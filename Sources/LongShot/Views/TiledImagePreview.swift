import AppKit
import LongShotCore
import SwiftUI

enum PreviewMode: String, CaseIterable, Identifiable {
    case fitWidth = "适合宽度"
    case actualSize = "100%"
    case doubleSize = "200%"

    var id: String { rawValue }
}

/// An AppKit-backed preview that draws only the visible tiles of the raw image.
/// This keeps memory flat and allows scrolling through images that are far
/// taller than any single GPU texture or NSImage could hold.
struct TiledImagePreview: NSViewRepresentable {
    let rawImage: RawImageFile
    let mode: PreviewMode

    func makeNSView(context: Context) -> PreviewContainer {
        let container = PreviewContainer()
        container.configure(rawImage: rawImage, mode: mode)
        return container
    }

    func updateNSView(_ nsView: PreviewContainer, context: Context) {
        nsView.configure(rawImage: rawImage, mode: mode)
    }
}

final class PreviewContainer: NSView {
    private let scrollView = NSScrollView()
    private let documentView = TiledDocumentView()
    private var rawImage: RawImageFile?
    private var mode: PreviewMode = .fitWidth

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        scrollView.frame = bounds
        scrollView.autoresizingMask = [.width, .height]
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .underPageBackgroundColor
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = documentView
        addSubview(scrollView)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        updateDocumentFrame(preservePosition: true)
    }

    func configure(rawImage: RawImageFile, mode: PreviewMode) {
        let changedImage = self.rawImage !== rawImage
        self.rawImage = rawImage
        self.mode = mode
        if changedImage, let image = try? rawImage.cgImage() {
            documentView.image = image
            documentView.imageWidth = rawImage.width
            documentView.imageHeight = rawImage.height
        }
        updateDocumentFrame(preservePosition: !changedImage)
    }

    private func updateDocumentFrame(preservePosition: Bool) {
        guard let rawImage else { return }
        let contentSize = scrollView.contentSize
        guard contentSize.width > 20, contentSize.height > 20 else { return }

        let backingScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let availableWidth = max(80, contentSize.width - 48)
        let scale: CGFloat
        switch mode {
        case .fitWidth:
            scale = min(1.0, availableWidth / CGFloat(rawImage.width))
        case .actualSize:
            scale = 1.0 / max(1, backingScale)
        case .doubleSize:
            scale = 2.0 / max(1, backingScale)
        }

        let imageWidth = CGFloat(rawImage.width) * scale
        let imageHeight = CGFloat(rawImage.height) * scale
        let documentWidth = max(contentSize.width, imageWidth + 48)
        let documentHeight = max(contentSize.height, imageHeight + 48)
        let imageX = (documentWidth - imageWidth) / 2
        let imageY: CGFloat = 24

        let clipView = scrollView.contentView
        let oldHeight = max(1, documentView.frame.height - clipView.bounds.height)
        let oldFraction = min(1, max(0, clipView.bounds.origin.y / oldHeight))

        documentView.imageRect = NSRect(
            x: imageX,
            y: imageY,
            width: imageWidth,
            height: imageHeight
        )
        documentView.imageScale = scale
        documentView.frame = NSRect(
            x: 0,
            y: 0,
            width: documentWidth,
            height: documentHeight
        )
        documentView.needsDisplay = true
        documentView.setNeedsDisplay(documentView.visibleRect)

        let newMax = max(1, documentView.frame.height - clipView.bounds.height)
        let targetY = preservePosition ? oldFraction * newMax : 0
        clipView.scroll(to: NSPoint(x: 0, y: targetY))
        scrollView.reflectScrolledClipView(clipView)
    }
}

final class TiledDocumentView: NSView {
    var image: CGImage?
    var imageWidth = 1
    var imageHeight = 1
    var imageRect: NSRect = .zero
    var imageScale: CGFloat = 1

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let drawRect = dirtyRect.intersection(visibleRect)
        guard !drawRect.isEmpty else { return }
        NSColor.underPageBackgroundColor.setFill()
        drawRect.fill()

        guard let image, imageRect.width > 0, imageRect.height > 0 else { return }

        let background = drawRect.intersection(imageRect)
        guard !background.isEmpty else { return }
        NSColor.white.setFill()
        background.fill()

        let clipped = drawRect.intersection(imageRect)
        guard !clipped.isEmpty else { return }

        let scale = max(0.01, imageScale)
        let sourceX0 = max(0, Int(floor((clipped.minX - imageRect.minX) / scale)))
        let sourceY0 = max(0, Int(floor((clipped.minY - imageRect.minY) / scale)))
        let sourceX1 = min(imageWidth, Int(ceil((clipped.maxX - imageRect.minX) / scale)))
        let sourceY1 = min(imageHeight, Int(ceil((clipped.maxY - imageRect.minY) / scale)))
        guard sourceX1 > sourceX0, sourceY1 > sourceY0 else { return }

        let sourceRect = CGRect(
            x: sourceX0,
            y: sourceY0,
            width: sourceX1 - sourceX0,
            height: sourceY1 - sourceY0
        )
        guard let tile = image.cropping(to: sourceRect) else { return }

        let destination = NSRect(
            x: imageRect.minX + CGFloat(sourceX0) * scale,
            y: imageRect.minY + CGFloat(sourceY0) * scale,
            width: CGFloat(sourceX1 - sourceX0) * scale,
            height: CGFloat(sourceY1 - sourceY0) * scale
        )

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: clipped).addClip()
        let interpolation: NSImageInterpolation = scale >= 0.999 ? .none : .high
        NSGraphicsContext.current?.imageInterpolation = interpolation
        let tileImage = NSImage(
            cgImage: tile,
            size: NSSize(width: tile.width, height: tile.height)
        )
        tileImage.draw(
            in: destination,
            from: .zero,
            operation: .copy,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: interpolation]
        )
        NSGraphicsContext.restoreGraphicsState()

        NSColor.labelColor.withAlphaComponent(0.10).setStroke()
        let border = NSBezierPath(rect: imageRect)
        border.lineWidth = 1
        border.stroke()
    }
}
