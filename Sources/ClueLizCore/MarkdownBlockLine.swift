import Foundation

/// Block-level role of one line of Markdown. SwiftUI `Text` only renders inline
/// Markdown, so UI layers classify lines with this and style headings/bullets
/// by hand.
public enum MarkdownBlockLine: Equatable {
    case heading(level: Int, text: String)
    case bullet(indent: Int, text: String)
    case plain(String)

    public static func classify(_ line: String) -> MarkdownBlockLine {
        // Heading: 1–6 leading '#' followed by a space.
        if line.hasPrefix("#") {
            let hashes = line.prefix(while: { $0 == "#" })
            let rest = line.dropFirst(hashes.count)
            if hashes.count <= 6, rest.first == " " {
                return .heading(level: hashes.count,
                                text: rest.trimmingCharacters(in: .whitespaces))
            }
        }
        // Bullet: optional indentation, then '-', '*', or '+' and a space.
        let indent = line.prefix(while: { $0 == " " }).count
        let unindented = line.drop(while: { $0 == " " })
        if let marker = unindented.first, "-*+".contains(marker),
           unindented.dropFirst().first == " " {
            return .bullet(indent: indent, text: String(unindented.dropFirst(2)))
        }
        return .plain(line)
    }
}
