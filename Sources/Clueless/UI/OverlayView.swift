import SwiftUI
import CluelessCore

// MARK: - Design tokens

/// One quiet visual language for the whole overlay: hairline-stroked cards on
/// translucent material, capsule pills, a single accent, small confident type.
private enum UI {
    static let cardRadius: CGFloat = 10
    static let cardFill = Color.primary.opacity(0.045)
    static let cardStroke = Color.primary.opacity(0.07)
}

private struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(UI.cardFill, in: RoundedRectangle(cornerRadius: UI.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: UI.cardRadius, style: .continuous)
                    .strokeBorder(UI.cardStroke, lineWidth: 1)
            )
    }
}

private extension View {
    func card() -> some View { modifier(CardBackground()) }
}

// MARK: - Root

/// Root overlay content: header, live transcript, insights card, chips, chat bar.
struct OverlayView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("overlayOpacity") private var overlayOpacity = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let error = appState.errorBanner {
                errorBanner(error)
            }
            sectionLabel("Transcript")
            TranscriptPanelView()
            if !appState.definitions.isEmpty {
                sectionLabel("Terms")
                DefinitionsView()
            }
            sectionLabel("Insights")
            InsightsCardView()
            if !appState.chips.isEmpty {
                ChipsRowView()
            }
            ChatBarView()
        }
        .padding(12)
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

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(.tertiary)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(appState.sessionActive ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 7, height: 7)
            Text("Clueless")
                .font(.system(size: 13, weight: .semibold))
            if appState.reconnecting {
                Text("reconnecting…")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(.orange.opacity(0.12), in: Capsule())
            }
            Spacer()
            opacityMenu
            sessionButton
        }
    }

    private var opacityMenu: some View {
        Menu {
            ForEach([1.0, 0.85, 0.7, 0.55, 0.4], id: \.self) { value in
                Button {
                    overlayOpacity = value
                } label: {
                    if abs(overlayOpacity - value) < 0.01 {
                        Label("\(Int(value * 100))%", systemImage: "checkmark")
                    } else {
                        Text("\(Int(value * 100))%")
                    }
                }
            }
        } label: {
            Image(systemName: "circle.lefthalf.filled")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Overlay transparency")
    }

    private var sessionButton: some View {
        Button {
            appState.sessionActive ? appState.endSession() : appState.startSession()
        } label: {
            Text(appState.sessionActive ? "End Session" : "Start Session")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(appState.sessionActive ? AnyShapeStyle(Color.red) : AnyShapeStyle(Color.white))
                .padding(.horizontal, 11).padding(.vertical, 5)
                .background(
                    appState.sessionActive
                        ? AnyShapeStyle(Color.red.opacity(0.13))
                        : AnyShapeStyle(Color.accentColor),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .help(appState.sessionActive
              ? "End the session and generate the summary"
              : (appState.hasDeepgramKey ? "Start transcribing this meeting"
                                         : "Add your Deepgram key in Settings first"))
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.red)
            Text(message)
                .font(.system(size: 11))
                .lineLimit(2)
            Spacer()
            // Retries whatever failed — action, chip, chat question, or screen answer.
            if appState.canRetry {
                Button("Retry") { appState.retryLast() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            Button {
                appState.errorBanner = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: UI.cardRadius, style: .continuous))
    }
}

// MARK: - Transcript

/// Live transcript: finals solid, in-progress speech muted; hanging-indent rows.
struct TranscriptPanelView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if appState.turns.isEmpty {
                        Text(appState.sessionActive
                             ? "Listening — speech appears here as it is transcribed."
                             : "Press Start Session to begin transcribing your meeting.")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(appState.turns) { turn in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(turn.speaker.label)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(turn.speaker == .me
                                                 ? AnyShapeStyle(Color.accentColor)
                                                 : AnyShapeStyle(.secondary))
                            Text(turn.text)
                                .font(.system(size: 12))
                                .foregroundStyle(turn.isFinal ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id(turn.id)
                    }
                }
                .padding(8)
            }
            .frame(minHeight: 140, maxHeight: .infinity)
            .card()
            .onChange(of: appState.turns.last?.text) {
                if let lastID = appState.turns.last?.id {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
        }
    }
}

// MARK: - Auto-definitions

/// Auto-generated definitions of terms mentioned in the conversation (e.g. "MCP").
struct DefinitionsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(appState.definitions) { definition in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(definition.term)
                            .font(.system(size: 11, weight: .semibold))
                        if !definition.done {
                            ProgressView().controlSize(.mini)
                        }
                        Text(definition.text.isEmpty ? "…" : definition.text)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(8)
        }
        .frame(maxHeight: 110)
        .card()
    }
}

