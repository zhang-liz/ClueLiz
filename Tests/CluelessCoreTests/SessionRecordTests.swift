import Testing
import Foundation
@testable import CluelessCore

@Suite struct SessionRecordTests {
    @Test func codableRoundTrip() throws {
        var rec = SessionRecord(startedAt: Date(timeIntervalSince1970: 0))
        rec.turns = [TranscriptTurn(speaker: .me, text: "hi", isFinal: true)]
        rec.summaryMarkdown = "# Summary"
        let data = try JSONEncoder().encode(rec)
        let back = try JSONDecoder().decode(SessionRecord.self, from: data)
        #expect(back.turns[0].text == "hi")
        #expect(back.summaryMarkdown == "# Summary")
        #expect(back.endedAt == nil)
    }

    @Test func markdownExport() {
        var rec = SessionRecord(startedAt: Date())
        rec.turns = [TranscriptTurn(speaker: .me, text: "hello", isFinal: true)]
        rec.summaryMarkdown = "## Key Takeaways"
        let md = rec.markdownExport()
        #expect(md.contains("## Key Takeaways"))
        #expect(md.contains("Me: hello"))
    }
}
