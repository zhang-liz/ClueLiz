import SwiftUI
import ClueLizCore

/// Root overlay content: header, live transcript, insights card, chips, chat bar.
struct OverlayView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("overlayOpacity") private var overlayOpacity = 1.0

    var body: some View {
        VStack(spacing: 8) {
            header
            if let error = appState.errorBanner {
                errorBanner(error)
            }
            sectionLabel("Transcript", systemImage: "waveform")
            TranscriptPanelView()
            if !appState.definitions.isEmpty {
                sectionLabel("Auto-detected terms", systemImage: "sparkles")
                DefinitionsView()
            }
            sectionLabel("Live Insights", systemImage: "lightbulb")
            InsightsCardView()
            if !appState.chips.isEmpty {
                sectionLabel("Tap to explore", systemImage: "hand.tap")
                ChipsRowView()
            }
            ChatBarView()
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .onAppear { applyOpacity() }
        .onChange(of: overlayOpacity) { applyOpacity() }
    }

    /// Window-level transparency so the overlay can hover over content unobtrusively.
    private func applyOpacity() {
        for window in NSApp.windows where window is OverlayPanel {
            window.alphaValue = max(0.3, min(1.0, overlayOpacity))
        }
    }

    private func sectionLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("ClueLiz").font(.headline)
            if appState.reconnecting {
                Label("reconnecting", systemImage: "wifi.exclamationmark")
                    .font(.caption)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.yellow.opacity(0.25), in: Capsule())
            }
            Spacer()
            // Transparency control: 30–100%.
            Image(systemName: "circle.lefthalf.filled")
                .font(.caption).foregroundStyle(.secondary)
                .help("Overlay transparency")
            Slider(value: $overlayOpacity, in: 0.3...1.0)
                .frame(width: 70)
                .controlSize(.mini)
                .help("Overlay transparency")
            Button(appState.sessionActive ? "End Session" : "Start Session") {
                appState.sessionActive ? appState.endSession() : appState.startSession()
            }
            .tint(appState.sessionActive ? .red : .green)
            .help(appState.sessionActive
                  ? "End the session and generate the summary"
                  : (appState.hasDeepgramKey ? "Start transcribing this meeting"
                                             : "Add your Deepgram key in Settings first"))
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Text(message).font(.caption).foregroundStyle(.red)
            Spacer()
            // Retries whatever failed — action, chip, chat question, or screen answer.
            if appState.canRetry {
                Button("Retry") { appState.retryLast() }
                    .font(.caption)
            }
            Button("✕") { appState.errorBanner = nil }
                .buttonStyle(.plain).font(.caption)
        }
        .padding(6)
        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }
}

/// Live transcript: finals labeled and solid, partials gray.
struct TranscriptPanelView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if appState.turns.isEmpty {
                        Text(appState.sessionActive
                             ? "Listening — speech appears here as it is transcribed."
                             : "Press Start Session to begin transcribing your meeting.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(appState.turns) { turn in
                        (Text("\(turn.speaker.label): ").bold() + Text(turn.text))
                            .font(.callout)
                            .foregroundStyle(turn.isFinal ? .primary : .secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(turn.id)
                    }
                }
                .padding(6)
            }
            .frame(minHeight: 140, maxHeight: .infinity)
            .background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            .onChange(of: appState.turns.last?.text) {
                if let lastID = appState.turns.last?.id {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
        }
    }
}

/// Auto-generated definitions of terms mentioned in the conversation (e.g. "MCP").
struct DefinitionsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(appState.definitions) { definition in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(definition.term).font(.caption).bold()
                            if !definition.done {
                                ProgressView().controlSize(.mini)
                            }
                        }
                        Text(definition.text.isEmpty ? "…" : definition.text)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(6)
        }
        .frame(maxHeight: 110)
        .background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// The five action buttons + streamed answer area.
struct InsightsCardView: View {
    @EnvironmentObject var appState: AppState

    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 6)]

    /// Recap runs on the summary provider (Anthropic); everything else on Gemini.
    private func missingKeyName(for action: InsightAction) -> String? {
        if action == .recap {
            return appState.hasAnthropicKey ? nil : "Anthropic"
        }
        return appState.hasGeminiKey ? nil : "Gemini"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(InsightAction.allCases) { action in
                    Button {
                        appState.run(action: action)
                    } label: {
                        Text(action.title)
                            .font(.caption)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(appState.activeAction == action ? .accentColor : .secondary)
                    .disabled(missingKeyName(for: action) != nil)
                    .help(missingKeyName(for: action).map { "Add your \($0) key in Settings" } ?? action.title)
                }
            }
            if appState.insightStreaming || !appState.insightText.isEmpty {
                ZStack(alignment: .topTrailing) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            HStack(alignment: .top, spacing: 6) {
                                if appState.insightStreaming {
                                    ProgressView().controlSize(.small)
                                }
                                Text(appState.insightText.isEmpty ? "…" : appState.insightText)
                                    .font(.callout)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(6)
                            .id("insight-answer")
                        }
                        // Follow the stream once it grows past the visible area.
                        .onChange(of: appState.insightText) {
                            if appState.insightStreaming {
                                proxy.scrollTo("insight-answer", anchor: .bottom)
                            }
                        }
                    }
                    if appState.insightStreaming {
                        Button {
                            appState.cancelStreaming()
                        } label: {
                            Label("Stop", systemImage: "stop.fill").font(.caption2)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .padding(4)
                        .help("Stop generating — keeps the partial answer")
                    }
                }
                .frame(maxHeight: 180)
                .background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            } else {
                Text("Tap an action above, tap a suggestion, or ask anything below — answers stream here. ⌘⇧⏎ answers whatever is on your screen.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
            }
        }
    }
}

/// Auto-detected suggestion chips.
struct ChipsRowView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(appState.chips) { chip in
                    Button {
                        appState.runChip(chip)
                    } label: {
                        Label(chip.text, systemImage: icon(for: chip.kind))
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .buttonStyle(.bordered)
                    .clipShape(Capsule())
                }
            }
        }
        .frame(height: 28)
    }

    private func icon(for kind: Chip.Kind) -> String {
        switch kind {
        case .question: return "questionmark.circle"
        case .keyword: return "tag"
        case .topic: return "bubble.left.and.bubble.right"
        }
    }
}

/// Free-text AI input with Smart Mode toggle. Cmd+Enter submits.
struct ChatBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 6) {
            TextField("Ask anything… (⌘⏎)", text: $appState.chatInput, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
                .onSubmit { appState.sendChat() }
            Toggle("Smart", isOn: $appState.smartMode)
                .toggleStyle(.button)
                .help("Smart Mode: optimized for coding/technical questions")
            Button {
                appState.sendChat()
            } label: {
                Image(systemName: "paperplane.fill")
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(appState.chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}
