import AppKit
import ScreenCaptureKit

struct DiscoveredWindow {
    let target: WindowTarget
    let window: SCWindow
}

enum WindowDiscovery {
    private static let ignoredOwners: Set<String> = [
        "Window Server",
        "Dock",
        "Control Center",
        "Notification Center",
        "Spotlight",
        "SystemUIServer",
        "TextInputMenuAgent",
        "Wallpaper",
        "universalAccessAuthWarn",
        "UserNotificationCenter",
        "SecurityAgent",
        "CoreServicesUIAgent"
    ]

    private static let ignoredBundleIdentifiers: Set<String> = [
        "com.apple.dock",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.WindowManager",
        "com.apple.wallpaper.agent"
    ]

    static func discover() async throws -> [DiscoveredWindow] {
        guard Permissions.hasScreenRecording else { throw DiscoveryError.permissionDenied }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
        } catch {
            if !Permissions.hasScreenRecording { throw DiscoveryError.permissionDenied }
            throw error
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownBundle = Bundle.main.bundleIdentifier

        var seen = Set<CGWindowID>()
        var result: [DiscoveredWindow] = []

        for window in content.windows {
            guard window.isOnScreen,
                  window.windowLayer == 0,
                  let app = window.owningApplication,
                  app.processID != ownPID,
                  app.bundleIdentifier != ownBundle,
                  !ignoredOwners.contains(app.applicationName),
                  !ignoredBundleIdentifiers.contains(app.bundleIdentifier),
                  window.frame.width >= 180,
                  window.frame.height >= 120,
                  seen.insert(window.windowID).inserted else {
                continue
            }

            let appName = app.applicationName.isEmpty ? "未知应用" : app.applicationName
            let title = window.title ?? ""
            let target = WindowTarget(
                id: window.windowID,
                processID: app.processID,
                appName: appName,
                title: title,
                bundleIdentifier: app.bundleIdentifier,
                frame: window.frame
            )
            result.append(DiscoveredWindow(target: target, window: window))
        }

        result.sort { lhs, rhs in
            if lhs.target.appName != rhs.target.appName {
                return lhs.target.appName.localizedStandardCompare(rhs.target.appName) == .orderedAscending
            }
            if lhs.target.title != rhs.target.title {
                return lhs.target.title.localizedStandardCompare(rhs.target.title) == .orderedAscending
            }
            return lhs.target.id < rhs.target.id
        }
        return result
    }

    static func thumbnail(for window: SCWindow) async -> NSImage? {
        guard Permissions.hasScreenRecording else { return nil }
        let aspect = window.frame.height / max(window.frame.width, 1)
        let width = min(520, max(220, Int(window.frame.width * 2)))
        let height = max(120, Int(Double(width) * aspect))

        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.ignoreGlobalClipSingleWindow = true
        configuration.captureResolution = .best
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB

        let filter = SCContentFilter(desktopIndependentWindow: window)
        do {
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            return NSImage(
                cgImage: image,
                size: NSSize(width: CGFloat(image.width) / 2, height: CGFloat(image.height) / 2)
            )
        } catch {
            return nil
        }
    }
}

@MainActor
enum AppIconProvider {
    private static var cache: [String: NSImage] = [:]

    static func icon(for target: WindowTarget) -> NSImage {
        let key = target.bundleIdentifier ?? target.appName
        if let cached = cache[key] { return cached }

        var image: NSImage?
        if let bundleURL = NSRunningApplication(processIdentifier: target.processID)?.bundleURL {
            image = NSWorkspace.shared.icon(forFile: bundleURL.path)
        }
        if image == nil {
            image = NSImage(named: NSImage.applicationIconName)
        }
        image?.size = NSSize(width: 64, height: 64)
        let resolved = image ?? NSImage(size: NSSize(width: 64, height: 64))
        cache[key] = resolved
        return resolved
    }
}
