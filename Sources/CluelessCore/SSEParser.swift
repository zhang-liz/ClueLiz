import Foundation

/// Incremental Server-Sent Events parser. Feed raw bytes, get back complete
/// `data:` payloads. Handles payloads split across feeds; skips `event:`/`id:`/
/// comment lines and the literal `[DONE]` sentinel.
public struct SSEParser {
    private var buffer = ""

    public init() {}

    public mutating func feed(_ data: Data) -> [String] {
        buffer += String(decoding: data, as: UTF8.self)

        var payloads: [String] = []
        var lines = buffer.components(separatedBy: "\n")
        // Last element is either "" (buffer ended in \n) or an incomplete line — keep it.
        buffer = lines.removeLast()

        for line in lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            guard !payload.isEmpty, payload != "[DONE]" else { continue }
            payloads.append(payload)
        }
        return payloads
    }
}
