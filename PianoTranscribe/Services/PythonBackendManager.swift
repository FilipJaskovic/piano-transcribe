import Foundation

struct PythonBackend: Sendable {
    let pythonExecutableURL: URL
    let runnerScriptURL: URL
    let ffmpegBinDirectoryURL: URL?

    var ffmpegExecutableURL: URL? { ffmpegBinDirectoryURL?.appendingPathComponent("ffmpeg") }
    var ffprobeExecutableURL: URL? { ffmpegBinDirectoryURL?.appendingPathComponent("ffprobe") }
}

enum PythonBackendError: LocalizedError {
    case backendNotFound
    case runnerNotFound
    case decoderNotFound
    case transkunBenchmarkCheckpointNotFound

    var errorDescription: String? {
        switch self {
        case .backendNotFound:
            "The Python runtime is missing or damaged. Reinstall Piano transcribe."
        case .runnerNotFound:
            "The transcription backend is missing or damaged. Reinstall Piano transcribe."
        case .decoderNotFound:
            "The bundled audio decoder is missing or damaged. Reinstall Piano transcribe."
        case .transkunBenchmarkCheckpointNotFound:
            "The benchmark checkpoint is not installed. Select Packaged default."
        }
    }
}

enum PythonBackendManager {
    static func resolveBackend() throws -> PythonBackend {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        let root = debugRoot
        let python = environment["PIANO_TRANSCRIBE_PYTHON"].map { URL(fileURLWithPath: $0) }
            ?? root.appendingPathComponent(".venv/bin/python")
        let runner = environment["PIANO_TRANSCRIBE_RUNNER"].map { URL(fileURLWithPath: $0) }
            ?? root.appendingPathComponent("Backend/transkun_runner.py")
        let decoderDirectory = environment["PIANO_TRANSCRIBE_FFMPEG_BIN"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        #else
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("Backend") else {
            throw PythonBackendError.backendNotFound
        }
        let python = root.appendingPathComponent("python/bin/python3.12")
        let runner = root.appendingPathComponent("transkun_runner.py")
        let decoderDirectory: URL? = root.appendingPathComponent("bin")
        guard let decoderDirectory,
              FileManager.default.isExecutableFile(atPath: decoderDirectory.appendingPathComponent("ffmpeg").path),
              FileManager.default.isExecutableFile(atPath: decoderDirectory.appendingPathComponent("ffprobe").path) else {
            throw PythonBackendError.decoderNotFound
        }
        #endif
        guard FileManager.default.isExecutableFile(atPath: python.path) else {
            throw PythonBackendError.backendNotFound
        }
        guard FileManager.default.fileExists(atPath: runner.path) else {
            throw PythonBackendError.runnerNotFound
        }
        return PythonBackend(pythonExecutableURL: python, runnerScriptURL: runner,
                             ffmpegBinDirectoryURL: decoderDirectory)
    }

    static func resolveTranskunBenchmarkCheckpointDirectory() throws -> URL {
        #if DEBUG
        let directory = ProcessInfo.processInfo.environment["PIANO_TRANSCRIBE_TRANSKUN_BENCHMARK_DIR"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? debugRoot.appendingPathComponent("External/transkun-checkpoints/benchmark-v2")
        #else
        guard let directory = Bundle.main.resourceURL?.appendingPathComponent("Backend/transkun-checkpoints/benchmark-v2") else {
            throw PythonBackendError.transkunBenchmarkCheckpointNotFound
        }
        #endif
        guard ["checkpoint.pt", "model.conf"].allSatisfy({ name in
            let file = directory.appendingPathComponent(name)
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return FileManager.default.isReadableFile(atPath: file.path) && size > 0
        }) else { throw PythonBackendError.transkunBenchmarkCheckpointNotFound }
        return directory
    }

    static func isTranskunBenchmarkCheckpointAvailable() -> Bool {
        (try? resolveTranskunBenchmarkCheckpointDirectory()) != nil
    }

    #if DEBUG
    private static var debugRoot: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["PIANO_TRANSCRIBE_ROOT"]
            ?? FileManager.default.currentDirectoryPath, isDirectory: true)
    }
    #endif
}
