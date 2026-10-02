import Darwin
import Foundation

enum ProcessRunnerError: LocalizedError {
    case alreadyStarted
    case launchFailed(String)
    case exited(code: Int32, diagnostics: String)
    case signalled(signal: Int32, diagnostics: String)

    var errorDescription: String? {
        switch self {
        case .alreadyStarted:
            return "This backend job has already started."
        case .launchFailed(let message):
            return "The transcription backend could not start. \(message)"
        case .exited(let code, let diagnostics):
            return "The transcription backend exited with code \(code).\n\(diagnostics)"
        case .signalled(let signal, let diagnostics):
            return "The transcription backend was stopped by signal \(signal).\n\(diagnostics)"
        }
    }
}

// A runner belongs to one job. Cancellation never targets a later job's process.
final class ProcessRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var hasStarted = false
    private var hasFinished = false
    private var cancellationRequested = false
    private var signalTarget: Int32?
    private var sentTermination = false
    private var killDeadline: UInt64?

    func checkCancellation() throws {
        try Task.checkCancellation()
        if lock.withLocking({ cancellationRequested }) { throw CancellationError() }
    }

    func cancel() {
        lock.withLocking { cancellationRequested = true }
        signalCancellationIfNeeded()
    }

    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        logHandler: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        try lock.withLocking {
            guard !hasStarted else { throw ProcessRunnerError.alreadyStarted }
            hasStarted = true
        }
        defer { lock.withLocking { hasFinished = true } }
        try checkCancellation()

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let diagnostics = DiagnosticCapture()
        let stdoutReader = Task.detached {
            await Self.readStream(stdout.fileHandleForReading, diagnostics: diagnostics, logHandler: logHandler)
        }
        let stderrReader = Task.detached {
            await Self.readStream(stderr.fileHandleForReading, diagnostics: diagnostics, logHandler: logHandler)
        }

        return try await withTaskCancellationHandler {
            do {
                let termination = try await launchAndWait(process)
                try? stdout.fileHandleForWriting.close()
                try? stderr.fileHandleForWriting.close()
                await stdoutReader.value
                await stderrReader.value
                await waitForCancelledProcessGroup()
                try checkCancellation()
                let output = diagnostics.value
                if termination.signalled {
                    throw ProcessRunnerError.signalled(signal: termination.status, diagnostics: output)
                }
                guard termination.status == 0 else {
                    throw ProcessRunnerError.exited(code: termination.status, diagnostics: output)
                }
                return output
            } catch {
                try? stdout.fileHandleForWriting.close()
                try? stderr.fileHandleForWriting.close()
                await stdoutReader.value
                await stderrReader.value
                await waitForCancelledProcessGroup()
                throw error
            }
        } onCancel: {
            cancel()
        }
    }

    private struct Termination: Sendable {
        let status: Int32
        let signalled: Bool
    }

    private func launchAndWait(_ process: Process) async throws -> Termination {
        try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                continuation.resume(returning: Termination(
                    status: process.terminationStatus,
                    signalled: process.terminationReason == .uncaughtSignal
                ))
            }
            do {
                try checkCancellation()
                try process.run()
                let pid = process.processIdentifier
                lock.withLocking {
                    // Foundation creates a process group on macOS; include decoder children.
                    signalTarget = getpgid(pid) == pid ? -pid : pid
                }
                signalCancellationIfNeeded()
            } catch is CancellationError {
                continuation.resume(throwing: CancellationError())
            } catch {
                continuation.resume(throwing: ProcessRunnerError.launchFailed(error.localizedDescription))
            }
        }
    }

    private func signalCancellationIfNeeded() {
        let shouldEscalate = lock.withLocking {
            guard cancellationRequested, !hasFinished, !sentTermination, let target = signalTarget else {
                return false
            }
            sentTermination = true
            killDeadline = DispatchTime.now().uptimeNanoseconds + 2_000_000_000
            _ = Darwin.kill(target, SIGTERM)
            return true
        }
        if shouldEscalate {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.lock.withLocking {
                    guard let self, !self.hasFinished, let target = self.signalTarget else { return }
                    _ = Darwin.kill(target, SIGKILL)
                }
            }
        }
    }

    private func waitForCancelledProcessGroup() async {
        let group = lock.withLocking { () -> (Int32, UInt64)? in
            guard cancellationRequested, let target = signalTarget, target < 0,
                  let killDeadline else { return nil }
            return (target, killDeadline)
        }
        guard let (target, deadline) = group else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .utility).async {
                // A decoder may outlive its Python parent after closing the parent's streams.
                var forced = false
                while Darwin.kill(target, 0) == 0 {
                    let now = DispatchTime.now().uptimeNanoseconds
                    if now >= deadline, !forced {
                        _ = Darwin.kill(target, SIGKILL)
                        forced = true
                    }
                    if now >= deadline + 500_000_000 { break }
                    Thread.sleep(forTimeInterval: 0.025)
                }
                continuation.resume()
            }
        }
    }

    private static func readStream(
        _ handle: FileHandle,
        diagnostics: DiagnosticCapture,
        logHandler: @escaping @Sendable (String) -> Void
    ) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .utility).async {
                defer {
                    try? handle.close()
                    continuation.resume()
                }
                var pending = Data()
                var discardingLongLine = false
                func emit(_ bytes: Data) {
                    let line = String(decoding: bytes, as: UTF8.self)
                    guard !line.isEmpty else { return }
                    diagnostics.append(line)
                    logHandler(line)
                }
                do {
                    while let data = try handle.read(upToCount: 4_096), !data.isEmpty {
                        for byte in data {
                            if byte == 10 || byte == 13 {
                                if !discardingLongLine { emit(pending) }
                                pending.removeAll(keepingCapacity: true)
                                discardingLongLine = false
                            } else if !discardingLongLine {
                                pending.append(byte)
                                if pending.count > 65_536 {
                                    emit(Data("Backend line exceeded 64 KiB and was discarded.".utf8))
                                    pending.removeAll(keepingCapacity: true)
                                    discardingLongLine = true
                                }
                            }
                        }
                    }
                    if !discardingLongLine { emit(pending) }
                } catch {
                    let message = "Could not read backend diagnostics: \(error.localizedDescription)"
                    diagnostics.append(message)
                    logHandler(message)
                }
            }
        }
    }
}

private final class DiagnosticCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = ""

    func append(_ line: String) {
        lock.withLocking {
            storage += line + "\n"
            if storage.utf8.count > 32_768 {
                var tail = Array(storage.utf8.suffix(32_768))
                while let first = tail.first, first & 0xC0 == 0x80 { tail.removeFirst() }
                storage = String(decoding: tail, as: UTF8.self)
            }
        }
    }

    var value: String { lock.withLocking { storage } }
}
