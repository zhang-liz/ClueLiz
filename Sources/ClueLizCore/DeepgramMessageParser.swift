import Foundation

/// A parsed Deepgram transcription result.
public struct DeepgramResult: Equatable {
    public let transcript: String
    public let isFinal: Bool
    public let speakerID: Int?

    public init(transcript: String, isFinal: Bool, speakerID: Int?) {
        self.transcript = transcript
        self.isFinal = isFinal
        self.speakerID = speakerID
    }
}

/// Parses Deepgram live-streaming JSON messages. Returns nil for non-Results
/// messages and empty transcripts. Speaker = majority speaker over words.
public enum DeepgramMessageParser {
    private struct Message: Decodable {
        let type: String?
        let is_final: Bool?
        let channel: Channel?

        struct Channel: Decodable {
            let alternatives: [Alternative]
        }
        struct Alternative: Decodable {
            let transcript: String
            let words: [Word]?
        }
        struct Word: Decodable {
            let word: String
            let speaker: Int?
        }
    }

    public static func parse(_ data: Data) -> DeepgramResult? {
        guard let message = try? JSONDecoder().decode(Message.self, from: data),
              message.type == "Results",
              let alternative = message.channel?.alternatives.first,
              !alternative.transcript.isEmpty else { return nil }

        var speakerID: Int?
        if let words = alternative.words, !words.isEmpty {
            var counts: [Int: Int] = [:]
            for word in words {
                if let speaker = word.speaker {
                    counts[speaker, default: 0] += 1
                }
            }
            speakerID = counts.max(by: { $0.value < $1.value })?.key
        }

        return DeepgramResult(transcript: alternative.transcript,
                              isFinal: message.is_final ?? false,
                              speakerID: speakerID)
    }
}
