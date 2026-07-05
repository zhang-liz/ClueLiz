import Testing
@testable import ClueLizCore

@Suite struct ChipDetectorTests {
    @Test func detectsQuestionMark() {
        let chips = ChipDetector.detectQuestions(in: "That's fine. What is the budget for Q3?")
        #expect(chips.map(\.text) == ["What is the budget for Q3?"])
        #expect(chips[0].kind == .question)
    }

    @Test func detectsInterrogativeWithoutMark() {
        let chips = ChipDetector.detectQuestions(in: "how does the pricing model work for enterprise")
        #expect(chips.map(\.text) == ["how does the pricing model work for enterprise?"])
    }

    @Test func ignoresStatementsAndShortFragments() {
        #expect(ChipDetector.detectQuestions(in: "We shipped it. Is it.").isEmpty)
        #expect(ChipDetector.detectQuestions(in: "The what now sounds fine to me").isEmpty)
    }

    @Test func dedup() {
        let chips = ChipDetector.detectQuestions(in: "What's the price? What's the price?")
        #expect(chips.count == 1)
    }

    @Test func detectsAcronyms() {
        let terms = ChipDetector.detectAcronyms(in: "We should use MCP with the K8S cluster")
        #expect(terms == ["MCP", "K8S"])
    }

    @Test func acronymsSkipStopwordsAndDedup() {
        let terms = ChipDetector.detectAcronyms(in: "OK so MCP and MCP again at 5 PM")
        #expect(terms == ["MCP"])
    }
}
