import SwiftUI

struct DropZoneView: View {
    let isTargeted: Bool
    let chooseAudio: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: isTargeted ? "arrow.down.document" : "pianokeys")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                .accessibilityHidden(true)

            Text(isTargeted ? "Release to Transcribe" : "Piano Audio")
                .font(.title3.weight(.semibold))

            Button("Choose Audio...", action: chooseAudio)
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
    }
}

#Preview {
    DropZoneView(isTargeted: false, chooseAudio: {})
        .frame(width: 600, height: 240)
}
