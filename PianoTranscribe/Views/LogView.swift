import SwiftUI

struct LogView: View {
    let lines: [String]
    @Binding var isExpanded: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ScrollView {
                Text(lines.isEmpty ? "No backend output yet." : lines.joined(separator: "\n"))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(height: 150)
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
        } label: {
            Label("Details", systemImage: "terminal")
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    LogView(lines: ["{\"event\":\"ready\"}"], isExpanded: .constant(true))
        .padding()
}
