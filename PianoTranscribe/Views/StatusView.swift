import SwiftUI

struct StatusView: View {
    let status: TranscriptionStatus
    var progress: Double? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(symbolColor)
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(status.title)
                    .font(.system(.body, weight: .medium))

                if let detail {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if status.isInProgress, let progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .accessibilityLabel(status.title)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var symbol: String {
        switch status {
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .cancelled, .cancelling: "stop.circle"
        case .idle: "circle"
        case .preparingBackend, .copyingInput: "waveform"
        case .transcribing: "pianokeys"
        case .savingOutput: "square.and.arrow.down"
        }
    }

    private var symbolColor: Color {
        switch status {
        case .completed: .green
        case .failed: .orange
        default: .secondary
        }
    }

    private var detail: String? {
        switch status {
        case .completed(let url): url.lastPathComponent
        case .failed(let message): message
        default: nil
        }
    }
}

#Preview {
    StatusView(status: .transcribing, progress: 0.45)
        .padding()
}
