//
//  AnnotatingPDFView.swift
//  marginalia
//
//  PDFView subclass that intercepts mouse events for the annotation tools.
//  PDFKit offers no hooks for this — the only option is to override the
//  NSResponder methods and convert points into page coordinates ourselves.
//

import AppKit
import PDFKit

@MainActor
protocol AnnotationEditingDelegate: AnyObject {
    var annotationUndoManager: UndoManager { get }

    /// The freehand stroke is finished and already on the page —
    /// it only needs to be registered for undo.
    func annotationView(_ view: AnnotatingPDFView, didFinishLive annotation: PDFAnnotation, on page: PDFPage)

    func annotationView(_ view: AnnotatingPDFView, didCreate annotations: [PDFAnnotation], on page: PDFPage, actionName: String)
    func annotationView(_ view: AnnotatingPDFView, didErase annotation: PDFAnnotation, on page: PDFPage)

    /// A note was moved — it only needs to be recorded for undo.
    func annotationView(_ view: AnnotatingPDFView, didMove annotation: PDFAnnotation, on page: PDFPage, from oldBounds: CGRect)

    /// The text of a note was changed.
    func annotationView(_ view: AnnotatingPDFView, didEditNote annotation: PDFAnnotation, on page: PDFPage, from oldText: String?)

    /// Frame of the topmost image at this spot, in page coordinates. Images
    /// are not annotations — they lie above the page in their own layer.
    func annotationView(_ view: AnnotatingPDFView, imageAt point: CGPoint, on page: PDFPage) -> (id: UUID, frame: CGRect)?
    func annotationView(_ view: AnnotatingPDFView, didEraseImage id: UUID, on page: PDFPage)
}

final class AnnotatingPDFView: PDFView {

    weak var editingDelegate: (any AnnotationEditingDelegate)?

    var activeTool: AnnotationTool = .select {
        didSet {
            guard activeTool != oldValue else { return }
            // Finish the ongoing input when switching tools, otherwise the
            // input field keeps floating without a matching tool.
            noteEditor.finish()
            if !activeTool.usesTextSelection { clearSelection() }
            hideHover()
            window?.invalidateCursorRects(for: self)
        }
    }

    var style = AnnotationStyle()

    // State of an ongoing freehand stroke
    private var liveAnnotation: PDFAnnotation?
    private var livePage: PDFPage?
    private var livePoints: [CGPoint] = []

    // State while moving a note or, with the select tool, any annotation
    // except highlights. `visualStart` is what has to stay on the page —
    // for freehand strokes that is the stroke, not the page-sized bounds.
    private var movingNote: (annotation: PDFAnnotation, page: PDFPage, start: CGRect, visualStart: CGRect, grab: CGPoint)?

    private var hoverTracking: NSTrackingArea?

    /// The annotation the eraser would currently hit, and its real colors.
    /// It is drawn fainter as a preview; the colors have to be restored
    /// before it is deleted or the document is saved.
    private var erasePreview: (annotation: PDFAnnotation, color: NSColor, fontColor: NSColor?)?

    private let noteEditor = StickyNoteEditor()

