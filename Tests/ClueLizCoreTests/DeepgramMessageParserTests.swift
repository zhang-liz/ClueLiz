import Testing
import Foundation
@testable import ClueLizCore

@Suite struct DeepgramMessageParserTests {
    @Test func parsesFinalWithSpeaker() {
        let json = #"""
        {"type":"Results","is_final":true,"channel":{"alternatives":[{"transcript":"hello there",
         "words":[{"word":"hello","speaker":0},{"word":"there","speaker":0}]}]}}
        """#
        let r = DeepgramMessageParser.parse(Data(json.utf8))
        #expect(r == DeepgramResult(transcript: "hello there", isFinal: true, speakerID: 0))
    }

    @Test func majoritySpeakerWins() {
        let json = #"""
        {"type":"Results","is_final":false,"channel":{"alternatives":[{"transcript":"a b c",
         "words":[{"word":"a","speaker":1},{"word":"b","speaker":1},{"word":"c","speaker":0}]}]}}
        """#
        #expect(DeepgramMessageParser.parse(Data(json.utf8))?.speakerID == 1)
    }

    @Test func ignoresEmptyAndNonResults() {
        #expect(DeepgramMessageParser.parse(Data(#"{"type":"Metadata"}"#.utf8)) == nil)
        let empty = #"{"type":"Results","is_final":true,"channel":{"alternatives":[{"transcript":""}]}}"#
        #expect(DeepgramMessageParser.parse(Data(empty.utf8)) == nil)
    }
}
