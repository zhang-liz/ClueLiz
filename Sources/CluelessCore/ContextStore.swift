import Foundation

/// An uploaded reference document, already reduced to plain text.
public struct ContextFile: Identifiable, Codable, Equatable {
    public let id: UUID
    public let name: String
    public let text: String

    public init(name: String, text: String) {
        self.id = UUID()
        self.name = name
        self.text = text
    }
}

/// Holds uploaded-file text and assembles the prompt-stuffing block.
/// Thread-safe.
public final class ContextStore {
    private let lock = NSLock()
    private var _files: [ContextFile] = []

    public var onChange: (() -> Void)?

    public init() {}

    public var files: [ContextFile] {
        lock.lock(); defer { lock.unlock() }
        return _files
    }

    public func add(_ file: ContextFile) {
        lock.lock()
        _files.append(file)
        lock.unlock()
        onChange?()
    }

    public func remove(id: UUID) {
        lock.lock()
        _files.removeAll { $0.id == id }
        lock.unlock()
        onChange?()
    }

    /// "## name\ntext" blocks. When over budget, each file gets a proportional
    /// share of `maxChars` for its text (headers not counted).
    public func combinedText(maxChars: Int) -> String {
        lock.lock(); defer { lock.unlock() }
        guard !_files.isEmpty else { return "" }

        let totalChars = _files.reduce(0) { $0 + $1.text.count }
        let blocks = _files.map { file -> String in
            var text = file.text
            if totalChars > maxChars {
                let share = Int(Double(maxChars) * Double(file.text.count) / Double(totalChars))
                text = String(text.prefix(max(share, 0)))
            }
            return "## \(file.name)\n\(text)"
        }
        return blocks.joined(separator: "\n\n")
    }
}
