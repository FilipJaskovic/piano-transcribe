import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppModel {
    var status: TranscriptionStatus = .idle
    var selectedDevice: TranskunDevice = .cpu
    var logLines: [String] = []
    var isImporterPresented = false
    var isDropTargeted = false
    var isLogExpanded = true

    private let transcriptionService = TranscriptionService()
    private var transcriptionTask: Task<Void, Never>?

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
            await self?.runTranscription(sourceURL: sourceURL)
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

    private func runTranscription(sourceURL: URL) async {
        do {
            let outputURL = try Self.defaultOutputURL(for: sourceURL)
            let result = try await transcriptionService.transcribe(
                sourceURL: sourceURL,
                finalOutputURL: outputURL,
                device: selectedDevice,
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
            NSWorkspace.shared.activateFileViewerSelecting([result])
        } catch is CancellationError {
            status = .cancelled
        } catch {
            status = .failed(error.localizedDescription)
            appendLog(error.localizedDescription)
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
}