// MARK: - Insights

/// The five action buttons + streamed answer area.
struct InsightsCardView: View {
    @EnvironmentObject var appState: AppState

    private let columns = [GridItem(.adaptive(minimum: 118), spacing: 6)]

    /// Recap runs on the summary provider (Anthropic); everything else on Gemini.
    private func missingKeyName(for action: InsightAction) -> String? {
        if action == .recap {
            return appState.hasAnthropicKey ? nil : "Anthropic"
        }
        return appState.hasGeminiKey ? nil : "Gemini"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(InsightAction.allCases) { action in
                    actionButton(action)
                }
            }
            if appState.insightStreaming || !appState.insightText.isEmpty {
                answerArea
            } else {
                Text("Tap an action, tap a suggestion, or ask anything below. ⌘⇧⏎ answers whatever is on your screen.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
            }
        }
    }

    private func actionButton(_ action: InsightAction) -> some View {
        let isActive = appState.activeAction == action
        let disabled = missingKeyName(for: action) != nil
        return Button {
            appState.run(action: action)
        } label: {
            Text(action.title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(
                    isActive ? AnyShapeStyle(Color.accentColor.opacity(0.16)) : AnyShapeStyle(UI.cardFill),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(isActive ? Color.accentColor.opacity(0.35) : UI.cardStroke, lineWidth: 1)
                )
                .foregroundStyle(isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)   // .plain doesn't gray out on its own
        .help(missingKeyName(for: action).map { "Add your \($0) key in Settings" } ?? action.title)
    }

    private var answerArea: some View {
        ZStack(alignment: .topTrailing) {
            ScrollViewReader { proxy in
                ScrollView {
                    HStack(alignment: .top, spacing: 6) {
                        if appState.insightStreaming {
                            ProgressView().controlSize(.small)
                        }
                        Text(appState.insightText.isEmpty ? "…" : appState.insightText)
                            .font(.system(size: 12))
                            .lineSpacing(2)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(8)
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
                    HStack(spacing: 3) {
                        Image(systemName: "stop.fill").font(.system(size: 8))
                        Text("Stop").font(.system(size: 10, weight: .medium))
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(UI.cardStroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(5)
                .help("Stop generating — keeps the partial answer")
            }
        }
        .frame(maxHeight: 180)
        .card()
    }
}

// MARK: - Chips

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
                        HStack(spacing: 4) {
                            Image(systemName: icon(for: chip.kind))
                                .font(.system(size: 9))
                            Text(chip.text)
                                .font(.system(size: 11))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(UI.cardFill, in: Capsule())
                        .overlay(Capsule().strokeBorder(UI.cardStroke, lineWidth: 1))
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(height: 26)
    }

    private func icon(for kind: Chip.Kind) -> String {
        switch kind {
        case .question: return "questionmark.circle"
        case .keyword: return "tag"
        case .topic: return "bubble.left.and.bubble.right"
        }
    }
}

// MARK: - Chat bar

/// Free-text AI input with Smart Mode toggle. Return or ⌘⏎ submits.
struct ChatBarView: View {
    @EnvironmentObject var appState: AppState

    private var canSend: Bool {
        !appState.chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField("Ask anything…", text: $appState.chatInput, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .lineLimit(1...3)
                .onSubmit { appState.sendChat() }
            Button {
                appState.smartMode.toggle()
            } label: {
                Text("Smart")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(appState.smartMode ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(
                        appState.smartMode ? AnyShapeStyle(Color.accentColor.opacity(0.15)) : AnyShapeStyle(UI.cardFill),
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)
            .help("Smart Mode: optimized for coding/technical questions")
            Button {
                appState.sendChat()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(canSend ? Color.accentColor : Color.secondary.opacity(0.3), in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!canSend)
            .help("Send (⌘⏎)")
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .card()
    }
}
