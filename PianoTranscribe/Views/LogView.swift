import SwiftUI

struct LogView: View {
    let lines: [String]
    @Binding var isExpanded: Bool

    var body: some View {
        DisclosureGroup("Details", isExpanded: $isExpanded) {
            ScrollView([.horizontal, .vertical]) {
                Text(lines.joined(separator: "\n"))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(height: 144)
            .background(.background)
            .padding(.top, 8)
        }
        .controlSize(.small)
    }
}

#Preview {
    LogView(lines: ["{\"version\":1,\"event\":\"stage\",\"stage\":\"transcribing\"}"], isExpanded: .constant(true))
        .padding()
}
