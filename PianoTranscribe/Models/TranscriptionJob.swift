import Foundation

struct TranscriptionJob: Identifiable, Equatable {
    let id: UUID
    let sourceURL: URL
    let workingInputURL: URL
    let workingOutputURL: URL
    let finalOutputURL: URL
    var status: TranscriptionStatus

    init(sourceURL: URL, workingInputURL: URL, workingOutputURL: URL, finalOutputURL: URL) {
        self.id = UUID()
        self.sourceURL = sourceURL
        self.workingInputURL = workingInputURL
        self.workingOutputURL = workingOutputURL
        self.finalOutputURL = finalOutputURL
        self.status = .idle
    }
}
