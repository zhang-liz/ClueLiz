import AppKit
import SwiftUI
import CluelessCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    private(set) var appState: AppState!
    private var overlayPanel: OverlayPanel?
    private var settingsWindow: NSWindow?
    private let hotkeyManager = HotkeyManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        installMenu()

        appState = AppState()
        let panel = OverlayPanel(appState: appState)
        panel.orderFrontRegardless()
        overlayPanel = panel

        if !UserDefaults.standard.bool(forKey: "onboardingDone") {
            showOnboarding()
        }

        // Get Answer: ⌘⇧Return, global, no typed input needed.
        hotkeyManager.register { [weak self] in
            self?.appState.runScreenAnswer()
            self?.overlayPanel?.orderFrontRegardless()
        }

        wireSessionEvents()
    }

    private var summaryWindows: [NSWindow] = []

    private func wireSessionEvents() {
        appState.presentSummary = { [weak self] record in
            self?.showSummaryWindow(for: record)
        }

        appState.sessionManager.onMeetingDetected = { [weak self] title, attendees in
            guard let self, !self.appState.sessionActive else { return }
            self.appState.participants = attendees
            let alert = NSAlert()
            alert.messageText = "Meeting starting: \(title)"
            alert.informativeText = attendees.isEmpty
                ? "Start a Clueless session?"
                : "With \(attendees.joined(separator: ", ")). Start a Clueless session?"
            alert.addButton(withTitle: "Start Session")
            alert.addButton(withTitle: "Not Now")
            if alert.runModal() == .alertFirstButtonReturn {
                self.appState.startSession()
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
            alert.informativeText = "Clueless didn't shut down cleanly. Resume the session from \(recovered.startedAt.formatted(date: .abbreviated, time: .shortened)) (\(recovered.turns.count) transcript entries)?"
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
        window.title = "Welcome to Clueless"
        window.contentView = NSHostingView(rootView: OnboardingView(contextStore: appState.contextStore) { [weak self] in
            UserDefaults.standard.set(true, forKey: "onboardingDone")
            self?.onboardingWindow?.close()
            // Deferred from AppState.init so the permission dialog doesn't
            // preempt the onboarding walkthrough.
            self?.appState.sessionManager.startCalendarWatch()
        })
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
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

        func addSubmenu(_ menu: NSMenu) {
            let item = NSMenuItem()
            item.submenu = menu
            mainMenu.addItem(item)
        }

        // App menu: About, Settings, Services, Hide/Show, Quit.
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Clueless",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
            .target = self
        appMenu.addItem(.separator())
        let servicesMenu = NSMenu(title: "Services")
        appMenu.addItem(withTitle: "Services", action: nil, keyEquivalent: "").submenu = servicesMenu
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Clueless", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others",
                                         action: #selector(NSApplication.hideOtherApplications(_:)),
                                         keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All",
                        action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Clueless",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        addSubmenu(appMenu)

        // File: session lifecycle + standard close.
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New Session", action: #selector(startSessionAction), keyEquivalent: "n")
            .target = self
        let endItem = fileMenu.addItem(withTitle: "End Session",
                                       action: #selector(endSessionAction), keyEquivalent: "e")
        endItem.keyEquivalentModifierMask = [.command, .shift]
        endItem.target = self
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close Window",
                         action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        addSubmenu(fileMenu)

        // Standard Edit menu — without it, ⌘V/⌘C/⌘X/⌘A do nothing in any text field.
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        addSubmenu(editMenu)

        // View — AppKit appends "Enter Full Screen" to the menu titled "View".
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "Show Overlay", action: #selector(showOverlay), keyEquivalent: "o")
            .target = self
        addSubmenu(viewMenu)

        // Window — assigned to NSApp.windowsMenu so open windows are listed automatically.
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize",
                           action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Bring All to Front",
                           action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        addSubmenu(windowMenu)

        let helpMenu = NSMenu(title: "Help")
        helpMenu.addItem(withTitle: "Clueless Help", action: #selector(openHelp), keyEquivalent: "?")
            .target = self
        addSubmenu(helpMenu)

        NSApp.mainMenu = mainMenu
        NSApp.servicesMenu = servicesMenu
        NSApp.windowsMenu = windowMenu
        NSApp.helpMenu = helpMenu
    }

    @objc private func startSessionAction() {
        appState.startSession()
    }

    @objc private func endSessionAction() {
        appState.endSession()
    }

    @objc private func openHelp() {
        NSWorkspace.shared.open(URL(string: "https://github.com/zhang-liz/ClueLiz")!)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let appState else { return false }
        switch menuItem.action {
        case #selector(startSessionAction): return !appState.sessionActive
        case #selector(endSessionAction): return appState.sessionActive
        default: return true
        }
    }

    @objc func showOverlay() {
        overlayPanel?.orderFrontRegardless()
    }

    // Only summary windows set this delegate; the other windows are single,
    // reused references that must stay retained.
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
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
            window.title = "Clueless Settings"
            window.contentView = NSHostingView(rootView: SettingsView(contextStore: appState.contextStore))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
