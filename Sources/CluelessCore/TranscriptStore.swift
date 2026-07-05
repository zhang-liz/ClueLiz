import Foundation

/// Rolling transcript buffer. One mutable partial turn per speaker; finals commit in place.
/// Thread-safe; `onChange` fires on the mutating thread after each change.
public final class TranscriptStore {
    private let lock = NSLock()
    private var _turns: [TranscriptTurn] = []
    /// Index into `_turns` of the open (non-final) turn per speaker.
    private var openPartialIndex: [Speaker: Int] = [:]

    public var onChange: (() -> Void)?

    public init() {}

    public var turns: [TranscriptTurn] {
        lock.lock(); defer { lock.unlock() }
        return _turns
    }

    public func applyPartial(speaker: Speaker, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lock.lock()
        if let index = openPartialIndex[speaker] {
            _turns[index].text = trimmed
        } else {
            _turns.append(TranscriptTurn(speaker: speaker, text: trimmed, isFinal: false))
            openPartialIndex[speaker] = _turns.count - 1
        }
        lock.unlock()
        onChange?()
    }

    public func applyFinal(speaker: Speaker, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lock.lock()
        if let index = openPartialIndex[speaker] {
            _turns[index].text = trimmed
            _turns[index].isFinal = true
            openPartialIndex[speaker] = nil
        } else {
            _turns.append(TranscriptTurn(speaker: speaker, text: trimmed, isFinal: true))
        }
        lock.unlock()
        onChange?()
    }

    public func recentTurns(_ n: Int) -> [TranscriptTurn] {
        lock.lock(); defer { lock.unlock() }
        return Array(_turns.suffix(n))
    }

    /// Newest-last "Label: text" lines, trimmed from the front to fit `maxWords`.
    public func contextText(maxWords: Int) -> String {
        lock.lock(); defer { lock.unlock() }
        var lines: [String] = []
        var wordCount = 0
        for turn in _turns.reversed() {
            let line = "\(turn.speaker.label): \(turn.text)"
            let words = line.split(separator: " ").count
            if wordCount + words > maxWords { break }
            wordCount += words
            lines.append(line)
        }
        return lines.reversed().joined(separator: "\n")
    }

    public var fullText: String {
        lock.lock(); defer { lock.unlock() }
        return _turns.map { "\($0.speaker.label): \($0.text)" }.joined(separator: "\n")
    }
}
