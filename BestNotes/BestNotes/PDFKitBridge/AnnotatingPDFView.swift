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
    func annotationView(_ view: AnnotatingPDFView, didRequestCommentAt point: CGPoint, on page: PDFPage)
}

final class AnnotatingPDFView: PDFView {

    weak var editingDelegate: (any AnnotationEditingDelegate)?

    var activeTool: AnnotationTool = .select {
        didSet {
            guard activeTool != oldValue else { return }
            if !activeTool.usesTextSelection { clearSelection() }
            window?.invalidateCursorRects(for: self)
        }
    }

    var style = AnnotationStyle()

    // Zustand eines laufenden Freihandstrichs
    private var liveAnnotation: PDFAnnotation?
    private var livePage: PDFPage?
    private var livePoints: [CGPoint] = []

    // MARK: - Undo aus der Responder-Chain

    override var undoManager: UndoManager? {
        editingDelegate?.annotationUndoManager
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
            editingDelegate?.annotationView(self, didRequestCommentAt: point, on: page)

        case .eraser:
            if let hit = page.annotation(at: point) {
                editingDelegate?.annotationView(self, didErase: hit, on: page)
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard activeTool == .ink else {
            super.mouseDragged(with: event)
            return
        }
        guard let (page, point) = locate(event), page === livePage else { return }
        extendStroke(to: point)
    }

    override func mouseUp(with event: NSEvent) {
        switch activeTool {
        case .ink:
            endStroke()
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
