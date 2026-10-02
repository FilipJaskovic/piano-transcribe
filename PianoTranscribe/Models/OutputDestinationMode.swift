import Foundation

enum OutputDestinationMode: String, CaseIterable, Identifiable, Sendable {
    case sourceFolder
    case customFolder

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sourceFolder:
            return "Audio folder"
        case .customFolder:
            return "Custom folder"
        }
    }
}

enum OutputDestinationError: LocalizedError {
    case customFolderMissing
    case customFolderUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .customFolderMissing:
            return "Choose a custom output folder in Settings before transcribing."
        case .customFolderUnavailable(let path):
            return "The custom output folder is not available: \(path)"
        }
    }
}
