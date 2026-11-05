import SwiftUI

/// Drop target for audio files. Clicking it opens the file importer.
struct DropZoneView: View {
    let isTargeted: Bool
    let isEnabled: Bool
    let chooseAudio: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12)

        Button(action: chooseAudio) {
            VStack(spacing: 10) {
                Image(systemName: isTargeted ? "arrow.down.circle.fill" : "waveform")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)

                Text(isTargeted ? "Release to transcribe" : "Drop audio here")
                    .font(.title3.weight(.semibold))

                Text("or click to choose. MP3, WAV, AIFF, M4A or FLAC.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 190, maxHeight: .infinity)
            .background {
                shape.fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.05))
            }
            .overlay {
                shape.strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                    style: StrokeStyle(lineWidth: isTargeted ? 2 : 1.5, dash: isTargeted ? [] : [7, 5])
                )
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
        .animation(.easeOut(duration: 0.16), value: isTargeted)
        .help("Choose an audio file")
    }
}

#Preview {
    DropZoneView(isTargeted: false, isEnabled: true, chooseAudio: {})
        .padding()
}
