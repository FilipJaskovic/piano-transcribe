import Darwin
import Foundation

enum FileAccessError: LocalizedError {
    case unsupportedInputExtension(String)
    case inputNotReadable(String)
    case copyFailed(String)
    case outputWriteFailed(String)
    case invalidMIDI

    var errorDescription: String? {
        switch self {
        case .unsupportedInputExtension(let ext):
            if ext == "mid" || ext == "midi" {
                return "MIDI files are not valid input. Choose an audio file."
            }
            if ext == "movpkg" {
                return "Apple Music packages are not supported. Choose an unprotected audio file."
            }
            return "Unsupported input type: .\(ext). Choose an audio file."
        case .inputNotReadable(let name):
            return "The audio file cannot be read: \(name)."
        case .copyFailed(let message):
            return "Could not prepare the selected audio file. \(message)"
        case .outputWriteFailed(let message):
            return "Could not save the MIDI file. \(message)"
        case .invalidMIDI:
            return "The backend did not produce a valid MIDI file."
        }
    }
}

struct FileAccess {
    static func validateInput(_ sourceURL: URL) throws {
        let ext = sourceURL.pathExtension.lowercased()
        guard SupportedAudioTypes.extensions.contains(ext) else {
            throw FileAccessError.unsupportedInputExtension(ext.isEmpty ? "unknown" : ext)
        }
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }
        var isDirectory: ObjCBool = false
        guard sourceURL.isFileURL,
              FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              FileManager.default.isReadableFile(atPath: sourceURL.path) else {
            throw FileAccessError.inputNotReadable(sourceURL.lastPathComponent)
        }
    }

    static func prepareWorkingCopy(from sourceURL: URL, jobID: UUID, rootURL: URL? = nil) throws -> URL {
        try validateInput(sourceURL)
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }
        let jobDir = try jobDirectory(jobID: jobID, rootURL: rootURL)
        let destination = jobDir.appendingPathComponent(sourceURL.lastPathComponent)
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            return destination
        } catch {
            throw FileAccessError.copyFailed(error.localizedDescription)
        }
    }

    static func preflightOutput(to outputURL: URL, originalSourceURL: URL) throws {
        let folder = outputURL.deletingLastPathComponent()
        let accessedSource = originalSourceURL.startAccessingSecurityScopedResource()
        let accessedFolder = folder.startAccessingSecurityScopedResource()
        defer {
            if accessedSource { originalSourceURL.stopAccessingSecurityScopedResource() }
            if accessedFolder { folder.stopAccessingSecurityScopedResource() }
        }

        var isDirectory: ObjCBool = false
        guard outputURL.isFileURL,
              FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw FileAccessError.outputWriteFailed("The output folder is not available.")
        }

        // Test effective write access using only an exclusively created, app-owned probe.
        let probe = folder.appendingPathComponent(".piano-transcribe-\(UUID().uuidString).probe")
        let descriptor = probe.path.withCString { open($0, O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC, 0o600) }
        guard descriptor >= 0 else {
            let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            throw FileAccessError.outputWriteFailed("The output folder is not writable. \(error.localizedDescription)")
        }
        defer {
            _ = Darwin.close(descriptor)
            try? FileManager.default.removeItem(at: probe)
        }
        var byte: UInt8 = 0
        guard Darwin.write(descriptor, &byte, 1) == 1 else {
            let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            throw FileAccessError.outputWriteFailed("The output folder is not writable. \(error.localizedDescription)")
        }
    }

    // Commit a complete sibling staging file without overwriting an existing result.
    @discardableResult
    static func saveOutput(
        _ workingOutputURL: URL,
        to requestedOutputURL: URL,
        originalSourceURL: URL,
        cancellationCheck: () throws -> Void = { try Task.checkCancellation() }
    ) throws -> URL {
        let accessedSource = originalSourceURL.startAccessingSecurityScopedResource()
        let folder = requestedOutputURL.deletingLastPathComponent()
        let accessedFolder = folder.startAccessingSecurityScopedResource()
        let stagedURL = folder.appendingPathComponent(".piano-transcribe-\(UUID().uuidString).tmp")
        defer {
            try? FileManager.default.removeItem(at: stagedURL)
            if accessedSource { originalSourceURL.stopAccessingSecurityScopedResource() }
            if accessedFolder { folder.stopAccessingSecurityScopedResource() }
        }
        do {
            try cancellationCheck()
            try FileManager.default.copyItem(at: workingOutputURL, to: stagedURL)
            let base = requestedOutputURL.deletingPathExtension().lastPathComponent
            let ext = requestedOutputURL.pathExtension
            for index in 1...10_000 {
                try cancellationCheck()
                let candidate: URL
                if index == 1 {
                    candidate = requestedOutputURL
                } else {
                    let name = ext.isEmpty ? "\(base) (\(index))" : "\(base) (\(index)).\(ext)"
                    candidate = folder.appendingPathComponent(name)
                }
                let result = stagedURL.path.withCString { source in
                    candidate.path.withCString { destination in
                        renamex_np(source, destination, UInt32(RENAME_EXCL))
                    }
                }
                if result == 0 { return candidate }
                let code = errno
                if code != EEXIST { throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO) }
            }
            throw FileAccessError.outputWriteFailed("Too many files already use this name.")
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as FileAccessError {
            throw error
        } catch {
            throw FileAccessError.outputWriteFailed(error.localizedDescription)
        }
    }

    static func validateMIDI(at url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber, size.uint64Value >= 26 else {
            throw FileAccessError.invalidMIDI
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard let header = try handle.read(upToCount: 14), header.count == 14,
              Array(header.prefix(4)) == [0x4D, 0x54, 0x68, 0x64] else {
            throw FileAccessError.invalidMIDI
        }
        let headerLength = bigEndian32(header, at: 4)
        let format = UInt16(header[8]) << 8 | UInt16(header[9])
        let tracks = UInt16(header[10]) << 8 | UInt16(header[11])
        let division = UInt16(header[12]) << 8 | UInt16(header[13])
        guard headerLength >= 6, format <= 2, tracks > 0, division != 0,
              format != 0 || tracks == 1 else { throw FileAccessError.invalidMIDI }
        var position = UInt64(headerLength) + 8
        for _ in 0..<tracks {
            guard position + 8 <= size.uint64Value else { throw FileAccessError.invalidMIDI }
            try handle.seek(toOffset: position)
            guard let chunk = try handle.read(upToCount: 8), chunk.count == 8,
                  Array(chunk.prefix(4)) == [0x4D, 0x54, 0x72, 0x6B] else {
                throw FileAccessError.invalidMIDI
            }
            let length = bigEndian32(chunk, at: 4)
            position += UInt64(length) + 8
            guard length >= 4, position <= size.uint64Value else { throw FileAccessError.invalidMIDI }
        }
    }

    static func jobDirectory(jobID: UUID, rootURL: URL? = nil) throws -> URL {
        let root: URL
        if let rootURL {
            root = rootURL
        } else {
            let caches = try FileManager.default.url(
                for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            )
            root = caches.appendingPathComponent("PianoTranscribe", isDirectory: true)
                .appendingPathComponent("Jobs", isDirectory: true)
        }
        let directory = root.appendingPathComponent(jobID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func bigEndian32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) << 24 | UInt32(data[offset + 1]) << 16
            | UInt32(data[offset + 2]) << 8 | UInt32(data[offset + 3])
    }
}
