import AppKit
import SwiftUI

/// Collapsible backend log. The whole header row toggles it; lines are JSON-highlighted.
struct LogView: View {
    let lines: [String]
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(spacing: 0) {
            header

            if isExpanded {
                Divider()
                output
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.easeOut(duration: 0.16)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "terminal")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 24)

                    Text("Details")
                        .font(.headline)

                    Text(lines.isEmpty ? "No output" : "\(lines.count) \(lines.count == 1 ? "line" : "lines")")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Hide details" : "Show details")

            if isExpanded {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .controlSize(.small)
                .disabled(lines.isEmpty)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var output: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if lines.isEmpty {
                        Text("No backend output yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        Text(LogHighlighter.highlight(line))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(index)
                    }
                }
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .padding(12)
            }
            .frame(height: 180)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
            .onAppear { proxy.scrollTo(lines.count - 1, anchor: .bottom) }
            .onChange(of: lines.count) { _, count in proxy.scrollTo(count - 1, anchor: .bottom) }
        }
    }
}

/// Colors one log line: JSON events get token colors, other lines are plain or marked as errors.
private enum LogHighlighter {
    private static let key = Color(nsColor: .systemTeal)
    private static let string = Color(nsColor: .systemOrange)
    private static let number = Color(nsColor: .systemPurple)
    private static let literal = Color(nsColor: .systemPink)
    private static let punctuation = Color.secondary
    private static let error = Color(nsColor: .systemRed)

    static func highlight(_ line: String) -> AttributedString {
        guard line.first == "{" || line.first == "[" else {
            var plain = AttributedString(line)
            if line.contains("Error") || line.hasPrefix("Traceback") { plain.foregroundColor = error }
            return plain
        }
        return json(line)
    }

    private static func json(_ line: String) -> AttributedString {
        var result = AttributedString()
        let characters = Array(line)
        var index = 0

        func append(_ text: some StringProtocol, _ color: Color?) {
            var run = AttributedString(String(text))
            if let color { run.foregroundColor = color }
            result += run
        }

        while index < characters.count {
            let character = characters[index]
            switch character {
            case "\"":
                var end = index + 1
                while end < characters.count, characters[end] != "\"" {
                    end += characters[end] == "\\" ? 2 : 1
                }
                end = min(end + 1, characters.count)
                // A string followed by a colon is an object key.
                var next = end
                while next < characters.count, characters[next] == " " { next += 1 }
                let isKey = next < characters.count && characters[next] == ":"
                append(String(characters[index..<end]), isKey ? key : string)
                index = end
            case "-", "0"..."9":
                var end = index + 1
                while end < characters.count, "0123456789.eE+-".contains(characters[end]) { end += 1 }
                append(String(characters[index..<end]), number)
                index = end
            case "{", "}", "[", "]", ",", ":":
                append(String(character), punctuation)
                index += 1
            case "t", "f", "n":
                let word = ["true", "false", "null"].first { word in
                    characters[index...].starts(with: word)
                }
                if let word {
                    append(word, literal)
                    index += word.count
                } else {
                    append(String(character), nil)
                    index += 1
                }
            default:
                append(String(character), nil)
                index += 1
            }
        }
        return result
    }
}

#Preview {
    LogView(lines: [
        #"{"version": 1, "event": "stage", "stage": "transcribing"}"#,
        #"{"version": 1, "event": "progress", "processedSeconds": 12.5, "totalSeconds": 60, "done": false}"#,
        "Traceback (most recent call last):",
    ], isExpanded: .constant(true))
    .padding()
}
