import Testing
@testable import ClueLizCore

@Suite struct MarkdownBlockLineTests {
    @Test func headings() {
        #expect(MarkdownBlockLine.classify("# Title") == .heading(level: 1, text: "Title"))
        #expect(MarkdownBlockLine.classify("## Action Items") == .heading(level: 2, text: "Action Items"))
        #expect(MarkdownBlockLine.classify("###### Deep") == .heading(level: 6, text: "Deep"))
    }

    @Test func headingRequiresSpaceAfterHashes() {
        #expect(MarkdownBlockLine.classify("#hashtag") == .plain("#hashtag"))
        #expect(MarkdownBlockLine.classify("#") == .plain("#"))
    }

    @Test func sevenHashesIsNotAHeading() {
        #expect(MarkdownBlockLine.classify("####### nope") == .plain("####### nope"))
    }

    @Test func bullets() {
        #expect(MarkdownBlockLine.classify("- item") == .bullet(indent: 0, text: "item"))
        #expect(MarkdownBlockLine.classify("* item") == .bullet(indent: 0, text: "item"))
        #expect(MarkdownBlockLine.classify("+ item") == .bullet(indent: 0, text: "item"))
    }

    @Test func nestedBulletKeepsIndent() {
        #expect(MarkdownBlockLine.classify("  - nested") == .bullet(indent: 2, text: "nested"))
    }

    @Test func bulletRequiresSpaceAfterMarker() {
        #expect(MarkdownBlockLine.classify("-dash") == .plain("-dash"))
        #expect(MarkdownBlockLine.classify("-") == .plain("-"))
    }

    @Test func plainLines() {
        #expect(MarkdownBlockLine.classify("Just a sentence.") == .plain("Just a sentence."))
        #expect(MarkdownBlockLine.classify("") == .plain(""))
        #expect(MarkdownBlockLine.classify("1. numbered") == .plain("1. numbered"))
    }
}
