import SwiftUI

@main
struct ClueLizApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }   // real windows are managed by AppDelegate
    }
}
