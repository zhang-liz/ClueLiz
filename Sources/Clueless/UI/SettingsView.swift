import SwiftUI
import CluelessCore

struct SettingsView: View {
    @ObservedObject var contextStore: FileContextStore
    @State private var deepgramKey = ""
    @State private var geminiKey = ""
    @State private var anthropicKey = ""
    @State private var saveError: String?
    @State private var importError: String?
    @AppStorage("meetingDomain") private var meetingDomain = "AI and software engineering"

    var body: some View {
        Form {
            Section("API Keys") {
                keyField("Deepgram (transcription)", text: $deepgramKey, key: .deepgram)
                keyField("Gemini (live insights)", text: $geminiKey, key: .gemini)
                keyField("Anthropic (summaries)", text: $anthropicKey, key: .anthropic)
                if let saveError {
                    Text(saveError).foregroundStyle(.red).font(.caption)
                }
            }

            Section("Meeting domain") {
                TextField("Topic area", text: $meetingDomain)
                    .help("Ambiguous terms are interpreted in this domain — e.g. \"MCP\" means Model Context Protocol when the domain is AI.")
                Text("All AI answers interpret jargon and acronyms in this domain.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Context files") {
                ForEach(contextStore.files) { file in
                    HStack {
                        Label(file.name, systemImage: "doc.text")
                        Spacer()
                        Text("\(file.text.count) chars")
                            .font(.caption).foregroundStyle(.secondary)
                        Button {
                            contextStore.remove(id: file.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button("Add file… (PDF, docx, txt, md)") { addFile() }
                if let importError {
                    Text(importError).foregroundStyle(.red).font(.caption)
                }
            }

            Section("Hotkeys") {
                LabeledContent("Get Answer (screen)", value: "⌘⇧Return")
                LabeledContent("Chat submit", value: "⌘Return")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 420)
        .onAppear(perform: load)
    }

    private func keyField(_ label: String, text: Binding<String>, key: APIKeyName) -> some View {
        SecureField(label, text: text)
            .onChange(of: text.wrappedValue) { _, newValue in
                do {
                    if newValue.isEmpty {
                        try KeychainStore.delete(key)
                    } else {
                        try KeychainStore.set(newValue, for: key)
                    }
                    saveError = nil
                } catch {
                    saveError = "Could not save key: \(error)"
                }
            }
    }

    private func load() {
        deepgramKey = KeychainStore.get(.deepgram) ?? ""
        geminiKey = KeychainStore.get(.gemini) ?? ""
        anthropicKey = KeychainStore.get(.anthropic) ?? ""
    }

    private func addFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        // Everything FileImporter supports: pdf, docx, txt, md/markdown.
        panel.allowedContentTypes = [.pdf, .plainText, .init(filenameExtension: "docx")!,
                                     .init(filenameExtension: "md")!,
                                     .init(filenameExtension: "markdown")!]
        guard panel.runModal() == .OK else { return }
        var failures: [String] = []
        for url in panel.urls {
            do {
                try contextStore.importFile(at: url)
            } catch {
                failures.append(error.localizedDescription)
            }
        }
        importError = failures.isEmpty ? nil : failures.joined(separator: "\n")
    }
}
