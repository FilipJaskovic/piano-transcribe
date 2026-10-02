import SwiftUI

struct StatusView: View {
    let status: TranscriptionStatus
    var progress: Double? = nil

    var body: some View {
        HStack(spacing: 10) {
            icon

            VStack(alignment: .leading, spacing: 3) {
                Text(status.title)
                    .font(.headline)

                if let detail {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            if status.isInProgress, let progress {
                ProgressView(value: progress)
                    .frame(width: 120)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var icon: some View {
        Group {
            switch status {
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            case .cancelled:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            case .idle:
                Image(systemName: "music.note")
                    .foregroundStyle(.secondary)
            case .preparingBackend, .copyingInput, .transcribing, .savingOutput, .cancelling:
                Image(systemName: "gearshape.2")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.title3)
        .frame(width: 24)
    }

    private var detail: String? {
        switch status {
        case .idle:
            "Choose or drop a piano audio file."
        case .preparingBackend:
            "Checking the local Python backend."
        case .copyingInput:
            "Copying the selected file into a job folder."
        case .transcribing:
            "Running Transkun V2."
        case .savingOutput:
            "Writing the MIDI file."
        case .completed(let url):
            url.lastPathComponent
        case .failed(let message):
            message
        case .cancelled:
            "The current job was stopped."
        case .cancelling:
            "Waiting for the backend to stop."
        }
    }
}

#Preview {
    StatusView(status: .idle)
        .padding()
}
