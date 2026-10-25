//
//  ImageOverlayView.swift
//  marginalia
//
//  Images on a notebook page: drawing, selecting, moving, resizing.
//
//  Deliberately AppKit and not a SwiftUI overlay: the layer sits above the
//  `NSTextView`, and only `hitTest` can decide precisely enough whether a
//  click belongs to the image or should fall through and land in the text.
//

import AppKit
import Foundation
import PDFKit

@MainActor
final class ImageOverlayNSView: NSView {

    var session: DocumentSession?
    var pageIndex = 0
    /// Only set in the PDF view, to find the page again after it moved.
    weak var page: PDFPage?
    var pageSize: CGSize = PDFPageFactory.a4 {
        didSet { syncBoundsToPageSize() }
    }

    /// In annotation mode images can only be grabbed with the select tool —
    /// with the pen they would otherwise be dragged instead of drawn on.
    var allowsInteraction = true {
        didSet {
            guard allowsInteraction != oldValue else { return }
            needsDisplay = true
        }
    }

    /// A move or resize starts — the PDF view hides its hover outline,
    /// which would otherwise stay behind at the old spot.
    var onInteractionBegan: (() -> Void)?

    private var mouseDownMonitor: Any?
    private var cursorTracking: NSTrackingArea?

    private static let handleSize: CGFloat = 8
    private static let minimumSize: CGFloat = 24

    private enum Interaction {
        case move(id: UUID, start: CGRect, grab: CGPoint)
        case resize(id: UUID, start: CGRect, corner: Corner)
    }

    private enum Corner: CaseIterable {
        case topLeading, topTrailing, bottomLeading, bottomTrailing
    }

