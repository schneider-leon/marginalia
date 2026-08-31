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

/// Womit man in einem Notizbuch gerade arbeitet.
enum NotebookMode: String, CaseIterable, Identifiable {
    case write
    case annotate

    var id: String { rawValue }

    var label: String {
        switch self {
        case .write: "Schreiben"
        case .annotate: "Annotieren"
        }
    }

    var symbol: String {
        switch self {
        case .write: "keyboard"
        case .annotate: "highlighter"
        }
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
    /// Jedes offene Dokument ist ein Notizbuchpaket — auch eine importierte
    /// PDF. Dadurch gibt es keinen zweiten Weg durch die App.
    let notebook: NotebookPackage
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

    private(set) var hasUnsavedChanges = false
    var pendingComment: PendingComment?

    /// Auffaelligkeiten beim Oeffnen — etwa reparierte Seitenbeschreibungen.
    private(set) var loadWarnings: [String] = []

    /// Letzter fehlgeschlagener Sicherungsversuch. Wird angezeigt, statt
    /// still verschluckt zu werden: eine stumm scheiternde Autosicherung
    /// waere die schlechteste aller Varianten.
    var saveError: String?

    @ObservationIgnored
    private var autosaveTask: Task<Void, Never>?

    /// Kurz genug, dass wenig verlorengeht, lang genug, dass nicht bei jedem
    /// Tastendruck eine Datei geschrieben wird.
    private static let autosaveDelay = Duration.seconds(3)

    // MARK: Notizbuch

    var notebookMode: NotebookMode = .write

    @ObservationIgnored
    let textEngine: NotebookTextEngine

    /// Zuletzt bearbeitete Textansicht — die Formatierbefehle brauchen deren
    /// Auswahl.
    @ObservationIgnored
    weak var activeTextView: NSTextView?

    /// Spiegel der Seitenliste des Pakets, damit SwiftUI Seitenaenderungen sieht.
    private(set) var pageDescriptors: [PageDescriptor] = []

    var ruling: PageRuling = .none

    /// Seite, auf der zuletzt gearbeitet wurde — dorthin landen eingefuegte
    /// Bilder ohne weitere Angabe.
    var activePageIndex = 0

    /// *Ein* Zoomwert fuer beide Modi. Vorher hatte die PDF-Ansicht einen
    /// eigenen und rechnete sich beim Oeffnen selbst einen aus — dadurch
    /// sprang die Groesse beim Umschalten.
    private(set) var zoom: CGFloat = 1

    /// Sichtbare Breite des Dokumentbereichs — fuer „auf Fensterbreite anpassen“.
    var viewportWidth: CGFloat = 0

    private static let zoomSteps: [CGFloat] = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 2, 3, 4]

    /// Zaehler, damit SwiftUI Bildaenderungen sieht; das Paket ist nicht
    /// observierbar.
    private(set) var overlayRevision = 0

    var selectedOverlayID: UUID?

    @ObservationIgnored
    private var imageCache: [String: NSImage] = [:]

    @ObservationIgnored
    weak var commandTarget: (any PDFViewCommandTarget)?

    @ObservationIgnored
    let undoManager = UndoManager()

    /// Nur da, damit SwiftUI die Undo-Buttons neu bewertet — der UndoManager
    /// selbst ist nicht observierbar.
    private(set) var editRevision = 0

    var url: URL { notebook.url }

    var pageCount: Int { document.pageCount }
    var canGoToNextPage: Bool { currentPageIndex + 1 < pageCount }
    var canGoToPreviousPage: Bool { currentPageIndex > 0 }
    var canUndo: Bool { _ = editRevision; return undoManager.canUndo }
    var canRedo: Bool { _ = editRevision; return undoManager.canRedo }

    init(package: NotebookPackage, name: String) {
        self.notebook = package
        self.document = package.pdf
        self.displayName = name

        let engine = NotebookTextEngine(rtf: package.bodyRTF)
        engine.updateContainers(sizes: package.textAreaSizes())
        self.textEngine = engine

        undoManager.levelsOfUndo = 100
        loadWarnings = package.loadWarnings
        package.pruneUnreferencedAssets()
        pageDescriptors = package.info.pages
        ruling = package.info.ruling
        engine.onEdited = { [weak self] in self?.textDidChange() }
    }

