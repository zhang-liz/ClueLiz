import Foundation
import AppKit
import ScreenCaptureKit

/// Captures the main display for the "Get Answer" hotkey, excluding the
/// ClueLiz overlay itself, downscaled to ≤1600 px wide, returned as PNG.
enum ScreenSnapshotService {
    static func captureMainDisplayPNG() async throws -> Data {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw NSError(domain: "ScreenSnapshotService", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No display found"])
        }
        let ownApps = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])

        let config = SCStreamConfiguration()
        let scale = min(1.0, 1600.0 / Double(display.width))
        config.width = Int(Double(display.width) * scale)
        config.height = Int(Double(display.height) * scale)
        config.showsCursor = false

        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "ScreenSnapshotService", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "PNG encoding failed"])
        }
        return png
    }
}
