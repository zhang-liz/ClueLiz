import Testing
@testable import CluelessCore

@Suite struct PromptBuilderTests {
    let ctx = PromptContext(transcript: "Me: hi\nThem: we need SSO by Q3",
                            uploadedContext: "ACME renewal notes",
                            participants: ["Jane Doe"])

    private func joinedText(_ r: LLMRequest) -> String {
        r.parts.compactMap { if case .text(let t) = $0 { return t } else { return nil } }.joined()
    }

    @Test func everyActionEmbedsTranscript() {
        for action in InsightAction.allCases {
            let r = PromptBuilder.request(for: action, context: ctx)
            #expect(joinedText(r).contains("we need SSO by Q3"), "\(action) missing transcript")
        }
    }

    @Test func whoIsThisIncludesParticipantsAndFiles() {
        let r = PromptBuilder.request(for: .whoIsThis, context: ctx)
        let text = joinedText(r)
        #expect(text.contains("Jane Doe"))
        #expect(text.contains("ACME renewal notes"))
    }

    @Test func smartModeSwapsSystemPrompt() {
        let normal = PromptBuilder.chatRequest(question: "q", smartMode: false, context: ctx)
        let smart = PromptBuilder.chatRequest(question: "q", smartMode: true, context: ctx)
        #expect(normal.system != smart.system)
        #expect(smart.system.lowercased().contains("code"))
    }

    @Test func parseChipsTolerantOfFences() {
        let json = "```json\n{\"questions\":[\"What is SSO?\"],\"keywords\":[\"SSO\"],\"topics\":[\"security\"]}\n```"
        let chips = PromptBuilder.parseChips(fromJSON: json)
        #expect(chips.count == 3)
        #expect(chips.first(where: { $0.kind == .question })?.text == "What is SSO?")
    }

    @Test func recapGetsBiggerBudget() {
        #expect(PromptBuilder.request(for: .recap, context: ctx).maxTokens >
                PromptBuilder.request(for: .sayNext, context: ctx).maxTokens)
    }

    @Test func domainInjectedIntoActionsAndDefinitions() {
        var domainCtx = ctx
        domainCtx.domain = "AI and software engineering"
        let action = PromptBuilder.request(for: .sayNext, context: domainCtx)
        let actionText = action.parts.compactMap { if case .text(let t) = $0 { return t } else { return nil } }.joined()
        #expect(actionText.contains("AI and software engineering"))

        let def = PromptBuilder.definitionRequest(term: "MCP", context: domainCtx)
        let defText = def.parts.compactMap { if case .text(let t) = $0 { return t } else { return nil } }.joined()
        #expect(defText.contains("AI and software engineering"))
        #expect(defText.contains("Model Context Protocol"))   // domain example steering
    }

    @Test func definitionIncludesUploadedDocs() {
        let def = PromptBuilder.definitionRequest(term: "ACME", context: ctx)
        let defText = def.parts.compactMap { if case .text(let t) = $0 { return t } else { return nil } }.joined()
        #expect(defText.contains("ACME renewal notes"))
    }
}
