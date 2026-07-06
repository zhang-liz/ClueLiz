import Testing
@testable import ClueLizCore

@Suite struct EnvFileTests {
    @Test func parsesKeysCommentsAndQuotes() {
        let text = """
        # keys
        DEEPGRAM_API_KEY=abc123
        export GEMINI_API_KEY = 'g-key'
        claude-api-key="sk-ant"

        not a pair
        """
        let values = EnvFile.parse(text)
        #expect(values["DEEPGRAM_API_KEY"] == "abc123")
        #expect(values["GEMINI_API_KEY"] == "g-key")
        #expect(values["claude-api-key"] == "sk-ant")
        #expect(values.count == 3)
    }

    @Test func laterDuplicateWins() {
        let values = EnvFile.parse("A=1\nA=2\n")
        #expect(values["A"] == "2")
    }

    @Test func updatingReplacesInPlaceAndPreservesComments() {
        let text = "# comment\nA=1\nB=2\n"
        let updated = EnvFile.updating(text, key: "A", value: "9")
        #expect(updated == "# comment\nA=9\nB=2\n")
    }

    @Test func updatingAppendsMissingKey() {
        let updated = EnvFile.updating("A=1\n", key: "B", value: "2")
        #expect(updated == "A=1\nB=2\n")
    }

    @Test func updatingRemovesKeyWhenValueNil() {
        let updated = EnvFile.updating("A=1\nB=2\n", key: "A", value: nil)
        #expect(updated == "B=2\n")
    }

    @Test func updatingCollapsesDuplicates() {
        let updated = EnvFile.updating("A=1\nA=2\n", key: "A", value: "3")
        #expect(updated == "A=3\n")
    }

    @Test func updatingEmptyTextCreatesFile() {
        #expect(EnvFile.updating("", key: "A", value: "1") == "A=1\n")
        #expect(EnvFile.updating("", key: "A", value: nil) == "")
    }
}
