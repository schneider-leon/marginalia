//
//  DocumentSession.swift
//  BestNotes
//
//  Zustand *eines* geoeffneten Dokuments. Ab Schritt 5 existiert pro Tab
//  genau eine Session.
//

import AppKit
import Foundation
import Observation
import PDFKit

// MARK: - Kommandokanal Richtung PDFKit

/// Aktionen, die nur die `PDFView` selbst ausfuehren kann (Scrollen, Zoomen).
///
/// Die Session ruft sie imperativ auf, statt sie als Zustand zu deklarieren —
/// sonst wuerde SwiftUI bei jedem Scrollen ein Update zurueckschreiben wollen.
@MainActor
protocol PDFViewCommandTarget: AnyObject {
    func go(toPageIndex index: Int)
    func goToNextPage()
    func goToPreviousPage()
    func zoomIn()
    func zoomOut()
    func fitToWindow()
    func refreshDisplay()
}

// MARK: - Anzeigemodus

enum PageDisplayMode: String, CaseIterable, Identifiable {
    case singlePage
    case singlePageContinuous
    case twoUpContinuous

    var id: String { rawValue }

    var label: String {
        switch self {
        case .singlePage: "Einzelseite"
        case .singlePageContinuous: "Fortlaufend"
        case .twoUpContinuous: "Doppelseite"
        }
    }

    var symbol: String {
        switch self {
        case .singlePage: "doc"
        case .singlePageContinuous: "doc.on.doc"
        case .twoUpContinuous: "book"
        }
    }

    var pdfDisplayMode: PDFDisplayMode {
        switch self {
        case .singlePage: .singlePage
        case .singlePageContinuous: .singlePageContinuous
        case .twoUpContinuous: .twoUpContinuous
        }
    }
}

// MARK: - Fehler

/// Woher der Inhalt einer Session stammt und wohin gesichert wird.
enum DocumentBacking {
    /// Eigenstaendige PDF in der Bibliothek.
    case pdfFile(URL)
    /// Notizbuch — gesichert wird ins Paket, nicht in eine lose PDF.
    case notebook(NotebookPackage)
}

enum DocumentSessionError: LocalizedError {
    case unreadablePDF(URL)

    var errorDescription: String? {
        switch self {
        case .unreadablePDF(let url):
            "„\(url.lastPathComponent)“ konnte nicht als PDF gelesen werden."
        }
    }

    var recoverySuggestion: String? {
        "Die Datei ist moeglicherweise beschaedigt, passwortgeschuetzt oder kein PDF."
    }
}

/// Ein angeklickter Punkt, fuer den noch der Kommentartext fehlt.
struct PendingComment: Identifiable {
    let id = UUID()
    let point: CGPoint
    let page: PDFPage
}

// MARK: - Session

@MainActor
@Observable
final class DocumentSession: Identifiable {
    let id = UUID()
    let backing: DocumentBacking
    let document: PDFDocument

    /// Der Name aus der Bibliothek — dort ist er massgeblich, `info.json`
    /// bekommt ihn beim naechsten Sichern nachgereicht.
    var displayName: String

    /// Vom Nutzer steuerbar, wird in `updateNSView` an die `PDFView` gespiegelt.
    var displayMode: PageDisplayMode = .singlePageContinuous
    var activeTool: AnnotationTool = .select
    var style = AnnotationStyle()

    /// Aus der `PDFView` zurueckgespiegelt — nur der Coordinator schreibt hier.
    private(set) var currentPageIndex = 0
    private(set) var scaleFactor: CGFloat = 1
    private(set) var minScaleFactor: CGFloat = 0.25
    private(set) var maxScaleFactor: CGFloat = 5

    private(set) var hasUnsavedChanges = false
    var pendingComment: PendingComment?

    @ObservationIgnored
    weak var commandTarget: (any PDFViewCommandTarget)?

    @ObservationIgnored
    let undoManager = UndoManager()

    /// Nur da, damit SwiftUI die Undo-Buttons neu bewertet — der UndoManager
    /// selbst ist nicht observierbar.
    private(set) var editRevision = 0

    var url: URL {
        switch backing {
        case .pdfFile(let url): url
        case .notebook(let package): package.url
        }
    }

    var notebook: NotebookPackage? {
        if case .notebook(let package) = backing { package } else { nil }
    }

    var pageCount: Int { document.pageCount }
    var canGoToNextPage: Bool { currentPageIndex + 1 < pageCount }
    var canGoToPreviousPage: Bool { currentPageIndex > 0 }
    var canUndo: Bool { _ = editRevision; return undoManager.canUndo }
    var canRedo: Bool { _ = editRevision; return undoManager.canRedo }

    init(pdfAt url: URL, name: String) throws {
        guard let document = PDFDocument(url: url) else {
            throw DocumentSessionError.unreadablePDF(url)
        }
        self.backing = .pdfFile(url)
        self.document = document
        self.displayName = name
        undoManager.levelsOfUndo = 100
    }

    init(package: NotebookPackage, name: String) {
        self.backing = .notebook(package)
        self.document = package.pdf
        self.displayName = name
        undoManager.levelsOfUndo = 100
    }

    func close() {
        commandTarget = nil
        undoManager.removeAllActions()
    }

    // MARK: Navigation & Zoom (SwiftUI/Menue -> PDFView)

    func go(toPageIndex index: Int) {
        guard index >= 0, index < pageCount else { return }
        commandTarget?.go(toPageIndex: index)
    }

