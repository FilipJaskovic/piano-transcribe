import Foundation

enum TranscriptionServiceError: LocalizedError {
    case alreadyRunning
    case outputMissing

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "A transcription is already running."
        case .outputMissing:
            return "The backend finished without creating a MIDI file."
        }
    }
}

struct TranscriptionResult: Sendable {
    let midiURL: URL
}

final class TranscriptionService: @unchecked Sendable {
    private let lock = NSLock()
    private var activeJob: ActiveJob?
    private let backendResolver: @Sendable () throws -> PythonBackend
    private let benchmarkDirectoryResolver: @Sendable () throws -> URL
    private let jobsRootURL: URL?

    init(
        backendResolver: @escaping @Sendable () throws -> PythonBackend = { try PythonBackendManager.resolveBackend() },
        benchmarkDirectoryResolver: @escaping @Sendable () throws -> URL = {
            try PythonBackendManager.resolveTranskunBenchmarkCheckpointDirectory()
        },
        jobsRootURL: URL? = nil
    ) {
        self.backendResolver = backendResolver
        self.benchmarkDirectoryResolver = benchmarkDirectoryResolver
        self.jobsRootURL = jobsRootURL
    }

    func cancel() {
        lock.withLocking { activeJob }?.runner.cancel()
    }

    func stop() async {
        guard let job = lock.withLocking({ activeJob }) else { return }
        job.runner.cancel()
        await job.waitUntilFinished()
    }

    func transcribe(
        _ job: TranscriptionJob,
        statusHandler: @escaping @Sendable (TranscriptionStatus) -> Void,
        logHandler: @escaping @Sendable (String) -> Void
    ) async throws -> TranscriptionResult {
        let operation = ActiveJob()
        try lock.withLocking {
            guard activeJob == nil else { throw TranscriptionServiceError.alreadyRunning }
            activeJob = operation
        }
        var jobDirectory: URL?
        defer {
            if let jobDirectory {
                do { try FileManager.default.removeItem(at: jobDirectory) }
                catch { logHandler("Temporary audio cleanup failed: \(error.localizedDescription)") }
            }
            lock.withLocking { activeJob = nil }
            operation.finish()
        }

        return try await withTaskCancellationHandler {
            try operation.runner.checkCancellation()
            try FileAccess.validateInput(job.sourceURL)
            try FileAccess.preflightOutput(to: job.finalOutputURL, originalSourceURL: job.sourceURL)
            try operation.runner.checkCancellation()
            statusHandler(.preparingBackend)
            let backend = try backendResolver()
            let benchmarkDirectory = job.checkpoint == .benchmarkV2 ? try benchmarkDirectoryResolver() : nil
            try operation.runner.checkCancellation()

            statusHandler(.copyingInput)
            let directory = try FileAccess.jobDirectory(jobID: job.id, rootURL: jobsRootURL)
            jobDirectory = directory
            let workingInput = try FileAccess.prepareWorkingCopy(
                from: job.sourceURL, jobID: job.id, rootURL: jobsRootURL
            )
            let workingOutput = directory.appendingPathComponent("output.mid")
            try operation.runner.checkCancellation()

            var arguments = [
                backend.runnerScriptURL.path,
                "--input", workingInput.path,
                "--output", workingOutput.path,
                "--device", job.device.rawValue,
                "--checkpoint", job.checkpoint.rawValue
            ]
            if let benchmarkDirectory { arguments += ["--checkpoint-dir", benchmarkDirectory.path] }
            if let ffmpeg = backend.ffmpegExecutableURL { arguments += ["--ffmpeg", ffmpeg.path] }
            if let ffprobe = backend.ffprobeExecutableURL { arguments += ["--ffprobe", ffprobe.path] }

            var environment = ProcessInfo.processInfo.environment
            for key in ["PYTHONHOME", "PYTHONPATH", "VIRTUAL_ENV", "CONDA_PREFIX"] {
                environment.removeValue(forKey: key)
            }
            if let ffmpegDirectory = backend.ffmpegBinDirectoryURL {
                environment["PATH"] = ffmpegDirectory.path + ":/usr/bin:/bin:/usr/sbin:/sbin"
            }
            environment["PYTHONUNBUFFERED"] = "1"
            environment["PYTHONDONTWRITEBYTECODE"] = "1"
            environment["PYTHONNOUSERSITE"] = "1"
            statusHandler(.transcribing)
            _ = try await operation.runner.run(
                executableURL: backend.pythonExecutableURL,
                arguments: arguments,
                environment: environment,
                logHandler: logHandler
            )
            try operation.runner.checkCancellation()
            guard FileManager.default.fileExists(atPath: workingOutput.path) else {
                throw TranscriptionServiceError.outputMissing
            }
            try FileAccess.validateMIDI(at: workingOutput)
            try operation.runner.checkCancellation()
            statusHandler(.savingOutput)
            let outputURL = try FileAccess.saveOutput(
                workingOutput,
                to: job.finalOutputURL,
                originalSourceURL: job.sourceURL,
                cancellationCheck: { try operation.runner.checkCancellation() }
            )
            // The atomic export is the commit point; a later cancel must not hide a saved result.
            return TranscriptionResult(midiURL: outputURL)
        } onCancel: {
            operation.runner.cancel()
        }
    }
}

private final class ActiveJob: @unchecked Sendable {
    let runner = ProcessRunner()
    private let lock = NSLock()
    private var finished = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func waitUntilFinished() async {
        await withCheckedContinuation { continuation in
            let completed = lock.withLocking {
                if finished { return true }
                waiters.append(continuation)
                return false
            }
            if completed { continuation.resume() }
        }
    }

    func finish() {
        let pending = lock.withLocking {
            finished = true
            let pending = waiters
            waiters.removeAll()
            return pending
        }
        for waiter in pending { waiter.resume() }
    }
}