    // MARK: Notizbuch-Bearbeitung

    /// Container an die Seiten angleichen und die Seitenliste spiegeln.
    private func syncNotebookState() {
        let package = notebook
        let engine = textEngine
        engine.updateContainers(sizes: package.textAreaSizes())
        pageDescriptors = package.info.pages
    }

    private func textDidChange() {
        hasUnsavedChanges = true
        editRevision &+= 1
        scheduleAutosave()
        // Seiten erst im naechsten Durchlauf nachziehen: waehrend der
        // Layout-Manager noch mit der Aenderung beschaeftigt ist, darf man
        // ihm keine Container unter den Fuessen wegziehen.
        Task { @MainActor [weak self] in self?.growPagesIfNeeded() }
    }

    /// Laeuft der Text hinter die letzte Seite, kommt eine dazu. Umgekehrt
    /// wird *nicht* automatisch geloescht — eine Seite, die der Nutzer
    /// angelegt hat, verschwindet nicht von selbst.
    func growPagesIfNeeded() {
        let package = notebook
        let engine = textEngine
        var added = 0
        while engine.overflows, added < 200 {
            guard (try? package.insertBlankPage()) != nil else { break }
            engine.updateContainers(sizes: package.textAreaSizes())
            added += 1
        }
        if added > 0 {
            pageDescriptors = package.info.pages
            hasUnsavedChanges = true
            scheduleAutosave()
        }
    }

    func insertBlankPage(after index: Int? = nil) {
        let package = notebook
        let position = index.map { $0 + 1 } ?? package.info.pages.count
        try? package.insertBlankPage(at: position)
        syncNotebookState()
        hasUnsavedChanges = true
        scheduleAutosave()
        commandTarget?.refreshDisplay()
    }

    func removePage(at index: Int) {
        guard notebook.info.pages.count > 1 else { return }
        let package = notebook
        package.removePage(at: index)
        syncNotebookState()
        hasUnsavedChanges = true
        scheduleAutosave()
        commandTarget?.refreshDisplay()
    }

    func setRuling(_ value: PageRuling) {
        guard value != ruling else { return }
        let package = notebook
        ruling = value
        package.setRuling(value)
        hasUnsavedChanges = true
        scheduleAutosave()
    }

    // MARK: Bilder

    func image(forAsset name: String) -> NSImage? {
        if let cached = imageCache[name] { return cached }
        guard let data = notebook.assetData(named: name), let image = NSImage(data: data) else {
            return nil
        }
        imageCache[name] = image
        return image
    }

    func imageOverlays(atPageIndex index: Int) -> [Overlay] {
        notebook.imageOverlays(atPageIndex: index)
    }

    @discardableResult
    func insertImage(from url: URL, atPageIndex index: Int) throws -> UUID? {
        let access = SecurityScopedAccess(url: url)
        defer { access.release() }
        let data = try Data(contentsOf: url)
        let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension.lowercased()
        return insertImage(data: data, fileExtension: ext, atPageIndex: index)
    }

    @discardableResult
    func insertImage(data: Data, fileExtension: String, atPageIndex index: Int) -> UUID? {
        let package = notebook
        guard let pageID = package.pageID(at: index),
              let image = NSImage(data: data),
              image.size.width > 0, image.size.height > 0
        else { return nil }

        let name = package.addAsset(data: data, fileExtension: fileExtension)
        imageCache[name] = image

        let pageSize = document.page(at: index)?.bounds(for: .cropBox).size ?? PDFPageFactory.a4
        let overlay = Overlay(
            frame: Self.initialFrame(for: image.size, on: pageSize),
            zIndex: (package.overlays[pageID].map(\.zIndex).max() ?? 0) + 1,
            content: .image(ImageOverlayContent(assetName: name))
        )
        addOverlay(overlay, pageID: pageID, actionName: "Bild einfuegen")
        selectedOverlayID = overlay.id
        return overlay.id
    }

