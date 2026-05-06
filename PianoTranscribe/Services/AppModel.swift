import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppModel {
    var status: TranscriptionStatus = .idle
    var selectedDevice: TranskunDevice = .cpu
    var isPianoSeparationEnabled = false
    var shouldSaveSeparatedStems = true {
        didSet {
            UserDefaults.standard.set(shouldSaveSeparatedStems, forKey: SettingsKeys.shouldSaveSeparatedStems)
        }
    }
    var outputDestinationMode: OutputDestinationMode = .sourceFolder {
        didSet {
            UserDefaults.standard.set(outputDestinationMode.rawValue, forKey: SettingsKeys.outputDestinationMode)
        }
    }
    var customOutputFolderURL: URL? {
        didSet {
            if let path = customOutputFolderURL?.path {
                UserDefaults.standard.set(path, forKey: SettingsKeys.customOutputFolderPath)
            } else {
                UserDefaults.standard.removeObject(forKey: SettingsKeys.customOutputFolderPath)
            }
        }
    }
    var logLines: [String] = []
    var isImporterPresented = false
    var isDropTargeted = false
    var isLogExpanded = true
    var isPianoSeparationAvailable = false
    var pianoSeparationAvailabilityMessage = "Separator backend not installed."
    var pianoSeparationAvailabilityDetails: String?

    private let transcriptionService = TranscriptionService()
    private var transcriptionTask: Task<Void, Never>?
    private var startupAutomationHandled = false

    init() {
        let defaults = UserDefaults.standard

        if let rawMode = defaults.string(forKey: SettingsKeys.outputDestinationMode),
           let mode = OutputDestinationMode(rawValue: rawMode) {
            outputDestinationMode = mode
        }

        if let path = defaults.string(forKey: SettingsKeys.customOutputFolderPath), !path.isEmpty {
            customOutputFolderURL = URL(fileURLWithPath: path, isDirectory: true)
        }

        if defaults.object(forKey: SettingsKeys.shouldSaveSeparatedStems) != nil {
            shouldSaveSeparatedStems = defaults.bool(forKey: SettingsKeys.shouldSaveSeparatedStems)
        }

        refreshPianoSeparationAvailability()
    }

    var canCancel: Bool {
        status.isInProgress
    }

    var customOutputFolderPath: String {
        customOutputFolderURL?.path ?? "No folder selected"
    }

    func presentImporter() {
        isImporterPresented = true
    }

    func chooseCustomOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose where Piano transcribe should save MIDI files."

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        customOutputFolderURL = url
        outputDestinationMode = .customFolder
    }

    func clearCustomOutputFolder() {
        customOutputFolderURL = nil
        outputDestinationMode = .sourceFolder
    }

    func transcribe(sourceURL: URL) {
        guard !status.isInProgress else {
            appendLog("A transcription is already running.")
            return
        }

        refreshPianoSeparationAvailability()
        if isPianoSeparationEnabled && !isPianoSeparationAvailable {
            status = .failed(pianoSeparationAvailabilityMessage)
            appendLog(pianoSeparationAvailabilityMessage)
            if let details = pianoSeparationAvailabilityDetails,
               details != pianoSeparationAvailabilityMessage {
                appendLog(details)
            }
            return
        }

        logLines.removeAll()
        status = .copyingInput

        transcriptionTask = Task { [weak self] in
            await self?.runTranscription(
                sourceURL: sourceURL,
                finalOutputURL: nil,
                revealInFinder: true,
                automationResultURL: nil,
                quitWhenFinished: false
            )
        }
    }

    func runStartupAutomationIfNeeded() {
        guard !startupAutomationHandled else { return }

        let environment = ProcessInfo.processInfo.environment
        guard let inputPath = environment["PIANO_TRANSCRIBE_AUTORUN_INPUT"], !inputPath.isEmpty else {
            return
        }

        startupAutomationHandled = true

        let inputURL = URL(fileURLWithPath: inputPath)
        let outputURL = environment["PIANO_TRANSCRIBE_AUTORUN_OUTPUT"].flatMap {
            $0.isEmpty ? nil : URL(fileURLWithPath: $0)
        }
        let resultURL = environment["PIANO_TRANSCRIBE_AUTORUN_RESULT_FILE"].flatMap {
            $0.isEmpty ? nil : URL(fileURLWithPath: $0)
        }
        let revealInFinder = environment["PIANO_TRANSCRIBE_AUTORUN_REVEAL"] != "0"
        let quitWhenFinished = environment["PIANO_TRANSCRIBE_AUTORUN_QUIT"] == "1"
        isPianoSeparationEnabled = environment["PIANO_TRANSCRIBE_AUTORUN_PREPROCESSOR"] == "pc-separation"
        if let saveStems = environment["PIANO_TRANSCRIBE_AUTORUN_SAVE_STEMS"] {
            shouldSaveSeparatedStems = saveStems != "0"
        }

        if environment["PIANO_TRANSCRIBE_AUTORUN_OUTPUT_DESTINATION"] == "source-folder" {
            outputDestinationMode = .sourceFolder
        }

        if let outputFolderPath = environment["PIANO_TRANSCRIBE_AUTORUN_OUTPUT_FOLDER"], !outputFolderPath.isEmpty {
            customOutputFolderURL = URL(fileURLWithPath: outputFolderPath, isDirectory: true)
            outputDestinationMode = .customFolder
        }

        refreshPianoSeparationAvailability()
        logLines.removeAll()
        status = .copyingInput

        transcriptionTask = Task { [weak self] in
            await self?.runTranscription(
                sourceURL: inputURL,
                finalOutputURL: outputURL,
                revealInFinder: revealInFinder,
                automationResultURL: resultURL,
                quitWhenFinished: quitWhenFinished
            )
        }
    }

    func cancel() {
        transcriptionTask?.cancel()
        transcriptionService.cancel()
        status = .cancelled
        appendLog("Cancelled.")
    }

    func refreshPianoSeparationAvailability() {
        isPianoSeparationAvailable = PythonBackendManager.isPianoSeparationBackendAvailable()
        pianoSeparationAvailabilityMessage = PythonBackendManager.pianoSeparationUnavailableMessage()
            ?? "Separator backend installed."
        pianoSeparationAvailabilityDetails = PythonBackendManager.pianoSeparationUnavailableDetails()
    }

    func handleImporterResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                status = .failed("No file was selected.")
                return
            }
            transcribe(sourceURL: url)
        case .failure(let error):
            status = .failed(error.localizedDescription)
        }
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else {
            status = .failed("Drop an audio file.")
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, error in
            let loadedURL = Self.fileURL(from: item)
            let errorMessage = error?.localizedDescription

            Task { @MainActor in
                guard let self else { return }

                if let errorMessage {
                    self.status = .failed(errorMessage)
                    return
                }

                if let url = loadedURL {
                    self.transcribe(sourceURL: url)
                } else {
                    self.status = .failed("Could not read the dropped file URL.")
                }
            }
        }

        return true
    }

    private func runTranscription(
        sourceURL: URL,
        finalOutputURL: URL?,
        revealInFinder: Bool,
        automationResultURL: URL?,
        quitWhenFinished: Bool
    ) async {
        var attemptedOutputURL: URL?

        do {
            let outputURL = try resolvedOutputURL(for: sourceURL, override: finalOutputURL)
            attemptedOutputURL = outputURL
            let result = try await transcriptionService.transcribe(
                sourceURL: sourceURL,
                finalOutputURL: outputURL,
                device: selectedDevice,
                preprocessor: selectedPreprocessor,
                saveSeparatedStems: isPianoSeparationEnabled && shouldSaveSeparatedStems,
                statusHandler: { [weak self] status in
                    Task { @MainActor in
                        self?.status = status
                    }
                },
                logHandler: { [weak self] line in
                    Task { @MainActor in
                        self?.appendLog(line)
                    }
                }
            )

            status = .completed(result.midiURL)
            writeAutomationResult(
                status: "completed",
                sourceURL: sourceURL,
                outputURL: result.midiURL,
                stemOutputURLs: result.savedStemURLs,
                message: nil,
                resultURL: automationResultURL
            )

            if revealInFinder {
                NSWorkspace.shared.activateFileViewerSelecting([result.midiURL] + result.savedStemURLs)
            }
        } catch is CancellationError {
            status = .cancelled
            writeAutomationResult(
                status: "cancelled",
                sourceURL: sourceURL,
                outputURL: attemptedOutputURL,
                message: "Cancelled",
                resultURL: automationResultURL
            )
        } catch {
            let message = userFacingMessage(for: error)
            status = .failed(message)
            appendLog(error.localizedDescription)
            writeAutomationResult(
                status: "failed",
                sourceURL: sourceURL,
                outputURL: attemptedOutputURL,
                message: message,
                resultURL: automationResultURL
            )
        }

        if quitWhenFinished {
            NSApp.terminate(nil)
        }
    }

    private func appendLog(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        logLines.append(trimmed)
    }

    nonisolated private static func fileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }

        if let data = item as? Data,
           let string = String(data: data, encoding: .utf8) {
            return URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        if let string = item as? String {
            return URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return nil
    }

    private func resolvedOutputURL(for inputURL: URL, override: URL?) throws -> URL {
        if let override {
            return override
        }

        let fileName = Self.defaultOutputFileName(for: inputURL)

        switch outputDestinationMode {
        case .sourceFolder:
            return inputURL.deletingLastPathComponent().appendingPathComponent(fileName)
        case .customFolder:
            guard let folder = customOutputFolderURL else {
                throw OutputDestinationError.customFolderMissing
            }

            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                throw OutputDestinationError.customFolderUnavailable(folder.path)
            }

            return folder.appendingPathComponent(fileName)
        }
    }

    private static func defaultOutputFileName(for inputURL: URL) -> String {
        let base = inputURL.deletingPathExtension().lastPathComponent
        return "\(base)-transkun.mid"
    }

    private func userFacingMessage(for error: Error) -> String {
        if let serviceError = error as? TranscriptionServiceError {
            switch serviceError {
            case .processFailed:
                return "Transkun failed. Open Details for backend output."
            case .outputMissing:
                return serviceError.localizedDescription
            }
        }

        if let preprocessorError = error as? AudioPreprocessorError {
            switch preprocessorError {
            case .processFailed:
                return "Piano/orchestra separation failed. Open Details for backend output."
            case .outputMissing, .stemOutputMissing:
                return preprocessorError.localizedDescription
            }
        }

        if let backendError = error as? PythonBackendError {
            switch backendError {
            case .backendNotFound:
                return "Python backend was not found. Run the backend setup before transcribing."
            case .runnerNotFound:
                return "Transkun runner script was not found."
            case .pianoSeparationBackendNotFound:
                return "Piano/orchestra separation backend is missing or damaged."
            case .pianoSeparationRunnerNotFound:
                return "Piano/orchestra separation runner script was not found."
            case .pianoSeparationRepositoryNotFound:
                return "Bundled pc-separation files or HDMC checkpoint are missing."
            }
        }

        return error.localizedDescription
    }

    private enum SettingsKeys {
        static let outputDestinationMode = "outputDestinationMode"
        static let customOutputFolderPath = "customOutputFolderPath"
        static let shouldSaveSeparatedStems = "shouldSaveSeparatedStems"
    }

    private var selectedPreprocessor: AudioPreprocessor {
        if isPianoSeparationEnabled {
            return PianoConcertoSeparationPreprocessor()
        }

        return NoOpPreprocessor()
    }

    private func writeAutomationResult(
        status: String,
        sourceURL: URL,
        outputURL: URL?,
        stemOutputURLs: [URL] = [],
        message: String?,
        resultURL: URL?
    ) {
        guard let resultURL else { return }

        var payload: [String: Any] = [
            "status": status,
            "input": sourceURL.path,
            "logs": logLines
        ]

        if let outputURL {
            payload["output"] = outputURL.path
            payload["outputExists"] = FileManager.default.fileExists(atPath: outputURL.path)
        }

        if !stemOutputURLs.isEmpty {
            payload["stemOutputs"] = stemOutputURLs.map(\.path)
            payload["stemOutputExists"] = stemOutputURLs.allSatisfy { url in
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                    && !isDirectory.boolValue
            }
        }

        if let message {
            payload["message"] = message
        }

        do {
            try FileManager.default.createDirectory(
                at: resultURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: resultURL, options: .atomic)
        } catch {
            appendLog("Could not write automation result: \(error.localizedDescription)")
        }
    }
}
