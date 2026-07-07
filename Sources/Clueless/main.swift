import AppKit

// AppKit-owned entry point. The app manages its own windows and menu bar;
// the SwiftUI App lifecycle is deliberately not used — its Scene machinery
// replaces NSApp.mainMenu with an auto-generated menu, wiping out the
// custom menus (Settings, Edit, Show Overlay, …) installed by AppDelegate.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
