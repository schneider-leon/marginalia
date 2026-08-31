//
//  AnnotatingPDFView.swift
//  BestNotes
//
//  PDFView-Subklasse, die Mausereignisse fuer die Annotationswerkzeuge
//  abfaengt. PDFKit bietet dafuer keine Hooks — es bleibt nur, die
//  NSResponder-Methoden zu ueberschreiben und Punkte selbst in
//  Seitenkoordinaten umzurechnen.
//

import AppKit
import PDFKit

@MainActor
protocol AnnotationEditingDelegate: AnyObject {
    var annotationUndoManager: UndoManager { get }

    /// Freihandstrich ist fertig und liegt bereits auf der Seite —
    /// nur noch fuer Undo registrieren.
    func annotationView(_ view: AnnotatingPDFView, didFinishLive annotation: PDFAnnotation, on page: PDFPage)

    func annotationView(_ view: AnnotatingPDFView, didCreate annotations: [PDFAnnotation], on page: PDFPage, actionName: String)
    func annotationView(_ view: AnnotatingPDFView, didErase annotation: PDFAnnotation, on page: PDFPage)

    /// Ein Zettel wurde verschoben — nur noch fuer Undo zu vermerken.
    func annotationView(_ view: AnnotatingPDFView, didMove annotation: PDFAnnotation, on page: PDFPage, from oldBounds: CGRect)

    /// Der Text eines Zettels wurde geaendert.
    func annotationView(_ view: AnnotatingPDFView, didEditNote annotation: PDFAnnotation, on page: PDFPage, from oldText: String?)
}

final class AnnotatingPDFView: PDFView {

    weak var editingDelegate: (any AnnotationEditingDelegate)?

    var activeTool: AnnotationTool = .select {
        didSet {
            guard activeTool != oldValue else { return }
            // Beim Werkzeugwechsel die laufende Eingabe abschliessen, sonst
            // schwebt das Eingabefeld ohne zugehoeriges Werkzeug weiter.
            noteEditor.finish()
            if !activeTool.usesTextSelection { clearSelection() }
            window?.invalidateCursorRects(for: self)
        }
    }

    var style = AnnotationStyle()

    // Zustand eines laufenden Freihandstrichs
    private var liveAnnotation: PDFAnnotation?
    private var livePage: PDFPage?
    private var livePoints: [CGPoint] = []

    // Zustand beim Verschieben eines Notizzettels
    private var movingNote: (annotation: PDFAnnotation, page: PDFPage, start: CGRect, grab: CGPoint)?

    private let noteEditor = StickyNoteEditor()

    // MARK: - Undo aus der Responder-Chain

    override var undoManager: UndoManager? {
        editingDelegate?.annotationUndoManager
    }

