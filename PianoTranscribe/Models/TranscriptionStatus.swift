import Foundation

enum TranscriptionStatus: Equatable {
    case idle
    case preparingBackend
    case copyingInput
    case separatingPiano
    case transcribing
    case savingOutput
    case completed(URL)
    case failed(String)
    case cancelled

    var isInProgress: Bool {
        switch self {
        case .preparingBackend, .copyingInput, .separatingPiano, .transcribing, .savingOutput:
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
        case .separatingPiano:
            "Separating piano"
        case .transcribing:
            "Transcribing"
        case .savingOutput:
            "Saving MIDI"
        case .completed:
            "Saved"
        case .failed:
            "Error"
        case .cancelled:
            "Cancelled"
        }
    }
}
