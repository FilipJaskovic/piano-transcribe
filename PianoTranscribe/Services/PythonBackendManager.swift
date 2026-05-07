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
    let ffmpegBinDirectoryURL: URL?
}

enum PythonBackendError: LocalizedError {
    case backendNotFound([String])
    case runnerNotFound([String])
    case pianoSeparationBackendNotFound([String])
    case pianoSeparationRunnerNotFound([String])
    case pianoSeparationRepositoryNotFound([String])
    case transkunBenchmarkCheckpointNotFound([String])

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
        case .transkunBenchmarkCheckpointNotFound(let paths):
            return "Transkun benchmark checkpoint was not found. Checked: \(paths.joined(separator: ", "))"
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

    static func isPianoSeparationBackendAvailable() -> Bool {
        (try? resolvePianoSeparationBackend()) != nil
    }

    static func resolveTranskunBenchmarkCheckpointDirectory() throws -> URL {
        #if DEBUG
        return try resolveDebugTranskunBenchmarkCheckpointDirectory()
        #else
        return try resolveReleaseTranskunBenchmarkCheckpointDirectory()
        #endif
    }

    static func isTranskunBenchmarkCheckpointAvailable() -> Bool {
        (try? resolveTranskunBenchmarkCheckpointDirectory()) != nil
    }

    static func transkunBenchmarkCheckpointUnavailableMessage() -> String? {
        do {
            _ = try resolveTranskunBenchmarkCheckpointDirectory()
            return nil
        } catch {
            #if DEBUG
            return "Benchmark checkpoint not installed."
            #else
            return "Bundled benchmark checkpoint is missing or damaged."
            #endif
        }
    }

    static func transkunBenchmarkCheckpointUnavailableDetails() -> String? {
        do {
            _ = try resolveTranskunBenchmarkCheckpointDirectory()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    static func pianoSeparationUnavailableMessage() -> String? {
        do {
            _ = try resolvePianoSeparationBackend()
            return nil
        } catch let error as PythonBackendError {
            switch error {
            case .pianoSeparationBackendNotFound,
                 .pianoSeparationRunnerNotFound,
                 .pianoSeparationRepositoryNotFound:
                #if DEBUG
                return "Separator backend not installed."
                #else
                return "Piano/orchestra separation backend is missing or damaged."
                #endif
            default:
                return nil
            }
        } catch {
            return "Separator backend not installed."
        }
    }

    static func pianoSeparationUnavailableDetails() -> String? {
        do {
            _ = try resolvePianoSeparationBackend()
            return nil
        } catch {
            return error.localizedDescription
        }
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

        let pythonCandidates = [
            resources.appendingPathComponent("Backend/python/bin/python3.12"),
            resources.appendingPathComponent("Backend/python/bin/python3"),
            resources.appendingPathComponent("Backend/python/bin/python")
        ]
        let runner = resources.appendingPathComponent("Backend/transkun_runner.py")
        let ffmpegDir = resources.appendingPathComponent("Backend/bin")

        guard let python = pythonCandidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }) else {
            throw PythonBackendError.backendNotFound(pythonCandidates.map(\.path))
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

        guard let repo = repoCandidates.first(where: isValidPianoSeparationRepository(_:)) else {
            throw PythonBackendError.pianoSeparationRepositoryNotFound(
                repoCandidates.flatMap { checkedPianoSeparationRepositoryPaths($0) }
            )
        }

        return PianoSeparationBackend(
            pythonExecutableURL: python,
            runnerScriptURL: runner,
            repositoryURL: repo,
            ffmpegBinDirectoryURL: nil
        )
    }

    private static func resolveReleasePianoSeparationBackend() throws -> PianoSeparationBackend {
        guard let resources = Bundle.main.resourceURL else {
            throw PythonBackendError.pianoSeparationBackendNotFound(["Bundle.main.resourceURL"])
        }

        let pythonCandidates = [
            resources.appendingPathComponent("Backend/pc-separation-python/bin/python3.10"),
            resources.appendingPathComponent("Backend/pc-separation-python/bin/python3"),
            resources.appendingPathComponent("Backend/pc-separation-python/bin/python")
        ]
        let runner = resources.appendingPathComponent("Backend/pc_separator_runner.py")
        let repo = resources.appendingPathComponent("Backend/pc-separation")
        let ffmpegDir = resources.appendingPathComponent("Backend/bin")

        guard let python = pythonCandidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }) else {
            throw PythonBackendError.pianoSeparationBackendNotFound(pythonCandidates.map(\.path))
        }
        guard FileManager.default.fileExists(atPath: runner.path) else {
            throw PythonBackendError.pianoSeparationRunnerNotFound([runner.path])
        }
        guard isValidPianoSeparationRepository(repo) else {
            throw PythonBackendError.pianoSeparationRepositoryNotFound(
                checkedPianoSeparationRepositoryPaths(repo)
            )
        }