    func goToNextPage() { commandTarget?.goToNextPage() }
    func goToPreviousPage() { commandTarget?.goToPreviousPage() }
    func zoomIn() { commandTarget?.zoomIn() }
    func zoomOut() { commandTarget?.zoomOut() }
    func fitToWindow() { commandTarget?.fitToWindow() }

    // MARK: Rueckmeldungen (PDFView -> SwiftUI)

    func reportPageIndex(_ index: Int) {
        guard index != currentPageIndex else { return }
        currentPageIndex = index
    }

    func reportScale(_ scale: CGFloat, min: CGFloat, max: CGFloat) {
        if scaleFactor != scale { scaleFactor = scale }
        if minScaleFactor != min { minScaleFactor = min }
        if maxScaleFactor != max { maxScaleFactor = max }
    }

    // MARK: Annotationen

    func addAnnotations(
        _ annotations: [PDFAnnotation],
        on page: PDFPage,
        actionName: String,
        alreadyPlaced: Bool = false
    ) {
        guard !annotations.isEmpty else { return }
        if !alreadyPlaced {
            annotations.forEach(page.addAnnotation)
        }
        undoManager.setActionName(actionName)
        undoManager.registerUndo(withTarget: self) { session in
            session.removeAnnotations(annotations, on: page, actionName: actionName)
        }
        didEdit()
    }

    func removeAnnotations(_ annotations: [PDFAnnotation], on page: PDFPage, actionName: String) {
        guard !annotations.isEmpty else { return }
        annotations.forEach(page.removeAnnotation)
        undoManager.setActionName(actionName)
        undoManager.registerUndo(withTarget: self) { session in
            session.addAnnotations(annotations, on: page, actionName: actionName)
        }
        didEdit()
    }

    func undo() {
        guard undoManager.canUndo else { return }
        undoManager.undo()
        didEdit()
    }

    func redo() {
        guard undoManager.canRedo else { return }
        undoManager.redo()
        didEdit()
    }

    private func didEdit() {
        hasUnsavedChanges = true
        editRevision &+= 1
        commandTarget?.refreshDisplay()
    }

    // MARK: Kommentar

    func requestComment(at point: CGPoint, on page: PDFPage) {
        pendingComment = PendingComment(point: point, page: page)
    }

    func commitPendingComment(text: String) {
        guard let pending = pendingComment else { return }
        pendingComment = nil

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let annotation = PDFAnnotation(
            bounds: commentBounds(for: trimmed, at: pending.point, on: pending.page),
            forType: .freeText,
            withProperties: nil
        )
        annotation.contents = trimmed
        annotation.font = .systemFont(ofSize: style.textSize)
        annotation.fontColor = style.textNSColor
        annotation.color = .clear
        annotation.alignment = .left

        addAnnotations([annotation], on: pending.page, actionName: "Kommentar")
    }

    private func commentBounds(for text: String, at point: CGPoint, on page: PDFPage) -> CGRect {
        let font = NSFont.systemFont(ofSize: style.textSize)
        let maxWidth: CGFloat = 260
        let padding: CGFloat = 6

        let measured = (text as NSString).boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        let size = CGSize(
            width: min(maxWidth, ceil(measured.width)) + padding * 2,
            height: ceil(measured.height) + padding * 2
        )

        // Der Klickpunkt ist die obere linke Ecke; danach in die Seite klemmen.
        let pageBounds = page.bounds(for: .cropBox)
        let x = min(max(point.x, pageBounds.minX), pageBounds.maxX - size.width)
        let y = min(max(point.y - size.height, pageBounds.minY), pageBounds.maxY - size.height)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    // MARK: Speichern & Export

    /// Schreibt zurueck — in die PDF-Datei oder ins Notizbuchpaket.
    func save() throws {
        switch backing {
        case .pdfFile(let url):
            try PDFExportService.write(document, to: url)
        case .notebook(let package):
            package.setTitle(displayName)
            package.markPDFDirty()
            try package.write()
        }
        hasUnsavedChanges = false
    }

    /// Schreibt eine Kopie an einen frei gewaehlten Ort.
    /// - Returns: das Ziel, oder `nil` wenn der Nutzer abgebrochen hat.
    @discardableResult
    func exportCopy() throws -> URL? {
        guard let destination = PDFExportService.chooseExportURL(suggestedName: displayName) else {
            return nil
        }
        try PDFExportService.write(document, to: destination)
        return destination
    }
}

// MARK: - AnnotationEditingDelegate

extension DocumentSession: AnnotationEditingDelegate {

    var annotationUndoManager: UndoManager { undoManager }

    func annotationView(_ view: AnnotatingPDFView, didFinishLive annotation: PDFAnnotation, on page: PDFPage) {
        addAnnotations([annotation], on: page, actionName: "Freihand", alreadyPlaced: true)
    }

    func annotationView(_ view: AnnotatingPDFView, didCreate annotations: [PDFAnnotation], on page: PDFPage, actionName: String) {
        addAnnotations(annotations, on: page, actionName: actionName)
    }

    func annotationView(_ view: AnnotatingPDFView, didErase annotation: PDFAnnotation, on page: PDFPage) {
        removeAnnotations([annotation], on: page, actionName: "Loeschen")
    }

    func annotationView(_ view: AnnotatingPDFView, didRequestCommentAt point: CGPoint, on page: PDFPage) {
        requestComment(at: point, on: page)
    }
}
