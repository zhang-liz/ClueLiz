import SwiftUI
import AVFoundation
import EventKit
import CoreGraphics

/// First-run walkthrough: welcome → mic → screen recording → calendar + API keys.
/// Features degrade gracefully if a permission is denied — nothing here blocks the app.
struct OnboardingView: View {
    let contextStore: FileContextStore
    var onFinished: () -> Void

    @State private var page = 0
    @State private var micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @State private var screenGranted = CGPreflightScreenCaptureAccess()
    @State private var calendarGranted = EKEventStore.authorizationStatus(for: .event) == .fullAccess

    var body: some View {
        VStack(spacing: 16) {
            content
            Spacer()
            HStack {
                if page > 0 {
                    Button("Back") { page -= 1 }
                }
                Spacer()
                if page < 3 {
                    Button("Continue") { page += 1 }.buttonStyle(.borderedProminent)
                } else {
                    Button("Done") { onFinished() }.buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(24)
        .frame(width: 480, height: 420)
    }

    @ViewBuilder private var content: some View {
        switch page {
        case 0:
            VStack(spacing: 12) {
                Image(systemName: "waveform.badge.mic").font(.system(size: 48))
                Text("Welcome to Clueless").font(.title).bold()
                Text("""
                Your real-time meeting copilot: live transcript, instant AI insights, \
                and a clean summary when the meeting ends. A few permissions make it work.
                """)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            }
        case 1:
            permissionPage(
                icon: "mic.fill",
                title: "Microphone",
                explanation: "Transcribes your side of the conversation.",
                granted: micGranted,
                grantAction: {
                    AVCaptureDevice.requestAccess(for: .audio) { granted in
                        DispatchQueue.main.async { micGranted = granted }
                    }
                },
                settingsPane: "Privacy_Microphone"
            )
        case 2:
            permissionPage(
                icon: "rectangle.inset.filled.badge.record",
                title: "Screen Recording",
                explanation: """
                Captures the other participants' audio and powers the "Get Answer" \
                screen hotkey. macOS may ask you to relaunch Clueless after granting.
                """,
                granted: screenGranted,
                grantAction: {
                    screenGranted = CGRequestScreenCaptureAccess()
                },
                settingsPane: "Privacy_ScreenCapture"
            )
        case 3:
            VStack(alignment: .leading, spacing: 12) {
                permissionRow(
                    icon: "calendar",
                    title: "Calendar (optional)",
                    explanation: "Detects when meetings start and end.",
                    granted: calendarGranted
                ) {
                    EKEventStore().requestFullAccessToEvents { granted, _ in
                        DispatchQueue.main.async { calendarGranted = granted }
                    }
                }
                Divider()
                Text("API Keys").font(.headline)
                Text("Paste your Deepgram, Gemini, and Anthropic keys — stored in your Keychain only. You can also do this later in Settings (⌘,).")
                    .font(.caption).foregroundStyle(.secondary)
                OnboardingKeyFields()
            }
        default:
            EmptyView()
        }
    }

    private func permissionPage(icon: String, title: String, explanation: String,
                                granted: Bool, grantAction: @escaping () -> Void,
                                settingsPane: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 42))
            Text(title).font(.title2).bold()
            Text(explanation).multilineTextAlignment(.center).foregroundStyle(.secondary)
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button("Grant \(title) Access", action: grantAction)
                    .buttonStyle(.borderedProminent)
                Button("Open System Settings") {
                    let url = "x-apple.systempreferences:com.apple.preference.security?\(settingsPane)"
                    NSWorkspace.shared.open(URL(string: url)!)
                }
                .font(.caption)
            }
        }
    }

    private func permissionRow(icon: String, title: String, explanation: String,
                               granted: Bool, grantAction: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: icon)
            VStack(alignment: .leading) {
                Text(title).bold()
                Text(explanation).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button("Grant", action: grantAction)
            }
        }
    }
}

/// Inline key entry reusing KeychainStore — same behavior as Settings.
private struct OnboardingKeyFields: View {
    @State private var deepgram = KeychainStore.get(.deepgram) ?? ""
    @State private var gemini = KeychainStore.get(.gemini) ?? ""
    @State private var anthropic = KeychainStore.get(.anthropic) ?? ""

    var body: some View {
        VStack(spacing: 6) {
            field("Deepgram key", text: $deepgram, key: .deepgram)
            field("Gemini key", text: $gemini, key: .gemini)
            field("Anthropic key", text: $anthropic, key: .anthropic)
        }
    }

    private func field(_ label: String, text: Binding<String>, key: APIKeyName) -> some View {
        SecureField(label, text: text)
            .textFieldStyle(.roundedBorder)
            .onChange(of: text.wrappedValue) { _, newValue in
                if newValue.isEmpty {
                    try? KeychainStore.delete(key)
                } else {
                    try? KeychainStore.set(newValue, for: key)
                }
            }
    }
}