    /// Haelt das Seitenverhaeltnis und passt in die halbe Seitenbreite —
    /// eine Bildschirmaufnahme soll nicht ueber den Rand hinausragen.
    private static func initialFrame(for imageSize: CGSize, on pageSize: CGSize) -> CGRect {
        let maxWidth = pageSize.width * 0.5
        let maxHeight = pageSize.height * 0.5
        let scale = min(maxWidth / imageSize.width, maxHeight / imageSize.height, 1)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (pageSize.width - size.width) / 2,
            y: (pageSize.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    func addOverlay(_ overlay: Overlay, pageID: UUID, actionName: String) {
        let package = notebook
        package.overlays[pageID] = package.overlays[pageID] + [overlay]
        undoManager.setActionName(actionName)
        undoManager.registerUndo(withTarget: self) { session in
            session.removeOverlay(id: overlay.id, pageID: pageID, actionName: actionName)
        }
        overlayDidChange()
    }

    func removeOverlay(id: UUID, pageID: UUID, actionName: String = "Bild entfernen") {
        let package = notebook
        guard let existing = package.overlays[pageID].first(where: { $0.id == id }) else { return }
        package.overlays[pageID] = package.overlays[pageID].filter { $0.id != id }
        undoManager.setActionName(actionName)
        undoManager.registerUndo(withTarget: self) { session in
            session.addOverlay(existing, pageID: pageID, actionName: actionName)
        }
        if selectedOverlayID == id { selectedOverlayID = nil }
        overlayDidChange()
    }

    func removeSelectedOverlay(atPageIndex index: Int) {
        guard let id = selectedOverlayID, let pageID = notebook.pageID(at: index) else { return }
        removeOverlay(id: id, pageID: pageID)
    }

    /// Waehrend des Ziehens: nur setzen, kein Undo-Schritt pro Mausbewegung.
    func previewOverlayFrame(id: UUID, frame: CGRect, atPageIndex index: Int) {
        let package = notebook
        guard let pageID = package.pageID(at: index) else { return }
        var list = package.overlays[pageID]
        guard let position = list.firstIndex(where: { $0.id == id }) else { return }
        list[position].frame = frame
        package.overlays[pageID] = list
        overlayRevision &+= 1
    }

    /// Nach dem Loslassen: ein Undo-Schritt fuer die gesamte Bewegung.
    func commitOverlayFrame(id: UUID, from oldFrame: CGRect, to newFrame: CGRect, atPageIndex index: Int) {
        guard oldFrame != newFrame, notebook.pageID(at: index) != nil else { return }
        previewOverlayFrame(id: id, frame: newFrame, atPageIndex: index)
        undoManager.setActionName("Bild bewegen")
        undoManager.registerUndo(withTarget: self) { session in
            session.commitOverlayFrame(id: id, from: newFrame, to: oldFrame, atPageIndex: index)
        }
        overlayDidChange()
    }

    private func overlayDidChange() {
        overlayRevision &+= 1
        hasUnsavedChanges = true
        editRevision &+= 1
        scheduleAutosave()
    }

    var selectedTextRange: NSRange {
        activeTextView?.selectedRange() ?? NSRange(location: 0, length: 0)
    }

    func toggleBold() {
        textEngine.toggleTrait(.boldFontMask, in: selectedTextRange)
    }

    func toggleItalic() {
        textEngine.toggleTrait(.italicFontMask, in: selectedTextRange)
    }

    func setFontSize(_ size: CGFloat) {
        textEngine.setFontSize(size, in: selectedTextRange)
    }

    func close() {
        autosaveTask?.cancel()
        autosaveTask = nil
        commandTarget = nil
        undoManager.removeAllActions()
    }

    func dismissLoadWarnings() {
        loadWarnings = []
    }

    // MARK: Automatisches Sichern

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.autosaveDelay)
            guard !Task.isCancelled else { return }
            self?.saveQuietly()
        }
    }

    /// Sichert, wenn noetig, und meldet einen Fehlschlag ueber `saveError`.
    /// - Returns: ob am Ende alles auf der Platte steht.
    @discardableResult
    func saveQuietly() -> Bool {
        guard hasUnsavedChanges else { return true }
        do {
            try save()
            saveError = nil
            return true
        } catch {
            let localized = error as? LocalizedError
            saveError = localized?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    // MARK: Navigation & Zoom (SwiftUI/Menue -> PDFView)

    func go(toPageIndex index: Int) {
        guard index >= 0, index < pageCount else { return }
        commandTarget?.go(toPageIndex: index)
    }

    func goToNextPage() { commandTarget?.goToNextPage() }
    func goToPreviousPage() { commandTarget?.goToPreviousPage() }

    // MARK: Zoom

    /// Ob gerade getippt wird — entscheidet nur noch ueber die Werkzeuge,
    /// nicht mehr ueber Zoom oder Aussehen.
    var isTextEditing: Bool { notebookMode == .write }

    var currentScale: CGFloat { zoom }
    var canZoomIn: Bool { zoom < (Self.zoomSteps.last ?? 1) - 0.001 }
    var canZoomOut: Bool { zoom > (Self.zoomSteps.first ?? 1) + 0.001 }

    func zoomIn() {
        if let next = Self.zoomSteps.first(where: { $0 > zoom + 0.001 }) { setZoom(next) }
    }

    func zoomOut() {
        if let previous = Self.zoomSteps.last(where: { $0 < zoom - 0.001 }) { setZoom(previous) }
    }

    func fitToWindow() {
        let pageWidth = document.page(at: currentPageIndex)?.bounds(for: .cropBox).width
            ?? PDFPageFactory.a4.width
        guard viewportWidth > 0, pageWidth > 0 else { return setZoom(1) }
        setZoom((viewportWidth - DocumentAppearance.pageGap * 2) / pageWidth)
    }

    func setZoom(_ value: CGFloat) {
        let clamped = min(max(value, Self.zoomSteps.first ?? 0.25), Self.zoomSteps.last ?? 4)
        guard abs(clamped - zoom) > 0.0001 else { return }
        zoom = clamped
    }

    // MARK: Rueckmeldungen (PDFView -> SwiftUI)

    func reportPageIndex(_ index: Int) {
        guard index != currentPageIndex else { return }
        currentPageIndex = index
    }

    /// Die `PDFView` kann auch selbst zoomen (Trackpad). Der Wert landet im
    /// gemeinsamen Zoom, damit der Editor ihn uebernimmt.
    func reportScale(_ scale: CGFloat) {
        setZoom(scale)
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
        // Nur Annotationen stecken in content.pdf. Text und Bilder liegen
        // daneben — die brauchen kein Neuschreiben der Seiten.
        notebook.markPDFDirty()
        hasUnsavedChanges = true
        editRevision &+= 1
        commandTarget?.refreshDisplay()
        scheduleAutosave()
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

    /// Exportiert wird die flachgerechnete Fassung: getippter Text, Bilder
    /// und Hilfslinien stecken danach in der Seite.
    private func exportDocument() throws -> PDFDocument {
        notebook.setBodyRTF(textEngine.rtfData())
        return try NotebookRenderer.flattened(notebook, engine: textEngine)
    }

    func save() throws {
        notebook.setTitle(displayName)
        notebook.setBodyRTF(textEngine.rtfData())
        try notebook.write()
        hasUnsavedChanges = false
    }

    /// Schreibt eine Kopie an einen frei gewaehlten Ort.
    /// - Returns: das Ziel, oder `nil` wenn der Nutzer abgebrochen hat.
    @discardableResult
    func exportCopy() throws -> URL? {
        guard let destination = PDFExportService.chooseExportURL(suggestedName: displayName) else {
            return nil
        }
        try PDFExportService.write(try exportDocument(), to: destination)
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
