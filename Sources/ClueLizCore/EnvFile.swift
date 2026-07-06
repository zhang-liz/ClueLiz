import Foundation

/// Minimal dotenv-format parser and editor.
///
/// Supports `KEY=VALUE` lines, blank lines, `#` comments, an optional
/// `export ` prefix, and single- or double-quoted values. Editing preserves
/// unrelated lines and comments.
public enum EnvFile {
    /// Parses dotenv text into a dictionary. Later duplicate keys win.
    public static func parse(_ text: String) -> [String: String] {
        var values: [String: String] = [:]
        for rawLine in text.components(separatedBy: .newlines) {
            guard let (key, value) = parseLine(rawLine) else { continue }
            values[key] = value
        }
        return values
    }

    /// Returns `text` with `key` set to `value` (replacing an existing line or
    /// appending), or with the key's line removed when `value` is nil.
    public static func updating(_ text: String, key: String, value: String?) -> String {
        var lines = text.isEmpty ? [] : text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }

        var replaced = false
        lines = lines.compactMap { line in
            guard parseLine(line)?.key == key else { return line }
            guard let value, !replaced else { return nil }
            replaced = true
            return "\(key)=\(value)"
        }
        if let value, !replaced {
            lines.append("\(key)=\(value)")
        }
        return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    }

    private static func parseLine(_ rawLine: String) -> (key: String, value: String)? {
        var line = rawLine.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, !line.hasPrefix("#") else { return nil }
        if line.hasPrefix("export ") {
            line = String(line.dropFirst("export ".count)).trimmingCharacters(in: .whitespaces)
        }
        guard let eq = line.firstIndex(of: "=") else { return nil }
        let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return nil }
        var value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
        if value.count >= 2,
           (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
            value = String(value.dropFirst().dropLast())
        }
        return (key, value)
    }
}
