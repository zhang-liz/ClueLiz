import Testing
@testable import CluelessCore

@Suite struct ContextStoreTests {
    @Test func combinedTextFormatsAndTruncates() {
        let s = ContextStore()
        s.add(ContextFile(name: "a.md", text: String(repeating: "x", count: 100)))
        s.add(ContextFile(name: "b.md", text: String(repeating: "y", count: 100)))
        let combined = s.combinedText(maxChars: 120)
        #expect(combined.contains("## a.md"))
        #expect(combined.contains("## b.md"))
        // headers/newlines excluded from the per-file text budget
        let bodyChars = combined.filter { $0 == "x" || $0 == "y" }.count
        #expect(bodyChars <= 120)
    }

    @Test func removeByID() {
        let s = ContextStore()
        let f = ContextFile(name: "a", text: "t")
        s.add(f)
        s.remove(id: f.id)
        #expect(s.files.isEmpty)
    }

    @Test func noTruncationWhenUnderBudget() {
        let s = ContextStore()
        s.add(ContextFile(name: "a", text: "short text"))
        #expect(s.combinedText(maxChars: 1000).contains("short text"))
    }
}
