import Foundation

struct PythonBackend {
    let pythonExecutableURL: URL
    let runnerScriptURL: URL
    let ffmpegBinDirectoryURL: URL?
}

struct PianoSeparationBackend {
    let pythonExecutableURL: URL
    let runnerScriptURL: URL
    let repositoryURL: URL
}

enum PythonBackendError: LocalizedError {
    case backendNotFound([String])
    case runnerNotFound([String])
    case pianoSeparationBackendNotFound([String])
    case pianoSeparationRunnerNotFound([String])
    case pianoSeparationRepositoryNotFound([String])

    var errorDescription: String? {
        switch self {
        case .backendNotFound(let paths):
            return "Python backend was not found. Checked: \(paths.joined(separator: ", "))"
        case .runnerNotFound(let paths):
            return "Transkun runner script was not found. Checked: \(paths.joined(separator: ", "))"
        case .pianoSeparationBackendNotFound(let paths):
            return "Piano/orchestra separation backend was not found. Checked: \(paths.joined(separator: ", "))"
        case .pianoSeparationRunnerNotFound(let paths):
            return "Piano/orchestra separation runner script was not found. Checked: \(paths.joined(separator: ", "))"
        case .pianoSeparationRepositoryNotFound(let paths):
            return "pc-separation checkout was not found. Checked: \(paths.joined(separator: ", "))"
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

    static func resolvePianoSeparationBackend() throws -> PianoSeparationBackend {
        #if DEBUG
        return try resolveDebugPianoSeparationBackend()
        #else
        return try resolveReleasePianoSeparationBackend()
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

    private static func resolveDebugPianoSeparationBackend() throws -> PianoSeparationBackend {
        let environment = ProcessInfo.processInfo.environment
        let projectRoot = URL(fileURLWithPath: environment["PIANO_TRANSCRIBE_ROOT"] ?? FileManager.default.currentDirectoryPath, isDirectory: true)

        let runner = projectRoot.appendingPathComponent("Backend/pc_separator_runner.py")
        guard FileManager.default.fileExists(atPath: runner.path) else {
            throw PythonBackendError.pianoSeparationRunnerNotFound([runner.path])
        }

        var pythonCandidates: [URL] = []
        if let pythonPath = environment["PIANO_TRANSCRIBE_PC_SEPARATION_PYTHON"], !pythonPath.isEmpty {
            pythonCandidates.append(URL(fileURLWithPath: pythonPath))
        }
        pythonCandidates.append(projectRoot.appendingPathComponent(".pc-separation-env/bin/python"))
        pythonCandidates.append(projectRoot.appendingPathComponent(".venv-pc-separation/bin/python"))

        guard let python = pythonCandidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }) else {
            throw PythonBackendError.pianoSeparationBackendNotFound(pythonCandidates.map(\.path))
        }

        var repoCandidates: [URL] = []
        if let repoPath = environment["PIANO_TRANSCRIBE_PC_SEPARATION_ROOT"], !repoPath.isEmpty {
            repoCandidates.append(URL(fileURLWithPath: repoPath, isDirectory: true))
        }
        repoCandidates.append(projectRoot.appendingPathComponent("External/pc-separation", isDirectory: true))

        guard let repo = repoCandidates.first(where: {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("utils.py").path)
        }) else {
            throw PythonBackendError.pianoSeparationRepositoryNotFound(repoCandidates.map(\.path))
        }

        return PianoSeparationBackend(
            pythonExecutableURL: python,
            runnerScriptURL: runner,
            repositoryURL: repo
        )
    }

    private static func resolveReleasePianoSeparationBackend() throws -> PianoSeparationBackend {
        guard let resources = Bundle.main.resourceURL else {
            throw PythonBackendError.pianoSeparationBackendNotFound(["Bundle.main.resourceURL"])
        }

        let python = resources.appendingPathComponent("Backend/pc-separation-python/bin/python")
        let runner = resources.appendingPathComponent("Backend/pc_separator_runner.py")
        let repo = resources.appendingPathComponent("Backend/pc-separation")

        guard FileManager.default.isExecutableFile(atPath: python.path) else {
            throw PythonBackendError.pianoSeparationBackendNotFound([python.path])
        }
        guard FileManager.default.fileExists(atPath: runner.path) else {
            throw PythonBackendError.pianoSeparationRunnerNotFound([runner.path])
        }
        guard FileManager.default.fileExists(atPath: repo.appendingPathComponent("utils.py").path) else {
            throw PythonBackendError.pianoSeparationRepositoryNotFound([repo.path])
        }

        return PianoSeparationBackend(
            pythonExecutableURL: python,
            runnerScriptURL: runner,
            repositoryURL: repo
        )
    }
}
