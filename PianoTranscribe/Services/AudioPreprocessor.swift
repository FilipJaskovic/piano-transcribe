import Foundation

protocol AudioPreprocessor {
    var id: String { get }
    var displayName: String { get }

    func process(inputURL: URL, jobDirectory: URL) async throws -> URL
}

struct NoOpPreprocessor: AudioPreprocessor {
    let id = "none"
    let displayName = "No preprocessing"

    func process(inputURL: URL, jobDirectory: URL) async throws -> URL {
        inputURL
    }
}

struct PianoConcertoSeparationPreprocessor: AudioPreprocessor {
    let id = "pc-separation"
    let displayName = "Separate piano from orchestra"

    func process(inputURL: URL, jobDirectory: URL) async throws -> URL {
        throw AudioPreprocessorError.notImplemented(displayName)
    }
}

enum AudioPreprocessorError: LocalizedError {
    case notImplemented(String)

    var errorDescription: String? {
        switch self {
        case .notImplemented(let name):
            "\(name) is planned for a later release."
        }
    }
}