    /// Verbindet den Zetteleditor mit dem Delegaten. Wird vom Coordinator
    /// nach dem Aufbau gerufen.
    func prepareNoteEditor() {
        noteEditor.onFinish = { [weak self] annotation, page, outcome in
            guard let self else { return }
            switch outcome {
            case .created:
                // Steht bereits auf der Seite; hier nur der Undo-Schritt.
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

    // MARK: - Mausereignisse

    override func mouseDown(with event: NSEvent) {
        guard let (page, point) = locate(event) else {
            super.mouseDown(with: event)
            return
        }

        switch activeTool {
        case .select, .highlight:
            // Auswahl macht die PDFView selbst; ausgewertet wird beim Loslassen.
            super.mouseDown(with: event)

        case .ink:
            beginStroke(at: point, on: page)

        case .text:
            beginNoteInteraction(at: point, on: page)

        case .eraser:
            if let hit = page.annotation(at: point) {
                editingDelegate?.annotationView(self, didErase: hit, on: page)
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
        default:
            super.mouseDragged(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        switch activeTool {
        case .ink:
            endStroke()
        case .text:
            endNoteInteraction()
        case .highlight:
            super.mouseUp(with: event)
            convertSelectionToHighlights()
        default:
            super.mouseUp(with: event)
        }
    }

    /// Fensterkoordinaten -> (Seite, Punkt in Seitenkoordinaten)
    private func locate(_ event: NSEvent) -> (PDFPage, CGPoint)? {
        let viewPoint = convert(event.locationInWindow, from: nil)
        guard let page = page(for: viewPoint, nearest: true) else { return nil }
        return (page, convert(viewPoint, to: page))
    }

    // MARK: - Freihand

    private func beginStroke(at point: CGPoint, on page: PDFPage) {
        // Die Bounds umfassen bewusst die ganze Seite: so muss der Pfad
        // waehrend des Zeichnens nicht bei jedem Punkt in ein neues
        // lokales Koordinatensystem umgerechnet werden.
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
        // Mikrobewegungen ueberspringen, sonst wird der Pfad unnoetig gross.
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

        // Einzelner Klick ohne Bewegung: nichts Sinnvolles gezeichnet.
        guard livePoints.count > 1 else {
            page.removeAnnotation(annotation)
            setNeedsDisplay(bounds)
            return
        }

        editingDelegate?.annotationView(self, didFinishLive: annotation, on: page)
    }

    /// Kubische Glaettung ueber die Mittelpunkte aufeinanderfolgender Punkte.
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

    // MARK: - Notizzettel

    /// Auf einem vorhandenen Zettel beginnt ein Verschieben, sonst entsteht
    /// ein neuer und die Eingabe beginnt sofort.
    private func beginNoteInteraction(at point: CGPoint, on page: PDFPage) {
        noteEditor.finish()

        if let hit = page.annotation(at: point), hit.type == "FreeText" {
            movingNote = (
                hit, page, hit.bounds,
                CGPoint(x: point.x - hit.bounds.minX, y: point.y - hit.bounds.minY)
            )
            return
        }

        // Der neue Zettel kommt erst auf die Seite, wenn er beschriftet ist.
        let origin = CGPoint(x: point.x, y: point.y - AnnotationStyle.defaultNoteSize.height)
        let annotation = makeNote(
            bounds: clampToPage(CGRect(origin: origin, size: AnnotationStyle.defaultNoteSize), on: page)
        )
        beginEditing(annotation, on: page, isNew: true)
    }

    private func dragNote(to point: CGPoint) {
        guard let moving = movingNote else { return }
        var bounds = moving.start
        bounds.origin = CGPoint(x: point.x - moving.grab.x, y: point.y - moving.grab.y)
        moving.annotation.bounds = clampToPage(bounds, on: moving.page)
        needsDisplay = true
    }

    private func endNoteInteraction() {
        guard let moving = movingNote else { return }
        movingNote = nil

        if moving.annotation.bounds != moving.start {
            editingDelegate?.annotationView(
                self, didMove: moving.annotation, on: moving.page, from: moving.start
            )
        } else {
            // Klick ohne Bewegung heisst: weiterschreiben.
            beginEditing(moving.annotation, on: moving.page, isNew: false)
        }
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

    // MARK: - Highlight aus der Textauswahl

    private func convertSelectionToHighlights() {
        guard let selection = currentSelection, !selection.string.isNilOrEmpty else { return }

        var byPage: [PDFPage: [PDFAnnotation]] = [:]

        // Zeilenweise, sonst umfasst ein mehrzeiliger Bereich auch die
        // Leerflaechen links und rechts der Zeilen.
        for line in selection.selectionsByLine() {
            for page in line.pages {
                let bounds = line.bounds(for: page)
                guard bounds.width > 0, bounds.height > 0 else { continue }
                let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
                annotation.color = style.highlightNSColor
                annotation.contents = line.string
                byPage[page, default: []].append(annotation)
            }
        }

        clearSelection()

        for (page, annotations) in byPage {
            editingDelegate?.annotationView(self, didCreate: annotations, on: page, actionName: "Markieren")
        }
    }
}

private extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool {
        self?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
    }
}