        return PianoSeparationBackend(
            pythonExecutableURL: python,
            runnerScriptURL: runner,
            repositoryURL: repo,
            ffmpegBinDirectoryURL: ffmpegDir
        )
    }

    private static func isValidPianoSeparationRepository(_ repo: URL) -> Bool {
        checkedPianoSeparationRepositoryPaths(repo).allSatisfy {
            FileManager.default.fileExists(atPath: $0)
        }
    }

    private static func checkedPianoSeparationRepositoryPaths(_ repo: URL) -> [String] {
        [
            repo.appendingPathComponent("utils.py").path,
            repo.appendingPathComponent("config/cfg_hdemucs.yaml").path,
            repo.appendingPathComponent("checkpoints/HDMC20_R_H_HU_HUS/hdemucs_best.pth").path
        ]
    }

    private static func resolveDebugTranskunBenchmarkCheckpointDirectory() throws -> URL {
        let environment = ProcessInfo.processInfo.environment
        let projectRoot = URL(fileURLWithPath: environment["PIANO_TRANSCRIBE_ROOT"] ?? FileManager.default.currentDirectoryPath, isDirectory: true)

        var candidates: [URL] = []
        if let checkpointPath = environment["PIANO_TRANSCRIBE_TRANSKUN_BENCHMARK_DIR"], !checkpointPath.isEmpty {
            candidates.append(URL(fileURLWithPath: checkpointPath, isDirectory: true))
        }
        candidates.append(projectRoot.appendingPathComponent("External/transkun-checkpoints/benchmark-v2", isDirectory: true))

        guard let directory = candidates.first(where: isValidTranskunBenchmarkCheckpointDirectory(_:)) else {
            throw PythonBackendError.transkunBenchmarkCheckpointNotFound(
                candidates.flatMap { checkedTranskunBenchmarkCheckpointPaths($0) }
            )
        }

        return directory
    }

    private static func resolveReleaseTranskunBenchmarkCheckpointDirectory() throws -> URL {
        guard let resources = Bundle.main.resourceURL else {
            throw PythonBackendError.transkunBenchmarkCheckpointNotFound(["Bundle.main.resourceURL"])
        }

        let directory = resources.appendingPathComponent("Backend/transkun-checkpoints/benchmark-v2", isDirectory: true)
        guard isValidTranskunBenchmarkCheckpointDirectory(directory) else {
            throw PythonBackendError.transkunBenchmarkCheckpointNotFound(
                checkedTranskunBenchmarkCheckpointPaths(directory)
            )
        }

        return directory
    }

    private static func isValidTranskunBenchmarkCheckpointDirectory(_ directory: URL) -> Bool {
        checkedTranskunBenchmarkCheckpointPaths(directory).allSatisfy {
            FileManager.default.fileExists(atPath: $0)
        }
    }

    private static func checkedTranskunBenchmarkCheckpointPaths(_ directory: URL) -> [String] {
        [
            directory.appendingPathComponent("checkpoint.pt").path,
            directory.appendingPathComponent("model.conf").path
        ]
    }
}
