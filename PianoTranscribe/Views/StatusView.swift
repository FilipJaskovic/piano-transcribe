import AppKit
import SwiftUI

/// Status card: state icon (colored only for results), message, a static stage track while running, and Show in Finder when saved.
struct StatusView: View {
    let status: TranscriptionStatus
    var progress: Double? = nil

    private static let stages = ["Prepare", "Decode", "Transcribe", "Save"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(tint.opacity(0.15), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(status.title)
                        .font(.headline)

                    if let detail {
                        Text(detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                }

                Spacer()

                if case .completed(let url) = status {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } label: {
                        Label("Show in Finder", systemImage: "folder")
                    }
                }
            }

            if let stageIndex {
                stageTrack(current: stageIndex)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    /// Four segments: finished stages filled, the current one filled by processed audio when known.
    private func stageTrack(current: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(Self.stages.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: 5) {
                    GeometryReader { geometry in
                        Capsule()
                            .fill(.quaternary)
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(Color.accentColor.opacity(index == current && progress == nil ? 0.5 : 1))
                                    .frame(width: geometry.size.width * fill(for: index, current: current))
                            }
                    }
                    .frame(height: 4)

                    Text(Self.stages[index])
                        .font(.caption)
                        .foregroundStyle(index == current ? .primary : .secondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(status.title), step \(current + 1) of \(Self.stages.count)")
    }

    private func fill(for index: Int, current: Int) -> Double {
        if index < current { return 1 }
        if index > current { return 0 }
        return progress ?? 1
    }

    private var stageIndex: Int? {
        switch status {
        case .preparingBackend: 0
        case .copyingInput: 1
        case .transcribing: 2
        case .savingOutput: 3
        default: nil
        }
    }

    private var symbol: String {
        switch status {
        case .idle: "music.note"
        case .preparingBackend: "shippingbox"
        case .copyingInput: "waveform"
        case .transcribing: "pianokeys"
        case .savingOutput: "square.and.arrow.down"
        case .cancelling, .cancelled: "stop.fill"
        case .completed: "checkmark"
        case .failed: "exclamationmark"
        }
    }

    private var tint: Color {
        switch status {
        case .completed: .green
        case .failed: .red
        case .cancelling, .cancelled: .secondary
        default: .secondary
        }
    }

    private var detail: String? {
        switch status {
        case .idle:
            "Choose or drop a piano recording."
        case .preparingBackend:
            "Loading the transcription model."
        case .copyingInput:
            "Decoding the audio."
        case .transcribing:
            progress.map { "Running Transkun V2. \(Int(($0 * 100).rounded()))% of the audio processed." }
                ?? "Running Transkun V2."
        case .savingOutput:
            "Writing the MIDI file."
        case .completed(let url):
            url.lastPathComponent
        case .failed(let message):
            message
        case .cancelled:
            "The transcription was stopped."
        case .cancelling:
            "Waiting for the backend to stop."
        }
    }
}

#Preview {
    VStack {
        StatusView(status: .idle)
        StatusView(status: .transcribing, progress: 0.4)
        StatusView(status: .completed(URL(fileURLWithPath: "/tmp/Etude-transkun.mid")))
        StatusView(status: .failed("The backend was killed."))
    }
    .padding()
}
