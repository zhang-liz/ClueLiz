import AppKit
import SwiftUI

/// Floating, non-activating, always-on-top overlay. Draggable by background,
/// visible on all Spaces and over full-screen apps, never steals focus.
final class OverlayPanel: NSPanel {
    init(appState: AppState) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 640),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable, .closable],
            backing: .buffered,
            defer: false
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        minSize = NSSize(width: 340, height: 420)

        contentView = NSHostingView(rootView: OverlayView().environmentObject(appState))

        // Default position: right edge of the main screen.
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            setFrameOrigin(NSPoint(x: frame.maxX - 440, y: frame.midY - 320))
        }
    }

    override var canBecomeKey: Bool { true }   // chat input needs key status without app activation
    override var canBecomeMain: Bool { false }
}
