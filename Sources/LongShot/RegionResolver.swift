import AppKit
import CoreGraphics

enum RegionResolver {
    private static let ignoredOwners: Set<String> = [
        "Window Server", "Dock", "Control Center", "Notification Center",
        "SystemUIServer", "universalAccessAuthWarn"
    ]

    /// Finds the frontmost normal window under a point. Used to activate and
    /// scroll the content behind a freely selected screen region.
    static func window(under point: CGPoint, excludingPID ownPID: pid_t = getpid()) -> WindowTarget? {
        guard let raw = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        for info in raw {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  pid != ownPID,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: boundsDict),
                  frame.width >= 80, frame.height >= 60,
                  frame.contains(point) else {
                continue
            }
            let owner = info[kCGWindowOwnerName as String] as? String ?? ""
            guard !ignoredOwners.contains(owner) else { continue }
            let title = info[kCGWindowName as String] as? String ?? ""
            let windowID = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0
            guard windowID != 0 else { continue }

            let app = NSRunningApplication(processIdentifier: pid)
            return WindowTarget(
                id: windowID,
                processID: pid,
                appName: owner.isEmpty ? (app?.localizedName ?? "应用") : owner,
                title: title,
                bundleIdentifier: app?.bundleIdentifier,
                frame: frame
            )
        }
        return nil
    }
}
