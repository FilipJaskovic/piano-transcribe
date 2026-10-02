import Darwin
import Foundation

struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    guard try condition() else { throw TestFailure(description: message) }
}

final class RecordedLines: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func append(_ line: String) { lock.withLock { lines.append(line) } }
    var value: [String] { lock.withLock { lines } }
}

@main
struct CoreTests {
    static var manager: FileManager { FileManager.default }
    static var python: URL { URL(fileURLWithPath: CommandLine.arguments[1]) }
    static var fixture: URL { URL(fileURLWithPath: CommandLine.arguments[2]) }

    static func main() async {
        let temporary = manager.temporaryDirectory.appendingPathComponent("piano-core-tests-\(UUID())")
        do {
            try manager.createDirectory(at: temporary, withIntermediateDirectories: true)
            defer { try? manager.removeItem(at: temporary) }
            try testInputValidation(in: temporary)
            try await testExports(in: temporary)
            try await testStreaming()
            try await testProcessFailures()
            try await testEarlyCancellation(in: temporary)
            try await testOutputPreflight(in: temporary)
            try await testService(in: temporary)
            print("All focused Swift core tests passed.")
        } catch {
            print("FAIL: \(error)")
            exit(1)
        }
    }

    static func testInputValidation(in root: URL) throws {
        for (name, expectedMessage) in [
            ("not-audio.mid", "MIDI files are not valid input"),
            ("protected.movpkg", "Apple Music packages are not supported")
        ] {
            let url = root.appendingPathComponent(name)
            try Data().write(to: url)
            do {
                try FileAccess.validateInput(url)
                throw TestFailure(description: "Unsupported input was accepted: \(name)")
            } catch let error as FileAccessError {
                try expect(error.localizedDescription.contains(expectedMessage), "Wrong user-facing input error: \(error)")
            }
        }
        let directory = root.appendingPathComponent("directory.wav")
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            try FileAccess.validateInput(directory)
            throw TestFailure(description: "An audio-named directory was accepted.")
        } catch FileAccessError.inputNotReadable {}
        print("PASS: MIDI/package rejection and regular-file validation")
    }

    static func testExports(in root: URL) async throws {
        let working = root.appendingPathComponent("working.mid")
        let target = root.appendingPathComponent("existing.mid")
        let previous = Data("previous-user-file".utf8)
        let replacement = Data("new-output".utf8)
        try previous.write(to: target)
        try replacement.write(to: working)
        let first = try FileAccess.saveOutput(working, to: target, originalSourceURL: working)
        let second = try FileAccess.saveOutput(working, to: target, originalSourceURL: working)
        try expect(first != target && second != target && first != second, "Exports must keep both on collisions.")
        try expect(try Data(contentsOf: target) == previous, "Export replaced an existing file.")
        try expect(try Data(contentsOf: first) == replacement, "Staged export contents differ.")
        do {
            _ = try FileAccess.saveOutput(root.appendingPathComponent("missing.mid"), to: target, originalSourceURL: working)
            throw TestFailure(description: "Saving a missing working output unexpectedly succeeded.")
        } catch is FileAccessError {}
        try expect(try Data(contentsOf: target) == previous, "Failed export damaged the previous file.")
        var cancellationChecks = 0
        do {
            _ = try FileAccess.saveOutput(working, to: target, originalSourceURL: working) {
                cancellationChecks += 1
                if cancellationChecks == 2 { throw CancellationError() }
            }
            throw TestFailure(description: "Export ignored cancellation before commit.")
        } catch is CancellationError {}
        try expect(try Data(contentsOf: target) == previous, "Cancellation damaged the previous file.")
        let concurrent = try await withThrowingTaskGroup(of: URL.self) { group in
            for _ in 0..<4 {
                group.addTask { try FileAccess.saveOutput(working, to: target, originalSourceURL: working) }
            }
            var outputs: [URL] = []
            for try await output in group { outputs.append(output) }
            return outputs
        }
        try expect(Set(concurrent).count == 4, "Concurrent exports collided.")
        for output in concurrent {
            try expect(try Data(contentsOf: output) == replacement, "Concurrent export is incomplete.")
        }
        let leakedStages = try manager.contentsOfDirectory(atPath: root.path).filter { $0.contains(".tmp") }
        try expect(leakedStages.isEmpty, "Failed save left temporary staging files.")
        print("PASS: non-destructive exports, collisions, and failed-save preservation")
    }

    static func testStreaming() async throws {
        let runner = ProcessRunner()
        let lines = RecordedLines()
        let diagnostics = try await runner.run(
            executableURL: python,
            arguments: [fixture.path, "--mode", "stream"],
            environment: [:],
            logHandler: { lines.append($0) }
        )
        let output = lines.value
        let expected = "caf\u{00e9} \u{1f3b9}"
        try expect(output.contains(where: { $0.contains(expected) }), "Split UTF-8 was corrupted or dropped.")
        try expect(!output.contains(where: { $0.contains("\u{fffd}") }), "A split UTF-8 codepoint became replacement characters.")
        struct Event: Decodable { let event: String }
        let events = output.compactMap { line -> String? in
            guard let data = line.data(using: .utf8) else { return nil }
            return (try? JSONDecoder().decode(Event.self, from: data))?.event
        }
        try expect(events == ["transcribing", "done"], "NDJSON records were split, merged, or tail lost: \(output)")
        try expect(output.contains("stderr-tail-without-newline"), "stderr tail was lost at process exit.")
        try expect(diagnostics.contains("done") && diagnostics.contains("stderr-tail-without-newline"), "Final diagnostics were truncated before the tail.")
        do {
            _ = try await runner.run(executableURL: python, arguments: [], environment: [:], logHandler: { _ in })
            throw TestFailure(description: "A job-owned ProcessRunner was reused.")
        } catch ProcessRunnerError.alreadyStarted {}
        print("PASS: split UTF-8, complete NDJSON, stdout/stderr final drain")
    }

    static func testProcessFailures() async throws {
        do {
            _ = try await ProcessRunner().run(
                executableURL: python, arguments: [fixture.path, "--mode", "failure"],
                environment: [:], logHandler: { _ in }
            )
            throw TestFailure(description: "Nonzero exit unexpectedly succeeded.")
        } catch ProcessRunnerError.exited(let code, let diagnostics) {
            try expect(code == 7 && diagnostics.contains("terminal-failure"), "Nonzero exit lost code or final diagnostics.")
        }
        do {
            _ = try await ProcessRunner().run(
                executableURL: python, arguments: [fixture.path, "--mode", "signal"],
                environment: [:], logHandler: { _ in }
            )
            throw TestFailure(description: "Killed worker unexpectedly succeeded.")
        } catch ProcessRunnerError.signalled(let signal, let diagnostics) {
            try expect(signal == SIGKILL && diagnostics.contains("signal-tail"), "Signal failure was misclassified.")
        }
        do {
            _ = try await ProcessRunner().run(
                executableURL: URL(fileURLWithPath: "/nonexistent/piano-test-python"), arguments: [],
                environment: [:], logHandler: { _ in }
            )
            throw TestFailure(description: "Missing executable unexpectedly launched.")
        } catch ProcessRunnerError.launchFailed {}
        print("PASS: nonzero exit, signal termination, and spawn failure")
    }

    static func testEarlyCancellation(in root: URL) async throws {
        let marker = root.appendingPathComponent("early-cancel-marker")
        let runner = ProcessRunner()
        runner.cancel()
        do {
            _ = try await runner.run(
                executableURL: python, arguments: [fixture.path, "--mode", "wait", "--marker", marker.path],
                environment: [:], logHandler: { _ in }
            )
            throw TestFailure(description: "Pre-cancelled process unexpectedly ran.")
        } catch is CancellationError {}
        try expect(!manager.fileExists(atPath: marker.path), "Cancellation before launch still started a worker.")
        print("PASS: cancellation before process launch")
    }

    static func testService(in root: URL) async throws {
        let cache = root.appendingPathComponent("jobs")
        let backend = PythonBackend(pythonExecutableURL: python, runnerScriptURL: fixture, ffmpegBinDirectoryURL: nil)
        let service = TranscriptionService(backendResolver: { backend }, jobsRootURL: cache)
        let source = root.appendingPathComponent("service-input.wav")
        let destination = root.appendingPathComponent("service-output.mid")
        func job() -> TranscriptionJob {
            TranscriptionJob(sourceURL: source, finalOutputURL: destination, device: .cpu, checkpoint: .packagedDefault)
        }
        try Data("mode:success".utf8).write(to: source)
        let completed = try await service.transcribe(job(), statusHandler: { _ in }, logHandler: { _ in })
        try FileAccess.validateMIDI(at: completed.midiURL)
        let existing = try Data(contentsOf: completed.midiURL)
        try assertEmptyCache(cache)

        for mode in ["invalid", "missing", "failure"] {
            try Data("mode:\(mode)".utf8).write(to: source)
            do {
                _ = try await service.transcribe(job(), statusHandler: { _ in }, logHandler: { _ in })
                throw TestFailure(description: "Bad backend output unexpectedly succeeded: \(mode)")
            } catch is TestFailure { throw TestFailure(description: "Bad backend output unexpectedly succeeded: \(mode)") }
            catch {}
            try expect(try Data(contentsOf: destination) == existing, "Backend failure damaged existing MIDI: \(mode)")
            try assertEmptyCache(cache)
        }

        let marker = root.appendingPathComponent("cancel-worker.pid")
        try Data("mode:wait:\(marker.path)".utf8).write(to: source)
        let waitingJob = job()
        let task = Task { try await service.transcribe(waitingJob, statusHandler: { _ in }, logHandler: { _ in }) }
        try await waitForFile(marker)
        let pidText = try String(contentsOf: marker, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let childPID = Int32(pidText) else { throw TestFailure(description: "Worker did not publish its PID.") }
        do {
            _ = try await service.transcribe(job(), statusHandler: { _ in }, logHandler: { _ in })
            throw TestFailure(description: "Overlapping job was accepted.")
        } catch TranscriptionServiceError.alreadyRunning {}
        task.cancel()
        await service.stop()
        do {
            _ = try await task.value
            throw TestFailure(description: "Cancelled service unexpectedly succeeded.")
        } catch is CancellationError {}
        try expect(kill(childPID, 0) == -1 && errno == ESRCH, "stop() returned before the cancelled worker died.")
        try assertEmptyCache(cache)
        try expect(try Data(contentsOf: destination) == existing, "Cancelled export damaged existing MIDI.")
        try Data("mode:success".utf8).write(to: source)
        let restarted = try await service.transcribe(job(), statusHandler: { _ in }, logHandler: { _ in })
        try expect(restarted.midiURL != destination, "Restart overwrote a prior export.")
        try FileAccess.validateMIDI(at: restarted.midiURL)
        try assertEmptyCache(cache)
        print("PASS: successful/failing job cleanup, cancellation teardown, guarded restart")
    }

    static func testOutputPreflight(in root: URL) async throws {
        let source = root.appendingPathComponent("preflight-input.wav")
        let previous = root.appendingPathComponent("previous-output.mid")
        let previousBytes = Data("previous-user-result".utf8)
        try Data("mode:success".utf8).write(to: source)
        try previousBytes.write(to: previous)
        let entriesBefore = Set(try manager.contentsOfDirectory(atPath: root.path))
        let resolutions = RecordedLines()
        let backend = PythonBackend(pythonExecutableURL: python, runnerScriptURL: fixture, ffmpegBinDirectoryURL: nil)
        let cache = root.appendingPathComponent("preflight-jobs")
        let service = TranscriptionService(backendResolver: {
            resolutions.append("called")
            return backend
        }, jobsRootURL: cache)
        // A regular file cannot contain an output child: deterministic even when tests run as root.
        let job = TranscriptionJob(sourceURL: source, finalOutputURL: previous.appendingPathComponent("output.mid"),
                                   device: .cpu, checkpoint: .packagedDefault)
        do {
            _ = try await service.transcribe(job, statusHandler: { _ in }, logHandler: { _ in })
            throw TestFailure(description: "An invalid output directory was accepted.")
        } catch is FileAccessError {}
        try expect(resolutions.value.isEmpty, "Output writability was checked only after resolving the backend.")
        try expect(try Data(contentsOf: previous) == previousBytes, "Output preflight damaged a previous result.")
        try expect(Set(try manager.contentsOfDirectory(atPath: root.path)) == entriesBefore, "Output preflight leaked probe or cache files.")
        print("PASS: output-directory preflight rejects before backend preparation")
    }

    static func assertEmptyCache(_ cache: URL) throws {
        guard manager.fileExists(atPath: cache.path) else { return }
        let children = try manager.contentsOfDirectory(atPath: cache.path)
        try expect(children.isEmpty, "Job cache leaked files: \(children)")
    }

    static func waitForFile(_ marker: URL) async throws {
        for _ in 0..<200 {
            if let data = try? Data(contentsOf: marker), !data.isEmpty { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw TestFailure(description: "Worker did not reach ready state.")
    }
}
