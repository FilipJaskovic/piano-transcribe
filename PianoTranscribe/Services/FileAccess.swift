import Foundation

enum FileAccessError: LocalizedError {
    case unsupportedInputExtension(String)
    case copyFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedInputExtension(let ext):
            if ext == "mid" || ext == "midi" {
                return "MIDI files are not valid input. Choose an audio file."
            }
            return "Unsupported input type: .\(ext). Choose an audio file."
        case .copyFailed(let message):
            return "Could not copy the selected file into the app workspace. \(message)"
        }
    }
}

struct FileAccess {
    static func prepareWorkingCopy(from sourceURL: URL, jobID: UUID) throws -> URL {
        let ext = sourceURL.pathExtension.lowercased()
        guard SupportedAudioTypes.extensions.contains(ext) else {
            throw FileAccessError.unsupportedInputExtension(ext.isEmpty ? "unknown" : ext)
        }

        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let jobDir = try jobDirectory(jobID: jobID)
        let destURL = jobDir.appendingPathComponent(sourceURL.lastPathComponent)

        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            return destURL
        } catch {
            throw FileAccessError.copyFailed(error.localizedDescription)
        }
    }

    static func jobDirectory(jobID: UUID) throws -> URL {
        let caches = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let dir = caches
            .appendingPathComponent("PianoTranscribe", isDirectory: true)
            .appendingPathComponent("Jobs", isDirectory: true)
            .appendingPathComponent(jobID.uuidString, isDirectory: true)

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
