import SwiftUI
import ClueLizCore

/// Post-meeting summary window: streams the Opus summary, then offers
/// copy / save-as-Markdown.
struct SummaryView: View {
    @ObservedObject var model: SummaryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Meeting Summary").font(.title2).bold()
                if model.streaming {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                Button("Copy Markdown") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.exportMarkdown, forType: .string)
                }
                .disabled(model.streaming)
                Button("Save .md…") { model.saveToFile() }
                    .disabled(model.streaming)
            }
            if let error = model.error {
                Text(error).foregroundStyle(.red).font(.caption)
                Button("Retry") { model.generate() }
            }
            // Save failures get their own slot — pairing them with the generation
            // error's Retry button would offer to regenerate the summary instead.
            if let saveError = model.saveError {
                Text(saveError).foregroundStyle(.red).font(.caption)
            }
            ScrollView {
                Text(renderedSummary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(minWidth: 480, minHeight: 480)
        .onAppear { model.generateIfNeeded() }
    }

    private var renderedSummary: AttributedString {
        // Line-by-line Markdown so headers/bullets render; falls back to plain text.
        let lines = model.summaryText.components(separatedBy: "\n").map { line -> AttributedString in
            (try? AttributedString(markdown: line)) ?? AttributedString(line)
        }
        var result = AttributedString()
        for (index, line) in lines.enumerated() {
            if index > 0 { result += AttributedString("\n") }
            result += line
        }
        return result
    }
}

/// Drives summary generation for one ended session.
@MainActor
final class SummaryModel: ObservableObject {
    @Published var summaryText = ""
    @Published var streaming = false
    @Published var error: String?
    @Published var saveError: String?

    private let record: SessionRecord
    private let sessionManager: SessionManager
    private var started = false

    init(record: SessionRecord, sessionManager: SessionManager) {
        self.record = record
        self.sessionManager = sessionManager
        if let existing = record.summaryMarkdown {
            summaryText = existing
            started = true
        }
    }

    var exportMarkdown: String {
        var updated = record
        updated.summaryMarkdown = summaryText
        return updated.markdownExport()
    }

    func generateIfNeeded() {
        guard !started else { return }
        generate()
    }

    func generate() {
        started = true
        error = nil
        guard let key = KeychainStore.get(.anthropic), !key.isEmpty else {
            error = "Add your Anthropic key in Settings to generate summaries."
            return
        }
        // Plain transcript only — markdownExport() would embed any existing summary
        // and headers into the prompt.
        let transcript = record.turns.filter(\.isFinal)
            .map { "\($0.speaker.label): \($0.text)" }
            .joined(separator: "\n")
        streaming = true
        summaryText = ""
        Task {
            do {
                let summary = try await sessionManager.streamSummary(
                    llm: AnthropicProvider(apiKey: key),
                    transcript: transcript
                ) { [weak self] partial in
                    self?.summaryText = partial
                }
                self.sessionManager.attachSummary(summary, to: self.record)
                self.streaming = false
            } catch {
                self.streaming = false
                self.error = error.localizedDescription
            }
        }
    }

    func saveToFile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "meeting-summary.md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try exportMarkdown.write(to: url, atomically: true, encoding: .utf8)
            saveError = nil
        } catch {
            saveError = "Could not save: \(error.localizedDescription)"
        }
    }
}
