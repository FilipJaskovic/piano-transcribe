import Foundation

struct PythonBackend {
    let pythonExecutableURL: URL
    let runnerScriptURL: URL
    let ffmpegBinDirectoryURL: URL?
}

enum PythonBackendError: LocalizedError {
    case backendNotFound([String])
    case runnerNotFound([String])

    var errorDescription: String? {
        switch self {
        case .backendNotFound(let paths):
            return "Python backend was not found. Checked: \(paths.joined(separator: ", "))"
        case .runnerNotFound(let paths):
            return "Transkun runner script was not found. Checked: \(paths.joined(separator: ", "))"
        }
    }
}

struct PythonBackendManager {
    static func resolveBackend() throws -> PythonBackend {
        #if DEBUG
        return try resolveDebugBackend()
        #else
        return try resolveReleaseBackend()
        #endif
    }

    private static func resolveDebugBackend() throws -> PythonBackend {
        let environment = ProcessInfo.processInfo.environment
        var candidateRoots: [URL] = []

        if let root = environment["PIANO_TRANSCRIBE_ROOT"], !root.isEmpty {
            candidateRoots.append(URL(fileURLWithPath: root, isDirectory: true))
        }

        candidateRoots.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true))

        let checkedPython = candidateRoots.map { $0.appendingPathComponent(".venv/bin/python").path }
        let checkedRunner = candidateRoots.map { $0.appendingPathComponent("Backend/transkun_runner.py").path }

        guard let rootWithPython = candidateRoots.first(where: {
            FileManager.default.isExecutableFile(atPath: $0.appendingPathComponent(".venv/bin/python").path)
        }) else {
            throw PythonBackendError.backendNotFound(checkedPython)
        }

        let runner = rootWithPython.appendingPathComponent("Backend/transkun_runner.py")
        guard FileManager.default.fileExists(atPath: runner.path) else {
            throw PythonBackendError.runnerNotFound(checkedRunner)
        }

        return PythonBackend(
            pythonExecutableURL: rootWithPython.appendingPathComponent(".venv/bin/python"),
            runnerScriptURL: runner,
            ffmpegBinDirectoryURL: nil
        )
    }

    private static func resolveReleaseBackend() throws -> PythonBackend {
        guard let resources = Bundle.main.resourceURL else {
            throw PythonBackendError.backendNotFound(["Bundle.main.resourceURL"])
        }

        let python = resources.appendingPathComponent("Backend/python/bin/python3.12")
        let runner = resources.appendingPathComponent("Backend/transkun_runner.py")
        let ffmpegDir = resources.appendingPathComponent("Backend/bin")

        guard FileManager.default.isExecutableFile(atPath: python.path) else {
            throw PythonBackendError.backendNotFound([python.path])
        }
        guard FileManager.default.fileExists(atPath: runner.path) else {
            throw PythonBackendError.runnerNotFound([runner.path])
        }

        return PythonBackend(
            pythonExecutableURL: python,
            runnerScriptURL: runner,
            ffmpegBinDirectoryURL: ffmpegDir
        )
    }
}
