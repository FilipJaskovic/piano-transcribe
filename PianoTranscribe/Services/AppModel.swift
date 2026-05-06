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
    var logLines: [String] = []
    var isImporterPresented = false
    var isDropTargeted = false
    var isLogExpanded = true

    private let transcriptionService = TranscriptionService()
    private var transcriptionTask: Task<Void, Never>?
    private var startupAutomationHandled = false

    var canCancel: Bool {
        status.isInProgress
    }

    func presentImporter() {
        isImporterPresented = true
    }

    func transcribe(sourceURL: URL) {
        guard !status.isInProgress else {
            appendLog("A transcription is already running.")
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
        var resolvedOutputURL: URL?

        do {
            let outputURL = try finalOutputURL ?? Self.defaultOutputURL(for: sourceURL)
            resolvedOutputURL = outputURL
            let result = try await transcriptionService.transcribe(
                sourceURL: sourceURL,
                finalOutputURL: outputURL,
                device: selectedDevice,
                preprocessor: selectedPreprocessor,
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

            status = .completed(result)
            writeAutomationResult(
                status: "completed",
                sourceURL: sourceURL,
                outputURL: result,
                message: nil,
                resultURL: automationResultURL
            )

            if revealInFinder {
                NSWorkspace.shared.activateFileViewerSelecting([result])
            }
        } catch is CancellationError {
            status = .cancelled
            writeAutomationResult(
                status: "cancelled",
                sourceURL: sourceURL,
                outputURL: resolvedOutputURL,
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
                outputURL: resolvedOutputURL,
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

    private static func defaultOutputURL(for inputURL: URL) throws -> URL {
        let base = inputURL.deletingPathExtension().lastPathComponent
        let folder = inputURL.deletingLastPathComponent()
        return folder.appendingPathComponent("\(base)-transkun.mid")
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

        if let backendError = error as? PythonBackendError {
            switch backendError {
            case .backendNotFound:
                return "Python backend was not found. Run the backend setup before transcribing."
            case .runnerNotFound:
                return "Transkun runner script was not found."
            case .pianoSeparationBackendNotFound:
                return "Piano/orchestra separation needs its separate backend. Run Packaging/build_pc_separation_dev.sh first."
            case .pianoSeparationRunnerNotFound:
                return "Piano/orchestra separation runner script was not found."
            case .pianoSeparationRepositoryNotFound:
                return "pc-separation checkout was not found. Run Packaging/build_pc_separation_dev.sh first."
            }
        }

        return error.localizedDescription
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
