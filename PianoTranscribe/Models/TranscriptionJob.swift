import Foundation

struct TranscriptionJob: Identifiable, Sendable {
    let id: UUID
    let sourceURL: URL
    let finalOutputURL: URL
    let device: TranskunDevice
    let checkpoint: TranskunCheckpoint

    init(
        id: UUID = UUID(),
        sourceURL: URL,
        finalOutputURL: URL,
        device: TranskunDevice,
        checkpoint: TranskunCheckpoint
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.finalOutputURL = finalOutputURL
        self.device = device
        self.checkpoint = checkpoint
    }
}
