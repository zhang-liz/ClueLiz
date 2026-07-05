import Foundation

/// Everything an insight request needs beyond the action itself.
public struct PromptContext {
    public var transcript: String
    public var uploadedContext: String
    public var participants: [String]
    /// Topic domain the meeting lives in (e.g. "AI and software engineering").
    /// Disambiguates terms: in an AI meeting, MCP = Model Context Protocol.
    public var domain: String

    public init(transcript: String, uploadedContext: String = "",
                participants: [String] = [], domain: String = "") {
        self.transcript = transcript
        self.uploadedContext = uploadedContext
        self.participants = participants
        self.domain = domain
    }
}

/// Builds LLM requests for every feature. Pure functions — fully unit-testable.
public enum PromptBuilder {

    private static let liveSystem = """
    You are a real-time meeting copilot. The user is currently in a live meeting. \
    You see the running transcript ("Me" is the user, "Them" is the other side). \
    Answer fast, specific, and scannable — short sentences, bullets where useful. \
    Never invent facts about the participants; say when you are unsure.
    """

    private static let smartSystem = """
    You are a real-time technical copilot for an engineer in a live meeting. \
    Be precise and terse. Prefer concrete answers: exact commands, code in fenced \
    code blocks, exact API names, numbers. No conversational filler, no hedging. \
    If the question is about code or systems, answer like a senior engineer would.
    """

    private static func contextSection(_ ctx: PromptContext) -> String {
        var section = ""
        if !ctx.domain.isEmpty {
            section += """
            \n\n## Meeting domain
            This conversation is about: \(ctx.domain). Interpret all ambiguous terms, \
            acronyms, and references in this domain (e.g. in an AI conversation, \
            "MCP" means Model Context Protocol, not other expansions).
            """
        }
        section += "\n\n## Live transcript\n\(ctx.transcript)"
        if !ctx.uploadedContext.isEmpty {
            section += "\n\n## Background documents provided by the user (their resume, project docs, notes — treat as ground truth about the user)\n\(ctx.uploadedContext)"
        }
        if !ctx.participants.isEmpty {
            section += "\n\n## Meeting participants\n\(ctx.participants.joined(separator: ", "))"
        }
        return section
    }

    public static func request(for action: InsightAction, context ctx: PromptContext) -> LLMRequest {
        let instruction: String
        var maxTokens = 1024

        switch action {
        case .sayNext:
            instruction = """
            Suggest what the user should say next. Focus on the other side's most recent \
            points and open questions. Give 1-3 concrete options, strongest first.
            """
        case .followUps:
            instruction = """
            Suggest 3-5 sharp follow-up questions the user could ask right now, based on \
            the most recent topic. One line each.
            """
        case .factCheck:
            instruction = """
            Identify the most recent factual claim(s) made in the conversation. For each: \
            state the claim, assess whether it is accurate to the best of your knowledge, \
            and flag anything that needs verification. Be explicit about uncertainty.
            """
        case .whoIsThis:
            instruction = """
            Tell the user who they are talking to. Use the meeting participants list and \
            the background documents. Summarize role, company, relevant history, and what \
            they seem to care about based on the conversation so far.
            """
        case .recap:
            instruction = """
            Recap the conversation so far: main topics, key points from each side, \
            decisions made, and open questions. Organized with short headers or bullets.
            """
            maxTokens = 4096
        }

        return LLMRequest(system: liveSystem,
                          parts: [.text(instruction + contextSection(ctx))],
                          maxTokens: maxTokens)
    }

    public static func chatRequest(question: String, smartMode: Bool, context ctx: PromptContext) -> LLMRequest {
        LLMRequest(system: smartMode ? smartSystem : liveSystem,
                   parts: [.text("The user asks: \(question)" + contextSection(ctx))],
                   maxTokens: 2048)
    }

    public static func chipExtractionRequest(recentTranscript: String) -> LLMRequest {
        let instruction = """
        Extract from this meeting transcript excerpt:
        - "questions": questions that were asked and may need answering (max 3)
        - "keywords": important terms, products, or names mentioned (max 3)
        - "topics": discussion topics (max 2)
        Respond with STRICT JSON only, exactly this shape, no markdown fences, no prose:
        {"questions":[],"keywords":[],"topics":[]}

        Transcript:
        \(recentTranscript)
        """
        return LLMRequest(system: "", parts: [.text(instruction)], maxTokens: 512)
    }

    public static func screenAnswerRequest(pngData: Data, context ctx: PromptContext) -> LLMRequest {
        let instruction = """
        The user pressed the "answer this" hotkey. Look at the screenshot of their screen \
        and answer the most relevant question or problem visible on it — a code snippet to \
        explain or fix, a spreadsheet question, an error message, a quiz question, etc. \
        Use the meeting transcript for extra context if relevant. Answer directly.
        """ + contextSection(ctx)
        return LLMRequest(system: liveSystem,
                          parts: [.text(instruction), .imagePNG(pngData)],
                          maxTokens: 2048)
    }

    public static func summaryRequest(fullTranscript: String) -> LLMRequest {
        let instruction = """
        Write a clean, shareable summary of this meeting in Markdown with exactly these sections:
        ## Key Takeaways
        ## Decisions
        ## Next Steps
        ## Action Items
        Use bullets. Attribute positions to "Me"/"Them" where it matters. Be concise but complete.

        Full transcript:
        \(fullTranscript)
        """
        return LLMRequest(system: "You are an expert meeting summarizer.",
                          parts: [.text(instruction)],
                          maxTokens: 8192)
    }

    /// One-shot definition of a term detected in the conversation.
    public static func definitionRequest(term: String, context ctx: PromptContext) -> LLMRequest {
        var instruction = """
        The term "\(term)" just came up in a live meeting. Define it in 1-2 short sentences \
        for the meeting context below. No preamble — start with the definition.
        """
        if !ctx.domain.isEmpty {
            instruction += """
            \nThe meeting is about: \(ctx.domain). Resolve the term in THAT domain \
            (e.g. in an AI conversation, "MCP" = Model Context Protocol). Only fall back \
            to another meaning if the transcript clearly demands it.
            """
        }
        instruction += "\n\nRecent transcript:\n\(ctx.transcript)"
        if !ctx.uploadedContext.isEmpty {
            // Trimmed slice: definitions are small, fast requests.
            instruction += "\n\nUser's background documents (may explain the term):\n\(String(ctx.uploadedContext.prefix(4000)))"
        }
        return LLMRequest(system: "", parts: [.text(instruction)], maxTokens: 256)
    }

    /// Parses the chip-extraction JSON. Tolerant of ```json fences the model might add.
    public static func parseChips(fromJSON raw: String) -> [Chip] {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = cleaned.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }

        var chips: [Chip] = []
        for question in obj["questions"] as? [String] ?? [] {
            chips.append(Chip(kind: .question, text: question))
        }
        for keyword in obj["keywords"] as? [String] ?? [] {
            chips.append(Chip(kind: .keyword, text: keyword))
        }
        for topic in obj["topics"] as? [String] ?? [] {
            chips.append(Chip(kind: .topic, text: topic))
        }
        return chips
    }
}
