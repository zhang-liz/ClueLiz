import AppKit
import SwiftUI
import ClueLizCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private(set) var appState: AppState!
    private var overlayPanel: OverlayPanel?
    private var settingsWindow: NSWindow?
    private let hotkeyManager = HotkeyManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        installMenu()

        migrateLegacyDefaults()
        EnvKeyFile.syncIntoKeychain()

        appState = AppState()
        let panel = OverlayPanel(appState: appState)
        panel.orderFrontRegardless()
        overlayPanel = panel

        if !UserDefaults.standard.bool(forKey: "onboardingDone") {
            showOnboarding()
        }

        // Get Answer: ⌘⇧Return, global, no typed input needed.
        let hotkeyRegistered = hotkeyManager.register { [weak self] in
            self?.appState.runScreenAnswer()
            self?.overlayPanel?.orderFrontRegardless()
        }
        if !hotkeyRegistered {
            appState.showNonRetryableError(
                "Could not register the ⌘⇧⏎ hotkey — another app may already use it. Get Answer is unavailable.")
        }

        wireSessionEvents()
    }

    /// ⌘Q mid-session: flush the transcript and mark the session ended —
    /// otherwise up to 10 s of transcript is lost and the next launch falsely
    /// claims an unclean shutdown.
    func applicationWillTerminate(_ notification: Notification) {
        appState?.endSessionForTermination()
    }

    private var summaryWindows: [NSWindow] = []

    private func wireSessionEvents() {
        appState.presentSummary = { [weak self] record in
            self?.showSummaryWindow(for: record)
        }

        appState.sessionManager.onMeetingDetected = { [weak self] title, attendees, eventID in
            guard let self, !self.appState.sessionActive else { return }
            let alert = NSAlert()
            alert.messageText = "Meeting starting: \(title)"
            alert.informativeText = attendees.isEmpty
                ? "Start a ClueLiz session?"
                : "With \(attendees.joined(separator: ", ")). Start a ClueLiz session?"
            alert.addButton(withTitle: "Start Session")
            alert.addButton(withTitle: "Not Now")
            if alert.runModal() == .alertFirstButtonReturn {
                self.appState.startSession()
                // Participants and the calendar-event link belong only to a
                // session actually started from this prompt — attaching them on
                // "Not Now" (or a failed start) would pollute a later manual
                // session and fire a bogus "meeting ended" prompt.
                if self.appState.sessionActive {
                    self.appState.participants = attendees
                    self.appState.sessionManager.attachDetectedEvent(eventID)
                }
            }
        }

        appState.sessionManager.onMeetingLikelyEnded = { [weak self] in
            guard let self, self.appState.sessionActive else { return }
            let alert = NSAlert()
            alert.messageText = "Meeting appears to have ended"
            alert.informativeText = "The calendar event finished a couple of minutes ago. End the session and generate the summary?"
            alert.addButton(withTitle: "End Session")
            alert.addButton(withTitle: "Keep Going")
            if alert.runModal() == .alertFirstButtonReturn {
                self.appState.endSession()
            }
        }

        appState.sessionManager.onSilenceTimeout = { [weak self] in
            guard let self, self.appState.sessionActive else { return }
            let alert = NSAlert()
            alert.messageText = "No audio for 10 minutes"
            alert.informativeText = "End the session and generate the summary?"
            alert.addButton(withTitle: "End Session")
            alert.addButton(withTitle: "Keep Going")
            if alert.runModal() == .alertFirstButtonReturn {
                self.appState.endSession()
            }
        }

        // Crash recovery: offer to resume an unfinished session.
        if let recovered = appState.sessionManager.recoverableSession {
            let alert = NSAlert()
            alert.messageText = "Resume previous session?"
            alert.informativeText = "ClueLiz didn't shut down cleanly. Resume the session from \(recovered.startedAt.formatted(date: .abbreviated, time: .shortened)) (\(recovered.turns.count) transcript entries)?"
            alert.addButton(withTitle: "Resume")
            alert.addButton(withTitle: "Discard")
            if alert.runModal() == .alertFirstButtonReturn {
                appState.resumeRecoveredSession()
            } else {
                appState.sessionManager.discardRecoverableSession()
            }
        }
    }

    private var onboardingWindow: NSWindow?

    private func showOnboarding() {
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 480, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to ClueLiz"
        window.contentView = NSHostingView(rootView: OnboardingView(contextStore: appState.contextStore) { [weak self] in
            self?.finishOnboarding()
        })
        window.isReleasedWhenClosed = false
        window.delegate = self   // title-bar close must release the window too
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
    }

    /// The rename from Clueless changed the bundle id, which reset UserDefaults.
    /// Copy the settings that survive under the old domain so users aren't sent
    /// through onboarding again.
    private func migrateLegacyDefaults() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "onboardingDone") == nil,
              let legacy = defaults.persistentDomain(forName: "com.clueless.app") else { return }
        for key in ["onboardingDone", "meetingDomain"] {
            if defaults.object(forKey: key) == nil, let value = legacy[key] {
                defaults.set(value, forKey: key)
            }
        }
    }

    /// Done button: mark onboarding complete, start the calendar watch, release
    /// the window (so its 1 s permission-poll timer dies with it). A premature
    /// title-bar close deliberately does NOT come here — closing at page 0 must
    /// not permanently mark onboarding done nor ambush the user with the
    /// calendar permission dialog; see `windowWillClose`.
    private func finishOnboarding() {
        guard let window = onboardingWindow else { return }
        onboardingWindow = nil   // windowWillClose then treats the close as handled
        UserDefaults.standard.set(true, forKey: "onboardingDone")
        // Deferred from AppState.init so the permission dialog doesn't
        // preempt the onboarding walkthrough.
        appState.sessionManager.startCalendarWatch()
        window.close()
    }

    private func showSummaryWindow(for record: SessionRecord) {
        let model = SummaryModel(record: record, sessionManager: appState.sessionManager)
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 560, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Meeting Summary"
        window.contentView = NSHostingView(rootView: SummaryView(model: model))
        window.isReleasedWhenClosed = false
        window.delegate = self   // release the retained window once it closes
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        summaryWindows.append(window)
    }

    private func installMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        appMenu.addItem(withTitle: "Show Overlay", action: #selector(showOverlay), keyEquivalent: "o")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit ClueLiz", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Standard Edit menu — without it, ⌘V/⌘C/⌘X/⌘A do nothing in any text field.
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        NSApp.mainMenu = mainMenu
    }

    @objc func showOverlay() {
        overlayPanel?.orderFrontRegardless()
    }

    // Summary windows and the onboarding window set this delegate; the other
    // windows are single, reused references that must stay retained.
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window == onboardingWindow {
            // Premature close (user bailed mid-walkthrough): release the window
            // so its permission poll stops, but don't mark onboarding done — it
            // re-shows next launch — and don't fire the calendar permission
            // dialog with zero context. Done goes through finishOnboarding().
            onboardingWindow = nil
        }
        summaryWindows.removeAll { $0 == window }
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: .init(x: 0, y: 0, width: 460, height: 420),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "ClueLiz Settings"
            window.contentView = NSHostingView(rootView: SettingsView(contextStore: appState.contextStore))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
