import SwiftUI

struct DropZoneView: View {
    let isTargeted: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(
                isTargeted ? Color.accentColor : Color.secondary.opacity(0.45),
                style: StrokeStyle(lineWidth: 2, dash: [8, 6])
            )
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.05))
            }
            .frame(height: 190)
            .overlay {
                VStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .font(.system(size: 44))
                        .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)

                    Text(isTargeted ? "Release to transcribe" : "Drop audio here")
                        .font(.title3.weight(.medium))
                }
            }
            .animation(.easeOut(duration: 0.16), value: isTargeted)
    }
}

#Preview {
    DropZoneView(isTargeted: false)
        .padding()
}
