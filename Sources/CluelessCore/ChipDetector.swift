import Foundation

/// Cheap local detection of questions in transcript text — no LLM call.
public enum ChipDetector {
    private static let interrogatives: Set<String> = [
        "what", "how", "why", "when", "where", "who", "which",
        "can", "could", "should", "would", "do", "does", "did",
        "is", "are", "will"
    ]

    public static func detectQuestions(in text: String) -> [Chip] {
        var chips: [Chip] = []
        var seen = Set<String>()

        for sentence in splitSentences(text) {
            let trimmed = sentence.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let words = trimmed.split(separator: " ")
            guard words.count >= 3 else { continue }

            let endsWithMark = sentence.terminator == "?"
            let firstWord = words[0].lowercased().trimmingCharacters(in: .punctuationCharacters)
            let startsInterrogative = interrogatives.contains(firstWord)

            guard endsWithMark || startsInterrogative else { continue }

            var questionText = trimmed
            if !questionText.hasSuffix("?") { questionText += "?" }

            let dedupKey = questionText.lowercased()
            guard !seen.contains(dedupKey) else { continue }
            seen.insert(dedupKey)
            chips.append(Chip(kind: .question, text: questionText))
        }
        return chips
    }

    /// Conversational all-caps tokens that are not acronyms worth defining.
    private static let acronymStopwords: Set<String> = [
        "OK", "AM", "PM", "HI", "NO", "SO", "BYE", "YES", "A", "I"
    ]

    /// Detects acronym-like tokens (2–6 uppercase letters/digits) worth auto-defining.
    /// Order of first appearance, deduped.
    public static func detectAcronyms(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\b[A-Z][A-Z0-9]{1,5}\b"#) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var seen = Set<String>()
        var result: [String] = []
        for match in regex.matches(in: text, range: range) {
            guard let matchRange = Range(match.range, in: text) else { continue }
            let token = String(text[matchRange])
            guard !acronymStopwords.contains(token),
                  token.rangeOfCharacter(from: .letters) != nil,
                  !seen.contains(token) else { continue }
            seen.insert(token)
            result.append(token)
        }
        return result
    }

    private static func splitSentences(_ text: String) -> [(text: String, terminator: Character?)] {
        var sentences: [(String, Character?)] = []
        var current = ""
        for char in text {
            if char == "." || char == "?" || char == "!" {
                sentences.append((current, char))
                current = ""
            } else {
                current.append(char)
            }
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty {
            sentences.append((current, nil))
        }
        return sentences
    }
}
