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
        preprocessor: AudioPreprocessor,
        statusHandler: @escaping @Sendable (TranscriptionStatus) -> Void,
        logHandler: @escaping @Sendable (String) -> Void
    ) async throws -> URL {
        statusHandler(.preparingBackend)
        let backend = try PythonBackendManager.resolveBackend()

        let jobID = UUID()
        statusHandler(.copyingInput)
        let workingInput = try FileAccess.prepareWorkingCopy(from: sourceURL, jobID: jobID)
        let jobDir = try FileAccess.jobDirectory(jobID: jobID)

        if preprocessor.requiresProcessing {
            statusHandler(.separatingPiano)
        }

        let processedInput = try await preprocessor.process(
            inputURL: workingInput,
            jobDirectory: jobDir,
            logHandler: logHandler,
            processRunner: runProcess
        )
        let workingOutput = jobDir.appendingPathComponent("output.mid")

        statusHandler(.transcribing)
        var environment = ProcessInfo.processInfo.environment
        if let ffmpegDir = backend.ffmpegBinDirectoryURL {
            let existingPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
            environment["PATH"] = "\(ffmpegDir.path):\(existingPath)"
        }
        environment["PYTHONUNBUFFERED"] = "1"
        environment["PYTHONDONTWRITEBYTECODE"] = "1"

        _ = try await runProcess(
            executableURL: backend.pythonExecutableURL,
            arguments: [
                backend.runnerScriptURL.path,
                "--input", processedInput.path,
                "--output", workingOutput.path,
                "--device", device.rawValue
            ],
            environment: environment,
            logHandler: logHandler
        )

        guard FileManager.default.fileExists(atPath: workingOutput.path) else {
            throw TranscriptionServiceError.outputMissing
        }

        statusHandler(.savingOutput)

        try FileAccess.saveOutput(workingOutput, to: finalOutputURL, originalSourceURL: sourceURL)
        return finalOutputURL
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
