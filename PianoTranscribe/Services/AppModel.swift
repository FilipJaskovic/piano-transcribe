import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppModel {
    private let preferences: UserDefaults?
    private let transcriptionService = TranscriptionService()
    private var transcriptionTask: Task<Void, Never>?
    private var activeJobID: UUID?
    private var startupAutomationHandled = false

    private(set) var status: TranscriptionStatus = .idle
    private(set) var progress: Double?
    private(set) var logLines: [String] = []
    private(set) var isBenchmarkCheckpointAvailable = false
    var isImporterPresented = false
    var isDropTargeted = false
    var isLogExpanded = false
    var selectedDevice: TranskunDevice = .cpu {
        didSet { preferences?.set(selectedDevice.rawValue, forKey: "selectedDevice") }
    }
    var selectedCheckpoint: TranskunCheckpoint = .packagedDefault {
        didSet { preferences?.set(selectedCheckpoint.rawValue, forKey: "selectedCheckpoint") }
    }
    var outputDestinationMode: OutputDestinationMode = .sourceFolder {
        didSet { preferences?.set(outputDestinationMode.rawValue, forKey: "outputDestinationMode") }
    }
    var customOutputFolderURL: URL? {
        didSet { preferences?.set(customOutputFolderURL?.path, forKey: "customOutputFolderPath") }
    }

    init() {
        preferences = ProcessInfo.processInfo.environment["PIANO_TRANSCRIBE_TEST_MODE"] == "1"
            ? nil : .standard
        if let raw = preferences?.string(forKey: "selectedDevice"), let value = TranskunDevice(rawValue: raw) {
            selectedDevice = value
        }
        if let raw = preferences?.string(forKey: "selectedCheckpoint"), let value = TranskunCheckpoint(rawValue: raw) {
            selectedCheckpoint = value
        }
        if let raw = preferences?.string(forKey: "outputDestinationMode"), let value = OutputDestinationMode(rawValue: raw) {
            outputDestinationMode = value
        }
        if let path = preferences?.string(forKey: "customOutputFolderPath"), !path.isEmpty {
            customOutputFolderURL = URL(fileURLWithPath: path, isDirectory: true)
        }
        refreshBenchmarkCheckpointAvailability()
    }

    var isRunning: Bool { activeJobID != nil }
    var canCancel: Bool { isRunning && status != .cancelling }
    var customOutputFolderPath: String { customOutputFolderURL?.path ?? "No folder selected" }

    func presentImporter() {
        guard !isRunning else { return }
        isImporterPresented = true
    }

    func chooseCustomOutputFolder() {
        guard !isRunning else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        customOutputFolderURL = url
        outputDestinationMode = .customFolder
    }

    func clearCustomOutputFolder() {
        guard !isRunning else { return }
        customOutputFolderURL = nil
        outputDestinationMode = .sourceFolder
    }

    func transcribe(sourceURL: URL) { begin(sourceURL: sourceURL) }

    func cancel() {
        guard canCancel else { return }
        status = .cancelling
        transcriptionTask?.cancel()
        transcriptionService.cancel()
    }

    func stop() async {
        cancel()
        await transcriptionService.stop()
        await transcriptionTask?.value
    }

    func refreshBenchmarkCheckpointAvailability() {
        isBenchmarkCheckpointAvailable = PythonBackendManager.isTranskunBenchmarkCheckpointAvailable()
    }

    func handleImporterResult(_ result: Result<[URL], Error>) {
        guard !isRunning else { return }
        switch result {
        case .success(let urls):
            if let url = urls.first { transcribe(sourceURL: url) }
        case .failure(let error):
            if (error as NSError).code != NSUserCancelledError { showFailure(error.localizedDescription) }
        }
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !isRunning, let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, error in
            let url = Self.fileURL(from: item)
            let message = error?.localizedDescription
            Task { @MainActor in
                guard let self, !self.isRunning else { return }
                if let url { self.transcribe(sourceURL: url) }
                else { self.showFailure(message ?? "Could not read the dropped file.") }
            }
        }
        return true
    }

    // Test automation opts in explicitly and never changes the user's preferences.
    func runStartupAutomationIfNeeded() {
        let environment = ProcessInfo.processInfo.environment
        guard environment["PIANO_TRANSCRIBE_TEST_MODE"] == "1", !startupAutomationHandled,
              let input = environment["PIANO_TRANSCRIBE_AUTORUN_INPUT"] else { return }
        startupAutomationHandled = true
        selectedCheckpoint = environment["PIANO_TRANSCRIBE_AUTORUN_TRANSKUN_CHECKPOINT"]
            .flatMap(TranskunCheckpoint.init(rawValue:)) ?? .packagedDefault
        if let folder = environment["PIANO_TRANSCRIBE_AUTORUN_OUTPUT_FOLDER"] {
            customOutputFolderURL = URL(fileURLWithPath: folder, isDirectory: true)
            outputDestinationMode = .customFolder
        }
        begin(sourceURL: URL(fileURLWithPath: input),
            outputOverride: environment["PIANO_TRANSCRIBE_AUTORUN_OUTPUT"].map { URL(fileURLWithPath: $0) },
            reveal: environment["PIANO_TRANSCRIBE_AUTORUN_REVEAL"] != "0",
            resultFile: environment["PIANO_TRANSCRIBE_AUTORUN_RESULT_FILE"].map { URL(fileURLWithPath: $0) },
            quit: environment["PIANO_TRANSCRIBE_AUTORUN_QUIT"] == "1")
    }

    private func begin(sourceURL: URL, outputOverride: URL? = nil, reveal: Bool = true,
                       resultFile: URL? = nil, quit: Bool = false) {
        guard !isRunning else { return }
        logLines.removeAll()
        progress = nil
        let checkpoint = selectedCheckpoint
        do {
            guard sourceURL.isFileURL, SupportedAudioTypes.extensions.contains(sourceURL.pathExtension.lowercased()) else {
                throw FileAccessError.unsupportedInputExtension(sourceURL.pathExtension.lowercased())
            }
            refreshBenchmarkCheckpointAvailability()
            if checkpoint == .benchmarkV2 && !isBenchmarkCheckpointAvailable {
                throw PythonBackendError.transkunBenchmarkCheckpointNotFound
            }
            let job = TranscriptionJob(sourceURL: sourceURL,
                finalOutputURL: try resolvedOutputURL(for: sourceURL, override: outputOverride),
                device: selectedDevice, checkpoint: checkpoint)
            activeJobID = job.id
            status = .preparingBackend
            transcriptionTask = Task { [weak self] in
                await self?.run(job, reveal: reveal, resultFile: resultFile, quit: quit)
            }
        } catch {
            showFailure(error.localizedDescription)
            writeAutomationResult(.init(status: "failed", input: sourceURL.path,
                checkpoint: checkpoint.rawValue, message: error.localizedDescription, logs: logLines), to: resultFile)
            if quit { NSApp.terminate(nil) }
        }
    }

    private func run(_ job: TranscriptionJob, reveal: Bool, resultFile: URL?, quit: Bool) async {
        var automation = AutomationResult(status: "failed", input: job.sourceURL.path,
                                           checkpoint: job.checkpoint.rawValue)
        do {
            let result = try await transcriptionService.transcribe(job,
                statusHandler: { [weak self] status in
                    Task { @MainActor in
                        guard let self, self.activeJobID == job.id, self.status != .cancelling else { return }
                        self.status = status
                        self.progress = nil
                    }
                }, logHandler: { [weak self] line in
                    Task { @MainActor in
                        guard let self, self.activeJobID == job.id else { return }
                        self.receive(line)
                    }
                })
            status = .completed(result.midiURL)
            progress = 1
            automation.status = "completed"
            automation.output = result.midiURL.path
            automation.outputExists = FileManager.default.fileExists(atPath: result.midiURL.path)
            if reveal { NSWorkspace.shared.activateFileViewerSelecting([result.midiURL]) }
        } catch is CancellationError {
            status = .cancelled
            automation.status = "cancelled"
        } catch {
            appendLog(error.localizedDescription)
            let message: String
            if let processError = error as? ProcessRunnerError {
                switch processError {
                case .signalled(let signal, _):
                    message = signal == 9
                        ? "The backend was killed. Memory pressure may be the cause. Open Details for diagnostics."
                        : "The backend was stopped by signal \(signal). Open Details for diagnostics."
                case .exited(_, let diagnostics):
                    message = Self.backendFailure(in: diagnostics)
                        ?? "Transcription failed. Open Details for diagnostics."
                case .launchFailed, .alreadyStarted:
                    message = "Transcription failed. Open Details for diagnostics."
                }
            } else { message = error.localizedDescription }
            status = .failed(message)
            isLogExpanded = true
            automation.message = message
        }
        automation.logs = logLines
        activeJobID = nil
        transcriptionTask = nil
        writeAutomationResult(automation, to: resultFile)
        if quit { NSApp.terminate(nil) }
    }

    private func receive(_ line: String) {
        appendLog(line)
        guard status != .cancelling, let data = line.data(using: .utf8),
              let event = try? JSONDecoder().decode(BackendEvent.self, from: data), event.version == 1 else { return }
        if event.event == "stage" {
            switch event.stage {
            case "validating", "loading_model": status = .preparingBackend
            case "decoding": status = .copyingInput
            case "transcribing": status = .transcribing
            case "writing_midi": status = .savingOutput
            default: break
            }
            progress = nil
        }
        if event.event == "progress", let processed = event.processedSeconds, let total = event.totalSeconds,
           total > 0, processed.isFinite, total.isFinite {
            progress = min(1, max(0, processed / total))
        }
    }

    nonisolated private static func backendFailure(in diagnostics: String) -> String? {
        for line in diagnostics.split(separator: "\n").reversed() {
            guard let data = line.data(using: .utf8),
                  let event = try? JSONDecoder().decode(BackendEvent.self, from: data),
                  event.version == 1, event.event == "error", let message = event.message else { continue }
            return String(message.prefix(512))
        }
        return nil
    }

    private func appendLog(_ line: String) {
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        logLines.append(String(text.prefix(8192)))
        if logLines.count > 512 { logLines.removeFirst(logLines.count - 512) }
    }

    private func showFailure(_ message: String) {
        guard !isRunning else { return }
        status = .failed(message)
        appendLog(message)
        isLogExpanded = true
    }

    private func resolvedOutputURL(for input: URL, override: URL?) throws -> URL {
        if let override { return override }
        let folder: URL
        switch outputDestinationMode {
        case .sourceFolder: folder = input.deletingLastPathComponent()
        case .customFolder:
            guard let selected = customOutputFolderURL else { throw OutputDestinationError.customFolderMissing }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: selected.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw OutputDestinationError.customFolderUnavailable(selected.path)
            }
            folder = selected
        }
        return folder.appendingPathComponent("\(input.deletingPathExtension().lastPathComponent)-transkun.mid")
    }

    nonisolated private static func fileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL { return url }
        let string = (item as? String) ?? (item as? Data).flatMap { String(data: $0, encoding: .utf8) }
        return string.flatMap { URL(string: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private func writeAutomationResult(_ result: AutomationResult, to url: URL?) {
        guard let url else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(result).write(to: url, options: .atomic)
        } catch { appendLog("Could not write test result: \(error.localizedDescription)") }
    }
}

private struct BackendEvent: Decodable {
    let version: Int
    let event: String
    let stage: String?
    let message: String?
    let processedSeconds: Double?
    let totalSeconds: Double?
}

private struct AutomationResult: Encodable {
    var status: String
    let input: String
    let checkpoint: String
    var output: String?
    var outputExists: Bool?
    var message: String?
    var logs: [String] = []
}
