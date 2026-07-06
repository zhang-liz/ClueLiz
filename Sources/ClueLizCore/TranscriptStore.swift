import Foundation

/// Rolling transcript buffer. One mutable partial turn per stream; finals commit in place.
/// Thread-safe; `onChange` fires on the mutating thread after each change.
public final class TranscriptStore {
    /// The capture stream a speaker belongs to: `.me` is the mic, `.them(_)` the system tap.
    private enum StreamKey: Hashable {
        case mic
        case system

        init(_ speaker: Speaker) {
            switch speaker {
            case .me: self = .mic
            case .them: self = .system
            }
        }
    }

    private let lock = NSLock()
    private var _turns: [TranscriptTurn] = []
    /// Index into `_turns` of the open (non-final) turn per stream. Keyed by
    /// stream rather than speaker: diarization can relabel the system speaker
    /// between interims and finals (e.g. `.them(0)` → `.them(1)`), and a
    /// per-speaker key would leave the interim's partial open (and duplicated
    /// in every LLM context) forever.
    private var openPartialIndex: [StreamKey: Int] = [:]

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
        if let index = openPartialIndex[StreamKey(speaker)] {
            _turns[index].speaker = speaker   // adopt the latest diarization label
            _turns[index].text = trimmed
        } else {
            _turns.append(TranscriptTurn(speaker: speaker, text: trimmed, isFinal: false))
            openPartialIndex[StreamKey(speaker)] = _turns.count - 1
        }
        lock.unlock()
        onChange?()
    }

    public func applyFinal(speaker: Speaker, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lock.lock()
        if let index = openPartialIndex[StreamKey(speaker)] {
            _turns[index].speaker = speaker   // finals carry the authoritative label
            _turns[index].text = trimmed
            _turns[index].isFinal = true
            openPartialIndex[StreamKey(speaker)] = nil
        } else {
            _turns.append(TranscriptTurn(speaker: speaker, text: trimmed, isFinal: true))
        }
        lock.unlock()
        onChange?()
    }

    /// Wipes all turns — call between sessions so a new meeting starts clean.
    public func clear() {
        lock.lock()
        _turns.removeAll()
        openPartialIndex.removeAll()
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
            // Always include the newest line, even if it alone exceeds the budget —
            // an empty context is worse than a slightly oversized one.
            if wordCount + words > maxWords, !lines.isEmpty { break }
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
