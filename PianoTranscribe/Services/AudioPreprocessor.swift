import Foundation

typealias AudioProcessRunner = @Sendable (
    _ executableURL: URL,
    _ arguments: [String],
    _ environment: [String: String],
    _ logHandler: @escaping @Sendable (String) -> Void
) async throws -> String

struct AudioPreprocessingResult: Sendable {
    let transcriptionInputURL: URL
    let separatedStems: [SeparatedStem]
}

struct SeparatedStem: Sendable {
    enum Kind: String, Sendable {
        case piano
        case orchestra

        var displayName: String {
            switch self {
            case .piano:
                return "piano"
            case .orchestra:
                return "orchestra"
            }
        }

        var fileSuffix: String {
            switch self {
            case .piano:
                return "piano-separated"
            case .orchestra:
                return "orchestra-separated"
            }
        }
    }

    let kind: Kind
    let workingURL: URL

    var displayName: String { kind.displayName }
    var fileSuffix: String { kind.fileSuffix }
}

protocol AudioPreprocessor: Sendable {
    var id: String { get }
    var displayName: String { get }
    var requiresProcessing: Bool { get }

    func process(
        inputURL: URL,
        jobDirectory: URL,
        logHandler: @escaping @Sendable (String) -> Void,
        processRunner: AudioProcessRunner
    ) async throws -> AudioPreprocessingResult
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
    ) async throws -> AudioPreprocessingResult {
        AudioPreprocessingResult(transcriptionInputURL: inputURL, separatedStems: [])
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
    ) async throws -> AudioPreprocessingResult {
        let backend = try PythonBackendManager.resolvePianoSeparationBackend()
        let pianoOutputURL = jobDirectory.appendingPathComponent("piano-separated.wav")
        let orchestraOutputURL = jobDirectory.appendingPathComponent("orchestra-separated.wav")

        logHandler("Starting piano/orchestra separation with pc-separation.")

        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        environment["PIANO_TRANSCRIBE_PC_SEPARATION_ROOT"] = backend.repositoryURL.path
        if let ffmpegDir = backend.ffmpegBinDirectoryURL {
            let existingPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
            environment["PATH"] = "\(ffmpegDir.path):\(existingPath)"
        }

        do {
            _ = try await processRunner(
                backend.pythonExecutableURL,
                [
                    backend.runnerScriptURL.path,
                    "--input", inputURL.path,
                    "--output", pianoOutputURL.path,
                    "--orchestra-output", orchestraOutputURL.path,
                    "--repo", backend.repositoryURL.path,
                    "--model", "HDMC",
                    "--device", "cpu"
                ],
                environment,
                logHandler
            )
        } catch let error as TranscriptionServiceError {
            switch error {
            case .processFailed(let exitCode, let output):
                throw AudioPreprocessorError.processFailed(exitCode: exitCode, output: output)
            case .outputMissing:
                throw error
            }
        }

        guard FileManager.default.fileExists(atPath: pianoOutputURL.path) else {
            throw AudioPreprocessorError.stemOutputMissing("piano")
        }

        guard FileManager.default.fileExists(atPath: orchestraOutputURL.path) else {
            throw AudioPreprocessorError.stemOutputMissing("orchestra")
        }

        return AudioPreprocessingResult(
            transcriptionInputURL: pianoOutputURL,
            separatedStems: [
                SeparatedStem(kind: .piano, workingURL: pianoOutputURL),
                SeparatedStem(kind: .orchestra, workingURL: orchestraOutputURL)
            ]
        )
    }
}

enum AudioPreprocessorError: LocalizedError {
    case processFailed(exitCode: Int32, output: String)
    case outputMissing
    case stemOutputMissing(String)

    var errorDescription: String? {
        switch self {
        case .processFailed(let exitCode, let output):
            "Piano/orchestra separation failed with exit code \(exitCode).\n\(output)"
        case .outputMissing:
            "Piano/orchestra separation finished but did not create a piano stem."
        case .stemOutputMissing(let stemName):
            "Piano/orchestra separation finished but did not create the \(stemName) stem."
        }
    }
}
