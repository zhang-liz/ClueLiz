import Testing
@testable import ClueLizCore

@Suite struct TranscriptStoreTests {
    @Test func partialCreatesMutableTurnPerSpeaker() {
        let s = TranscriptStore()
        s.applyPartial(speaker: .me, text: "hel")
        s.applyPartial(speaker: .me, text: "hello wor")
        #expect(s.turns.count == 1)
        #expect(s.turns[0].text == "hello wor")
        #expect(!s.turns[0].isFinal)
    }

    @Test func finalCommitsTurn() {
        let s = TranscriptStore()
        s.applyPartial(speaker: .me, text: "hello wor")
        s.applyFinal(speaker: .me, text: "Hello world.")
        #expect(s.turns.count == 1)
        #expect(s.turns[0].text == "Hello world.")
        #expect(s.turns[0].isFinal)
        // next partial starts a NEW turn
        s.applyPartial(speaker: .me, text: "again")
        #expect(s.turns.count == 2)
    }

    @Test func interleavedSpeakersKeepSeparatePartials() {
        let s = TranscriptStore()
        s.applyPartial(speaker: .me, text: "mine")
        s.applyPartial(speaker: .them(0), text: "theirs")
        s.applyPartial(speaker: .me, text: "mine more")
        #expect(s.turns.count == 2)
        #expect(s.turns.first(where: { $0.speaker == .me })?.text == "mine more")
    }

    @Test func emptyTextIgnored() {
        let s = TranscriptStore()
        s.applyPartial(speaker: .me, text: "  ")
        s.applyFinal(speaker: .me, text: "")
        #expect(s.turns.isEmpty)
    }

    @Test func contextTextTrimsFromFront() {
        let s = TranscriptStore()
        s.applyFinal(speaker: .me, text: "one two three")
        s.applyFinal(speaker: .them(0), text: "four five six")
        let ctx = s.contextText(maxWords: 5)
        #expect(!ctx.contains("one"))       // oldest trimmed
        #expect(ctx.contains("Them: four five six"))
    }

    @Test func contextTextAlwaysIncludesNewestTurn() {
        let s = TranscriptStore()
        s.applyFinal(speaker: .me, text: "one two three four five six seven eight")
        // Budget smaller than the only turn — still return it rather than nothing.
        #expect(s.contextText(maxWords: 3).contains("one two three"))
    }

    @Test func clearResetsTurnsAndPartials() {
        let s = TranscriptStore()
        s.applyPartial(speaker: .me, text: "partial")
        s.applyFinal(speaker: .them(0), text: "final")
        s.clear()
        #expect(s.turns.isEmpty)
        // A partial after clear() must open a fresh turn, not index into the old array.
        s.applyPartial(speaker: .me, text: "new partial")
        #expect(s.turns.count == 1)
        #expect(s.turns[0].text == "new partial")
    }

    @Test func speakerLabels() {
        #expect(Speaker.me.label == "Me")
        #expect(Speaker.them(0).label == "Them")
        #expect(Speaker.them(1).label == "Them 2")
    }
}
