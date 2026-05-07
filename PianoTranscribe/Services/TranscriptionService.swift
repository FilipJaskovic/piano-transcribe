import Foundation

enum TranscriptionServiceError: LocalizedError {
    case processFailed(exitCode: Int32, output: String)
    case outputMissing

    var errorDescription: String? {
        switch self {
        case .processFailed(let code, let output):
            return "Transkun failed with exit code \(code).\n\(output)"
        case .outputMissing:
            return "Transkun finished but did not create a MIDI file."
        }
    }
}

struct TranscriptionResult: Sendable {
    let midiURL: URL
    let savedStemURLs: [URL]
}

final class TranscriptionService: @unchecked Sendable {
    private let processLock = NSLock()
    private var currentProcess: Process?

    func cancel() {
        processLock.withLocking {
            currentProcess?.terminate()
        }
    }

    func transcribe(
        sourceURL: URL,
        finalOutputURL: URL,
        device: TranskunDevice,
        checkpoint: TranskunCheckpoint,
        preprocessor: AudioPreprocessor,
        saveSeparatedStems: Bool,
        statusHandler: @escaping @Sendable (TranscriptionStatus) -> Void,
        logHandler: @escaping @Sendable (String) -> Void
    ) async throws -> TranscriptionResult {
        statusHandler(.preparingBackend)
        let backend = try PythonBackendManager.resolveBackend()

        let jobID = UUID()
        statusHandler(.copyingInput)
        let workingInput = try FileAccess.prepareWorkingCopy(from: sourceURL, jobID: jobID)
        let jobDir = try FileAccess.jobDirectory(jobID: jobID)

        if preprocessor.requiresProcessing {
            statusHandler(.separatingPiano)
        }

        let preprocessingResult = try await preprocessor.process(
            inputURL: workingInput,
            jobDirectory: jobDir,
            logHandler: logHandler,
            processRunner: runProcess
        )
        let processedInput = preprocessingResult.transcriptionInputURL
        let workingOutput = jobDir.appendingPathComponent("output.mid")

        statusHandler(.transcribing)
        let runnerArguments = try transkunRunnerArguments(
            runnerScriptURL: backend.runnerScriptURL,
            inputURL: processedInput,
            outputURL: workingOutput,
            device: device,
            checkpoint: checkpoint
        )
        var environment = ProcessInfo.processInfo.environment
        if let ffmpegDir = backend.ffmpegBinDirectoryURL {
            let existingPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
            environment["PATH"] = "\(ffmpegDir.path):\(existingPath)"
        }
        environment["PYTHONUNBUFFERED"] = "1"
        environment["PYTHONDONTWRITEBYTECODE"] = "1"

        _ = try await runProcess(
            executableURL: backend.pythonExecutableURL,
            arguments: runnerArguments,
            environment: environment,
            logHandler: logHandler
        )

        guard FileManager.default.fileExists(atPath: workingOutput.path) else {
            throw TranscriptionServiceError.outputMissing
        }

        statusHandler(.savingOutput)

        try FileAccess.saveOutput(workingOutput, to: finalOutputURL, originalSourceURL: sourceURL)
        var savedStemURLs: [URL] = []

        if saveSeparatedStems {
            for stem in preprocessingResult.separatedStems {
                let finalStemURL = finalSeparatedStemURL(
                    for: stem,
                    sourceURL: sourceURL,
                    finalOutputURL: finalOutputURL
                )
                try FileAccess.saveOutput(stem.workingURL, to: finalStemURL, originalSourceURL: sourceURL)
                savedStemURLs.append(finalStemURL)
                logHandler("Saved \(stem.displayName) stem: \(finalStemURL.path)")
            }
        }

        return TranscriptionResult(midiURL: finalOutputURL, savedStemURLs: savedStemURLs)
    }

    private func transkunRunnerArguments(
        runnerScriptURL: URL,
        inputURL: URL,
        outputURL: URL,
        device: TranskunDevice,
        checkpoint: TranskunCheckpoint
    ) throws -> [String] {
        var arguments = [
            runnerScriptURL.path,
            "--input", inputURL.path,
            "--output", outputURL.path,
            "--device", device.rawValue,
            "--checkpoint", checkpoint.rawValue
        ]

        if checkpoint == .benchmarkV2 {
            let checkpointDirectory = try PythonBackendManager.resolveTranskunBenchmarkCheckpointDirectory()
            arguments += ["--checkpoint-dir", checkpointDirectory.path]
        }

        return arguments
    }

    private func finalSeparatedStemURL(
        for stem: SeparatedStem,
        sourceURL: URL,
        finalOutputURL: URL
    ) -> URL {
        let base = sourceURL.deletingPathExtension().lastPathComponent
        let fileName = "\(base)-\(stem.fileSuffix).wav"
        return finalOutputURL.deletingLastPathComponent().appendingPathComponent(fileName)
    }

    private func runProcess(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        logHandler: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        let cancellationRequested = LockedFlag()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                let process = Process()
                setCurrentProcess(process)

                process.executableURL = executableURL
                process.arguments = arguments
                process.environment = environment

                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr

                let collected = LockedString()

                func stream(_ pipe: Pipe) {
                    pipe.fileHandleForReading.readabilityHandler = { handle in
                        let data = handle.availableData
                        guard !data.isEmpty else { return }
                        let text = String(decoding: data, as: UTF8.self)
                        collected.append(text)

                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            logHandler(trimmed)
                        }
                    }
                }

                stream(stdout)
                stream(stderr)

                process.terminationHandler = { [weak self] process in
                    stdout.fileHandleForReading.readabilityHandler = nil
                    stderr.fileHandleForReading.readabilityHandler = nil

                    self?.clearCurrentProcess(process)
                    let output = collected.value

                    if cancellationRequested.value {
                        continuation.resume(throwing: CancellationError())
                    } else if process.terminationStatus == 0 {
                        continuation.resume(returning: output)
                    } else {
                        continuation.resume(
                            throwing: TranscriptionServiceError.processFailed(
                                exitCode: process.terminationStatus,
                                output: output
                            )
                        )
                    }
                }

                do {
                    try process.run()
                } catch {
                    clearCurrentProcess(process)
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            cancellationRequested.setTrue()
            cancel()
        }
    }

    private func setCurrentProcess(_ process: Process) {
        processLock.withLocking {
            currentProcess = process
        }
    }

    private func clearCurrentProcess(_ process: Process) {
        processLock.withLocking {
            if currentProcess === process {
                currentProcess = nil
            }
        }
    }
}
