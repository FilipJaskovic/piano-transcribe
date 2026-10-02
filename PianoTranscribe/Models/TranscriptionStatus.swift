import Foundation

enum TranscriptionStatus: Equatable, Sendable {
    case idle
    case preparingBackend
    case copyingInput
    case transcribing
    case savingOutput
    case cancelling
    case completed(URL)
    case failed(String)
    case cancelled

    var isInProgress: Bool {
        switch self {
        case .preparingBackend, .copyingInput, .transcribing, .savingOutput, .cancelling:
            true
        case .idle, .completed, .failed, .cancelled:
            false
        }
    }

    var title: String {
        switch self {
        case .idle:
            "Ready"
        case .preparingBackend:
            "Preparing backend"
        case .copyingInput:
            "Preparing audio"
        case .transcribing:
            "Transcribing"
        case .savingOutput:
            "Saving MIDI"
        case .cancelling:
            "Stopping"
        case .completed:
            "Saved"
        case .failed:
            "Error"
        case .cancelled:
            "Cancelled"
        }
    }
}