    private var interaction: Interaction?
    private var frameBeforeInteraction: CGRect?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    // MARK: - Scaling
    //
    // The view always works in page points. In the PDF view of annotation
    // mode PDFKit sizes it to the zoomed page; the bounds keep the page size,
    // so AppKit does the scaling.

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        syncBoundsToPageSize()
    }

    private func syncBoundsToPageSize() {
        guard frame.width > 0, frame.height > 0, bounds.size != pageSize else { return }
        bounds = CGRect(origin: .zero, size: pageSize)
        needsDisplay = true
    }

    // MARK: - Anchoring
    //
    // A click next to the image does not reach this view — it lands in the
    // text or the PDF view. So we watch for it here to drop the selection,
    // which anchors the image.

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let mouseDownMonitor {
            NSEvent.removeMonitor(mouseDownMonitor)
            self.mouseDownMonitor = nil
        }
        guard window != nil else { return }
        mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.handleMouseDownAnywhere(event)
            return event
        }
    }

    private func handleMouseDownAnywhere(_ event: NSEvent) {
        guard let session, let window, event.window === window else { return }
        let hit = window.contentView?.hitTest(event.locationInWindow)
        if !(hit is ImageOverlayNSView), session.selectedOverlayID != nil {
            session.selectedOverlayID = nil
        }
        // Another page's view may take over the selection — redraw after it.
        DispatchQueue.main.async { [weak self] in self?.needsDisplay = true }
    }

    // MARK: - Coordinates
    //
    // Overlays are stored in PDF points with the origin at the bottom left;
    // this view counts from the top left.

    private func viewRect(_ pdf: CGRect) -> CGRect {
        CGRect(x: pdf.minX, y: pageSize.height - pdf.maxY, width: pdf.width, height: pdf.height)
    }

    private func pdfRect(_ view: CGRect) -> CGRect {
        CGRect(x: view.minX, y: pageSize.height - view.maxY, width: view.width, height: view.height)
    }

    private var overlays: [Overlay] {
        session?.imageOverlays(atPageIndex: pageIndex) ?? []
    }

    private func handleRects(for rect: CGRect) -> [(Corner, CGRect)] {
        let s = Self.handleSize
        return [
            (.topLeading, CGRect(x: rect.minX - s / 2, y: rect.minY - s / 2, width: s, height: s)),
            (.topTrailing, CGRect(x: rect.maxX - s / 2, y: rect.minY - s / 2, width: s, height: s)),
            (.bottomLeading, CGRect(x: rect.minX - s / 2, y: rect.maxY - s / 2, width: s, height: s)),
            (.bottomTrailing, CGRect(x: rect.maxX - s / 2, y: rect.maxY - s / 2, width: s, height: s))
        ]
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let session else { return }
        // The selection may have changed — and with it the hand's area.
        window?.invalidateCursorRects(for: self)

        for overlay in overlays {
            guard case .image(let content) = overlay.content,
                  let image = session.image(forAsset: content.assetName)
            else { continue }

            let rect = viewRect(overlay.frame)
            image.draw(
                in: rect,
                from: .zero,
                operation: .sourceOver,
                fraction: content.opacity,
                respectFlipped: true,
                hints: nil
            )

            guard allowsInteraction, overlay.id == session.selectedOverlayID else { continue }

            NSColor.controlAccentColor.setStroke()
            let outline = NSBezierPath(rect: rect)
            outline.lineWidth = 1.5
            outline.stroke()

            for (_, handle) in handleRects(for: rect) {
                NSColor.white.setFill()
                NSColor.controlAccentColor.setStroke()
                let path = NSBezierPath(rect: handle)
                path.fill()
                path.lineWidth = 1
                path.stroke()
            }
        }
    }

    // MARK: - Cursor
    //
    // Over the active image the hand shows that it can be grabbed. Cursor
    // rects alone are not enough: the text view and the PDF view below set
    // their own cursor on every mouse movement — so it is set here as well,
    // and the PDF view asks via `showsHandCursor(atWindowPoint:)`.

    private var selectedRect: CGRect? {
        guard allowsInteraction, let id = session?.selectedOverlayID,
              let overlay = overlays.first(where: { $0.id == id })
        else { return nil }
        return viewRect(overlay.frame)
    }

    func showsHandCursor(atWindowPoint point: NSPoint) -> Bool {
        guard let rect = selectedRect else { return false }
        return rect.insetBy(dx: -Self.handleSize / 2, dy: -Self.handleSize / 2)
            .contains(convert(point, from: nil))
    }

    override func resetCursorRects() {
        if let rect = selectedRect {
            addCursorRect(rect, cursor: .pointingHand)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let cursorTracking { removeTrackingArea(cursorTracking) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        cursorTracking = area
    }

    override func cursorUpdate(with event: NSEvent) {
        if showsHandCursor(atWindowPoint: event.locationInWindow) {
            NSCursor.pointingHand.set()
        } else {
            super.cursorUpdate(with: event)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        guard showsHandCursor(atWindowPoint: event.locationInWindow) else { return }
        // After the views below have set theirs.
        DispatchQueue.main.async { NSCursor.pointingHand.set() }
    }

    // MARK: - Hit Testing
    //
    // `nil` means: this point does not belong to us. The event then falls
    // through to the text view below — exactly as intended.

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let session, allowsInteraction, !isHidden else { return nil }
        let local = convert(point, from: superview)

        for overlay in overlays.reversed() {
            let rect = viewRect(overlay.frame)
            if overlay.id == session.selectedOverlayID {
                for (_, handle) in handleRects(for: rect) where handle.contains(local) {
                    return self
                }
            }
            if rect.contains(local) { return self }
        }
        return nil
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        guard let session else { return }
        let point = convert(event.locationInWindow, from: nil)
        window?.makeFirstResponder(self)
        session.setCurrentPage(pageIndex)

        for overlay in overlays.reversed() {
            let rect = viewRect(overlay.frame)

            if overlay.id == session.selectedOverlayID {
                for (corner, handle) in handleRects(for: rect) where handle.contains(point) {
                    interaction = .resize(id: overlay.id, start: rect, corner: corner)
                    frameBeforeInteraction = overlay.frame
                    trackUntilMouseUp()
                    return
                }
            }

            if rect.contains(point) {
                session.selectedOverlayID = overlay.id
                interaction = .move(
                    id: overlay.id,
                    start: rect,
                    grab: CGPoint(x: point.x - rect.minX, y: point.y - rect.minY)
                )
                frameBeforeInteraction = overlay.frame
                needsDisplay = true
                trackUntilMouseUp()
                return
            }
        }

        session.selectedOverlayID = nil
        needsDisplay = true
    }

    /// Follows the mouse until it is released. PDFKit routes the drag events
    /// of its page layers by position — as soon as the mouse left the image's
    /// old spot, they no longer arrived here and the image stopped halfway.
    private func trackUntilMouseUp() {
        guard let window else { return }
        onInteractionBegan?()
        while let event = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if event.type == .leftMouseUp {
                mouseUp(with: event)
                return
            }
            mouseDragged(with: event)
            NSCursor.closedHand.set()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let session, let interaction else { return }
        let point = convert(event.locationInWindow, from: nil)

        let updated: CGRect
        switch interaction {
        case .move(_, let start, let grab):
            var rect = start
            rect.origin = CGPoint(x: point.x - grab.x, y: point.y - grab.y)
            updated = clamped(rect)

        case .resize(_, let start, let corner):
            updated = clamped(resized(start, corner: corner, to: point))
        }

        let id: UUID
        switch interaction {
        case .move(let value, _, _), .resize(let value, _, _): id = value
        }
        session.previewOverlayFrame(id: id, frame: pdfRect(updated), atPageIndex: pageIndex)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            interaction = nil
            frameBeforeInteraction = nil
        }
        guard let session, let interaction, let before = frameBeforeInteraction else { return }

        let id: UUID
        switch interaction {
        case .move(let value, _, _), .resize(let value, _, _): id = value
        }
        guard let current = overlays.first(where: { $0.id == id })?.frame else { return }
        session.commitOverlayFrame(id: id, from: before, to: current, atPageIndex: pageIndex)
    }

    private func resized(_ rect: CGRect, corner: Corner, to point: CGPoint) -> CGRect {
        var result = rect
        switch corner {
        case .topLeading:
            result.origin.x = min(point.x, rect.maxX - Self.minimumSize)
            result.origin.y = min(point.y, rect.maxY - Self.minimumSize)
            result.size.width = rect.maxX - result.origin.x
            result.size.height = rect.maxY - result.origin.y
        case .topTrailing:
            result.origin.y = min(point.y, rect.maxY - Self.minimumSize)
            result.size.width = max(point.x - rect.minX, Self.minimumSize)
            result.size.height = rect.maxY - result.origin.y
        case .bottomLeading:
            result.origin.x = min(point.x, rect.maxX - Self.minimumSize)
            result.size.width = rect.maxX - result.origin.x
            result.size.height = max(point.y - rect.minY, Self.minimumSize)
        case .bottomTrailing:
            result.size.width = max(point.x - rect.minX, Self.minimumSize)
            result.size.height = max(point.y - rect.minY, Self.minimumSize)
        }
        return result
    }

    /// Images must not leave the page — otherwise they would be cut off in
    /// the export and no longer grabbable on screen.
    private func clamped(_ rect: CGRect) -> CGRect {
        var result = rect
        result.size.width = min(result.width, pageSize.width)
        result.size.height = min(result.height, pageSize.height)
        result.origin.x = min(max(result.origin.x, 0), pageSize.width - result.width)
        result.origin.y = min(max(result.origin.y, 0), pageSize.height - result.height)
        return result
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        guard let session, session.selectedOverlayID != nil else {
            super.keyDown(with: event)
            return
        }
        switch event.keyCode {
        case 51, 117:  // Backspace, Forward Delete
            session.removeSelectedOverlay(atPageIndex: pageIndex)
            needsDisplay = true
        case 53:  // Escape
            session.selectedOverlayID = nil
            needsDisplay = true
        default:
            super.keyDown(with: event)
        }
    }
}
