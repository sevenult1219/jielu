import AppKit

struct RegionSelection {
    let rectOnScreen: NSRect
    let screen: NSScreen

    var displayID: CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

private final class RegionSelectionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class RegionSelectionController {
    private var window: RegionSelectionWindow?
    private var overlayView: RegionSelectionView?
    private var completion: ((RegionSelection?) -> Void)?

    func begin(
        on screen: NSScreen,
        confirmTitle: String = "开始长截屏",
        completion: @escaping (RegionSelection?) -> Void
    ) {
        cancel()

        let window = RegionSelectionWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.setFrame(screen.frame, display: false)
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none

        let view = RegionSelectionView(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            controller: self,
            confirmTitle: confirmTitle
        )
        window.contentView = view
        self.window = window
        self.overlayView = view
        self.completion = completion

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
    }

    func cancel() {
        finish(with: nil)
    }

    fileprivate func confirm() {
        guard let window, let overlayView, let selection = overlayView.validSelection else {
            return
        }
        guard let screen = window.screen ?? NSScreen.main else {
            finish(with: nil)
            return
        }
        let screenRect = window.convertToScreen(selection)
        finish(with: RegionSelection(rectOnScreen: screenRect, screen: screen))
    }

    fileprivate func cancelFromOverlay() {
        finish(with: nil)
    }


    private func finish(with selection: RegionSelection?) {
        let callback = completion
        completion = nil
        let currentWindow = window
        window = nil
        overlayView = nil
        currentWindow?.orderOut(nil)
        currentWindow?.contentView = nil
        currentWindow?.close()
        callback?(selection)
    }
}

private final class RegionSelectionView: NSView {
    private weak var controller: RegionSelectionController?
    private let confirmTitle: String
    private var selection = NSRect.zero
    private var dragOrigin: NSPoint?
    private var toolbar: NSVisualEffectView?

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

    init(
        frame frameRect: NSRect,
        controller: RegionSelectionController,
        confirmTitle: String
    ) {
        self.controller = controller
        self.confirmTitle = confirmTitle
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    var validSelection: NSRect? {
        guard selection.width >= 40, selection.height >= 40 else { return nil }
        return selection
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let toolbar, !toolbar.isHidden, toolbar.frame.contains(point) {
            return
        }
        window?.makeFirstResponder(self)
        hideToolbar()
        dragOrigin = point
        selection = .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragOrigin else { return }
        let point = convert(event.locationInWindow, from: nil)
        selection = normalizedRect(from: dragOrigin, to: point).intersection(bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        dragOrigin = nil
        if validSelection == nil {
            selection = .zero
            hideToolbar()
            needsDisplay = true
            return
        }
        showToolbar()
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:
            controller?.cancelFromOverlay()
        case 36, 76:
            if validSelection != nil { controller?.confirm() }
        default:
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        controller?.cancelFromOverlay()
    }

    @objc private func startTapped() {
        controller?.confirm()
    }

    @objc private func cancelTapped() {
        controller?.cancelFromOverlay()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState()

        let dim = NSBezierPath(rect: bounds)
        if selection.width > 1, selection.height > 1 {
            dim.append(NSBezierPath(rect: selection))
            dim.windingRule = .evenOdd
        }
        NSColor.black.withAlphaComponent(0.48).setFill()
        dim.fill()

        if selection.width > 1, selection.height > 1 {
            NSColor.white.withAlphaComponent(0.9).setStroke()
            let outer = NSBezierPath(rect: selection.insetBy(dx: -0.5, dy: -0.5))
            outer.lineWidth = 1
            outer.stroke()

            NSColor.controlAccentColor.setStroke()
            let inner = NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5))
            inner.lineWidth = 2
            inner.stroke()

            drawSizeLabel()
        }

        drawInstructions()
        context.restoreGraphicsState()
    }

    private func drawSizeLabel() {
        let width = Int(selection.width.rounded())
        let height = Int(selection.height.rounded())
        let scale = window?.backingScaleFactor ?? 2
        let text = "\(width) × \(height) pt  ·  \(Int((Double(width) * scale).rounded())) × \(Int((Double(height) * scale).rounded())) px"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let string = text as NSString
        let size = string.size(withAttributes: attributes)
        var origin = NSPoint(x: selection.minX + 10, y: selection.minY + 10)
        if origin.x + size.width + 18 > bounds.width { origin.x = max(8, bounds.width - size.width - 26) }
        if origin.y + size.height + 14 > bounds.height { origin.y = max(8, bounds.height - size.height - 20) }
        let background = NSRect(
            x: origin.x - 7,
            y: origin.y - 4,
            width: size.width + 14,
            height: size.height + 8
        )
        NSColor.black.withAlphaComponent(0.68).setFill()
        NSBezierPath(roundedRect: background, xRadius: 6, yRadius: 6).fill()
        string.draw(at: origin, withAttributes: attributes)
    }

    private func drawInstructions() {
        let text: String
        if validSelection != nil {
            text = "拖动可重新框选  ·  回车开始  ·  Esc 取消"
        } else {
            text = "拖动鼠标，框选要截取的区域  ·  Esc 取消"
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let string = text as NSString
        let size = string.size(withAttributes: attributes)
        let rect = NSRect(
            x: (bounds.width - size.width) / 2 - 14,
            y: bounds.height - 58,
            width: size.width + 28,
            height: size.height + 16
        )
        NSColor.black.withAlphaComponent(0.62).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
        string.draw(
            at: NSPoint(x: rect.minX + 14, y: rect.minY + 8),
            withAttributes: attributes
        )
    }

    private func showToolbar() {
        guard let selection = validSelection else { return }
        let toolbar = ensureToolbar()
        let size = toolbar.frame.size
        let x = min(max(10, selection.midX - size.width / 2), bounds.width - size.width - 10)
        var y = selection.minY - size.height - 10
        if y < 10 {
            y = min(bounds.height - size.height - 10, selection.maxY + 10)
        }
        toolbar.frame.origin = NSPoint(x: x, y: max(10, y))
        toolbar.isHidden = false
        window?.makeFirstResponder(self)
    }

    private func ensureToolbar() -> NSVisualEffectView {
        if let toolbar { return toolbar }
        let toolbar = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 286, height: 48))
        toolbar.material = .hudWindow
        toolbar.blendingMode = .withinWindow
        toolbar.state = .active
        toolbar.wantsLayer = true
        toolbar.layer?.cornerRadius = 10
        toolbar.layer?.masksToBounds = true

        let start = NSButton(title: confirmTitle, target: self, action: #selector(startTapped))
        start.frame = NSRect(x: 10, y: 8, width: 164, height: 32)
        start.bezelStyle = .rounded
        start.controlSize = .large
        start.keyEquivalent = "\r"
        toolbar.addSubview(start)

        let cancel = NSButton(title: "取消", target: self, action: #selector(cancelTapped))
        cancel.frame = NSRect(x: 182, y: 8, width: 94, height: 32)
        cancel.bezelStyle = .rounded
        cancel.controlSize = .large
        cancel.keyEquivalent = "\u{1b}"
        toolbar.addSubview(cancel)

        addSubview(toolbar)
        self.toolbar = toolbar
        return toolbar
    }

    private func hideToolbar() {
        toolbar?.isHidden = true
    }


    private func normalizedRect(from start: NSPoint, to end: NSPoint) -> NSRect {
        NSRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }
}