    /// Outline of the object under the mouse or of the note currently being
    /// moved. While typing, the input field carries the outline itself.
    private lazy var hoverOutline: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.borderWidth = 2
        view.layer?.cornerRadius = 3
        view.layer?.borderColor = NSColor.controlAccentColor.cgColor
        return view
    }()

    // MARK: - Undo from the Responder Chain

    override var undoManager: UndoManager? {
        editingDelegate?.annotationUndoManager
    }

    /// Connects the note editor to the delegate. Called by the coordinator
    /// after setup.
    func prepareNoteEditor() {
        noteEditor.onFinish = { [weak self] annotation, page, outcome in
            guard let self else { return }
            switch outcome {
            case .created:
                // Already on the page; only the undo step happens here.
                self.editingDelegate?.annotationView(self, didFinishLive: annotation, on: page)
            case .edited(let oldText):
                self.editingDelegate?.annotationView(self, didEditNote: annotation, on: page, from: oldText)
            case .discarded, .unchanged:
                break
            }
        }
    }

    func finishNoteEditing() {
        noteEditor.finish()
    }

    override var acceptsFirstResponder: Bool { true }

    // MARK: - Cursor

    override func resetCursorRects() {
        switch activeTool {
        case .select:
            super.resetCursorRects()
        case .highlight, .ink, .text:
            addCursorRect(bounds, cursor: .crosshair)
        case .eraser:
            addCursorRect(bounds, cursor: .disappearingItem)
        }
    }

    // MARK: - Mouse Events

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateHover(for: event)
        // PDFKit sets its own cursor here; over the active image the hand
        // wins.
        if let image = window?.contentView?.hitTest(event.locationInWindow) as? ImageOverlayNSView,
           image.showsHandCursor(atWindowPoint: event.locationInWindow) {
            NSCursor.pointingHand.set()
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        if movingNote == nil { hideHover() }
    }

    override func mouseDown(with event: NSEvent) {
        guard let (page, point) = locate(event) else {
            super.mouseDown(with: event)
            return
        }

        switch activeTool {
        case .select:
            // The select tool moves everything except highlights — those
            // belong to the text. Elsewhere the PDFView's text selection
            // applies. Images are grabbed by their own layer above.
            if let hit = movable(at: point, on: page) {
                beginMovingNote(hit, at: point, on: page)
            } else {
                super.mouseDown(with: event)
            }

        case .highlight:
            // The PDFView handles the selection itself; it is evaluated on mouse up.
            super.mouseDown(with: event)

        case .ink:
            beginStroke(at: point, on: page)

        case .text:
            beginNoteInteraction(at: point, on: page)

        case .eraser:
            // Images lie above everything else, so they are hit first.
            if let image = editingDelegate?.annotationView(self, imageAt: point, on: page) {
                hideHover()
                editingDelegate?.annotationView(self, didEraseImage: image.id, on: page)
                updateHover(for: event)
            } else if let hit = erasable(at: point, on: page) {
                // Restore the real colors first, otherwise the faint preview
                // ends up on the undo stack.
                hideHover()
                editingDelegate?.annotationView(self, didErase: hit, on: page)
                updateHover(for: event)
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        switch activeTool {
        case .ink:
            guard let (page, point) = locate(event), page === livePage else { return }
            extendStroke(to: point)
        case .text:
            guard let (_, point) = locate(event) else { return }
            dragNote(to: point)
        case .select where movingNote != nil:
            guard let (_, point) = locate(event) else { return }
            dragNote(to: point)
        default:
            super.mouseDragged(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        switch activeTool {
        case .ink:
            endStroke()
        case .text:
            endNoteInteraction(editOnClick: true)
            updateHover(for: event)
        case .select where movingNote != nil:
            endNoteInteraction(editOnClick: false)
            updateHover(for: event)
        case .highlight:
            super.mouseUp(with: event)
            convertSelectionToHighlights()
        default:
            super.mouseUp(with: event)
        }
    }

    /// Window coordinates -> (page, point in page coordinates)
    private func locate(_ event: NSEvent) -> (PDFPage, CGPoint)? {
        let viewPoint = convert(event.locationInWindow, from: nil)
        guard let page = page(for: viewPoint, nearest: true) else { return nil }
        return (page, convert(viewPoint, to: page))
    }

    // MARK: - Freehand

    private func beginStroke(at point: CGPoint, on page: PDFPage) {
        // The bounds deliberately cover the whole page: that way the path
        // does not have to be converted into a new local coordinate system
        // for every point while drawing.
        let annotation = PDFAnnotation(
            bounds: page.bounds(for: displayBox),
            forType: .ink,
            withProperties: nil
        )
        annotation.color = style.inkNSColor

        let border = PDFBorder()
        border.lineWidth = style.inkWidth
        border.style = .solid
        annotation.border = border

        page.addAnnotation(annotation)
        liveAnnotation = annotation
        livePage = page
        livePoints = [point]
    }

    private func extendStroke(to point: CGPoint) {
        guard let annotation = liveAnnotation, let last = livePoints.last else { return }
        // Skip micro movements, otherwise the path gets needlessly large.
        guard hypot(point.x - last.x, point.y - last.y) >= 1 else { return }

        livePoints.append(point)

        if let previous = annotation.paths?.last {
            annotation.remove(previous)
        }
        annotation.add(smoothPath(through: livePoints))
        setNeedsDisplay(bounds)
    }

    private func endStroke() {
        defer {
            liveAnnotation = nil
            livePage = nil
            livePoints = []
        }
        guard let annotation = liveAnnotation, let page = livePage else { return }

        // A single click without movement: nothing meaningful was drawn.
        guard livePoints.count > 1 else {
            page.removeAnnotation(annotation)
            setNeedsDisplay(bounds)
            return
        }

        editingDelegate?.annotationView(self, didFinishLive: annotation, on: page)
    }

    /// Cubic smoothing through the midpoints of consecutive points.
    private func smoothPath(through points: [CGPoint]) -> NSBezierPath {
        let path = NSBezierPath()
        path.lineWidth = style.inkWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        guard let first = points.first else { return path }
        path.move(to: first)

        if points.count == 2 {
            path.line(to: points[1])
            return path
        }

        for index in 1..<(points.count - 1) {
            let current = points[index]
            let next = points[index + 1]
            let midpoint = CGPoint(x: (current.x + next.x) / 2, y: (current.y + next.y) / 2)
            path.curve(to: midpoint, controlPoint1: current, controlPoint2: current)
        }
        if let last = points.last {
            path.line(to: last)
        }
        return path
    }

    // MARK: - Sticky Notes

    /// On an existing note a move begins; otherwise a new one is created and
    /// typing starts right away.
    private func beginNoteInteraction(at point: CGPoint, on page: PDFPage) {
        // A click that ends an ongoing input does not create a new note yet.
        // Depending on the order of events, AppKit has already ended the
        // input before we get here — both cases have to be caught.
        if noteEditor.finish() { return }
        if noteEditor.consumeFocusLossFinish() { return }

        if let hit = note(at: point, on: page) {
            beginMovingNote(hit, at: point, on: page)
            return
        }

        // The new note only goes onto the page once it has text.
        let origin = CGPoint(x: point.x, y: point.y - AnnotationStyle.defaultNoteSize.height)
        let annotation = makeNote(
            bounds: clampToPage(CGRect(origin: origin, size: AnnotationStyle.defaultNoteSize), on: page)
        )
        beginEditing(annotation, on: page, isNew: true)
    }

    private func note(at point: CGPoint, on page: PDFPage) -> PDFAnnotation? {
        guard let hit = page.annotation(at: point), hit.type == "FreeText" else { return nil }
        return hit
    }

    /// What the select tool would move at this spot.
    private func movable(at point: CGPoint, on page: PDFPage) -> PDFAnnotation? {
        guard let hit = erasable(at: point, on: page),
              !["Highlight", "Link", "Widget"].contains(hit.type ?? "")
        else { return nil }
        return hit
    }

    private func beginMovingNote(_ note: PDFAnnotation, at point: CGPoint, on page: PDFPage) {
        let visual = visualBounds(of: note)
        movingNote = (
            note, page, note.bounds, visual,
            CGPoint(x: point.x - note.bounds.minX, y: point.y - note.bounds.minY)
        )
        showOutline(around: visual, on: page)
    }

    private func dragNote(to point: CGPoint) {
        guard let moving = movingNote else { return }
        // Clamp what is visible, then shift the bounds by the same amount.
        var visual = moving.visualStart
        visual.origin = CGPoint(
            x: point.x - moving.grab.x + (moving.visualStart.minX - moving.start.minX),
            y: point.y - moving.grab.y + (moving.visualStart.minY - moving.start.minY)
        )
        visual = clampToPage(visual, on: moving.page)
        moving.annotation.bounds = moving.start.offsetBy(
            dx: visual.minX - moving.visualStart.minX,
            dy: visual.minY - moving.visualStart.minY
        )
        showOutline(around: visual, on: moving.page)
        needsDisplay = true
    }

    private func endNoteInteraction(editOnClick: Bool) {
        guard let moving = movingNote else { return }
        movingNote = nil

        if moving.annotation.bounds != moving.start {
            editingDelegate?.annotationView(
                self, didMove: moving.annotation, on: moving.page, from: moving.start
            )
        } else if editOnClick {
            hideHover()
            // A click without movement means: keep writing.
            beginEditing(moving.annotation, on: moving.page, isNew: false)
        }
    }

    // MARK: - Hover

    /// Outlines the object under the mouse: for the select tool everything
    /// it can move, notes for the note tool, and for the eraser everything a
    /// click would delete — which is also drawn fainter.
    private func updateHover(for event: NSEvent) {
        guard movingNote == nil else { return }
        guard let (page, point) = locate(event) else { return hideHover() }

        switch activeTool {
        case .select:
            if let image = editingDelegate?.annotationView(self, imageAt: point, on: page) {
                return showOutline(around: image.frame, on: page)
            }
            guard let hit = movable(at: point, on: page) else { return hideHover() }
            showOutline(around: visualBounds(of: hit), on: page)

        case .text:
            guard let hit = note(at: point, on: page) else { return hideHover() }
            showOutline(around: hit.bounds, on: page)

        case .eraser:
            if let image = editingDelegate?.annotationView(self, imageAt: point, on: page) {
                endErasePreview()
                return showOutline(around: image.frame, on: page)
            }
            guard let hit = erasable(at: point, on: page) else { return hideHover() }
            if erasePreview?.annotation !== hit {
                endErasePreview()
                beginErasePreview(of: hit)
            }
            showOutline(around: visualBounds(of: hit), on: page)

        case .highlight, .ink:
            hideHover()
        }
    }

    /// Removes the outline and the eraser preview. Must run before every
    /// save and after undo/redo so the real colors are back.
    func hideHover() {
        hoverOutline.removeFromSuperview()
        endErasePreview()
    }

    private func beginErasePreview(of annotation: PDFAnnotation) {
        let fade = 0.35
        erasePreview = (annotation, annotation.color, annotation.fontColor)
        annotation.color = annotation.color.withAlphaComponent(annotation.color.alphaComponent * fade)
        if let fontColor = annotation.fontColor {
            annotation.fontColor = fontColor.withAlphaComponent(fontColor.alphaComponent * fade)
        }
        needsDisplay = true
    }

    private func endErasePreview() {
        guard let preview = erasePreview else { return }
        erasePreview = nil
        preview.annotation.color = preview.color
        if let fontColor = preview.fontColor {
            preview.annotation.fontColor = fontColor
        }
        needsDisplay = true
    }

    /// What an eraser click at this spot would delete.
    ///
    /// Freehand strokes span their bounds across the whole page — for them
    /// only the distance to the stroke itself counts.
    private func erasable(at point: CGPoint, on page: PDFPage) -> PDFAnnotation? {
        for annotation in page.annotations.reversed() where annotation.type != "Popup" {
            if annotation.type == "Ink" {
                if inkStroke(of: annotation, tolerance: 4).contains(point) { return annotation }
            } else if annotation.bounds.contains(point) {
                return annotation
            }
        }
        return nil
    }

    /// Outline of the drawn strokes in page coordinates. The paths of an
    /// ink annotation are relative to the origin of its bounds.
    private func inkStroke(of annotation: PDFAnnotation, tolerance: CGFloat) -> CGPath {
        let combined = CGMutablePath()
        let lineWidth = max(annotation.border?.lineWidth ?? 1, 1)
        let offset = CGAffineTransform(translationX: annotation.bounds.minX, y: annotation.bounds.minY)
        for path in annotation.paths ?? [] {
            let stroked = path.cgPath.copy(
                strokingWithWidth: lineWidth + tolerance * 2,
                lineCap: .round,
                lineJoin: .round,
                miterLimit: 10
            )
            combined.addPath(stroked, transform: offset)
        }
        return combined
    }

    private func visualBounds(of annotation: PDFAnnotation) -> CGRect {
        guard annotation.type == "Ink" else { return annotation.bounds }
        let stroke = inkStroke(of: annotation, tolerance: 0)
        return stroke.isEmpty ? annotation.bounds : stroke.boundingBoxOfPath.insetBy(dx: -2, dy: -2)
    }

    /// Places the outline around a rectangle of the page — in document view
    /// coordinates so it moves along when scrolling.
    private func showOutline(around rect: CGRect, on page: PDFPage) {
        guard let documentView else { return }
        if hoverOutline.superview !== documentView {
            documentView.addSubview(hoverOutline)
        }
        let inView = convert(rect, from: page)
        hoverOutline.frame = documentView.convert(inView, from: self)
    }

    private func beginEditing(_ annotation: PDFAnnotation, on page: PDFPage, isNew: Bool) {
        prepareNoteEditor()
        noteEditor.begin(editing: annotation, on: page, isNew: isNew, in: self, style: style)
    }

    private func makeNote(bounds: CGRect) -> PDFAnnotation {
        let annotation = PDFAnnotation(bounds: bounds, forType: .freeText, withProperties: nil)
        annotation.contents = ""
        annotation.font = .systemFont(ofSize: style.textSize)
        annotation.fontColor = style.textNSColor
        annotation.color = style.noteNSColor
        annotation.alignment = .left
        let border = PDFBorder()
        border.lineWidth = 0
        annotation.border = border
        return annotation
    }

    private func clampToPage(_ rect: CGRect, on page: PDFPage) -> CGRect {
        let bounds = page.bounds(for: displayBox)
        var result = rect
        result.origin.x = min(max(result.minX, bounds.minX), bounds.maxX - result.width)
        result.origin.y = min(max(result.minY, bounds.minY), bounds.maxY - result.height)
        return result
    }

    // MARK: - Highlights from the Text Selection

    private func convertSelectionToHighlights() {
        guard let selection = currentSelection, !selection.string.isNilOrEmpty else { return }

        var byPage: [PDFPage: [PDFAnnotation]] = [:]

        // Line by line, otherwise a multi-line range would also cover the
        // empty areas left and right of the lines.
        for line in selection.selectionsByLine() {
            for page in line.pages {
                let bounds = line.bounds(for: page)
                guard bounds.width > 0, bounds.height > 0 else { continue }
                let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
                annotation.color = style.highlightNSColor
                byPage[page, default: []].append(annotation)
            }
        }

        clearSelection()

        for (page, annotations) in byPage {
            editingDelegate?.annotationView(self, didCreate: annotations, on: page, actionName: "Highlight")
        }
    }
}

private extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool {
        self?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
    }
}
