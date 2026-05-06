import Foundation

typealias AudioProcessRunner = @Sendable (
    _ executableURL: URL,
    _ arguments: [String],
    _ environment: [String: String],
    _ logHandler: @escaping @Sendable (String) -> Void
) async throws -> String

protocol AudioPreprocessor: Sendable {
    var id: String { get }
    var displayName: String { get }
    var requiresProcessing: Bool { get }

    func process(
        inputURL: URL,
        jobDirectory: URL,
        logHandler: @escaping @Sendable (String) -> Void,
        processRunner: AudioProcessRunner
    ) async throws -> URL
}

struct NoOpPreprocessor: AudioPreprocessor {
    let id = "none"
    let displayName = "No preprocessing"
    let requiresProcessing = false

    func process(
        inputURL: URL,
        jobDirectory: URL,
        logHandler: @escaping @Sendable (String) -> Void,
        processRunner: AudioProcessRunner
    ) async throws -> URL {
        inputURL
    }
}

struct PianoConcertoSeparationPreprocessor: AudioPreprocessor {
    let id = "pc-separation"
    let displayName = "Separate piano from orchestra"
    let requiresProcessing = true

    func process(
        inputURL: URL,
        jobDirectory: URL,
        logHandler: @escaping @Sendable (String) -> Void,
        processRunner: AudioProcessRunner
    ) async throws -> URL {
        let backend = try PythonBackendManager.resolvePianoSeparationBackend()
        let outputURL = jobDirectory.appendingPathComponent("piano-separated.wav")

        logHandler("Starting piano/orchestra separation with pc-separation.")

        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        environment["PIANO_TRANSCRIBE_PC_SEPARATION_ROOT"] = backend.repositoryURL.path
        if let ffmpegDir = backend.ffmpegBinDirectoryURL {
            let existingPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
            environment["PATH"] = "\(ffmpegDir.path):\(existingPath)"
        }

        _ = try await processRunner(
            backend.pythonExecutableURL,
            [
                backend.runnerScriptURL.path,
                "--input", inputURL.path,
                "--output", outputURL.path,
                "--repo", backend.repositoryURL.path,
                "--model", "HDMC",
                "--device", "cpu"
            ],
            environment,
            logHandler
        )

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw AudioPreprocessorError.outputMissing
        }

        return outputURL
    }
}

enum AudioPreprocessorError: LocalizedError {
    case outputMissing

    var errorDescription: String? {
        switch self {
        case .outputMissing:
            "Piano/orchestra separation finished but did not create a piano stem."
        }
    }
}
