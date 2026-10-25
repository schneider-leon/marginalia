//
//  DocumentSession.swift
//  marginalia
//
//  State of *one* open document. From step 5 on there is exactly one
//  session per tab.
//

import AppKit
import Foundation
import Observation
import PDFKit

// MARK: - Command Channel Towards PDFKit

/// Actions only the `PDFView` itself can perform (scrolling, zooming).
///
/// The session calls them imperatively instead of declaring them as state —
/// otherwise SwiftUI would want to write an update back on every scroll.
@MainActor
protocol PDFViewCommandTarget: AnyObject {
    func go(toPageIndex index: Int)
    func goToNextPage()
    func goToPreviousPage()
    func refreshDisplay()
    /// Takes back temporary rendering (eraser preview) so it does not get
    /// saved along.
    func endTransientPreviews()
}

// MARK: - Display Mode

enum PageDisplayMode: String, CaseIterable, Identifiable {
    case singlePage
    case singlePageContinuous
    case twoUpContinuous

    var id: String { rawValue }

    var label: String {
        switch self {
        case .singlePage: "Single Page"
        case .singlePageContinuous: "Continuous"
        case .twoUpContinuous: "Two Pages"
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

// MARK: - Errors

enum DocumentSessionError: LocalizedError {
    case unreadablePDF(URL)

    var errorDescription: String? {
        switch self {
        case .unreadablePDF(let url):
            "“\(url.lastPathComponent)” could not be read as a PDF."
        }
    }

    var recoverySuggestion: String? {
        "The file may be damaged, password-protected or not a PDF."
    }
}

/// What you are currently doing in a notebook.
enum NotebookMode: String, CaseIterable, Identifiable {
    case write
    case annotate

    var id: String { rawValue }

    var label: String {
        switch self {
        case .write: "Write"
        case .annotate: "Annotate"
        }
    }

    var symbol: String {
        switch self {
        case .write: "keyboard"
        case .annotate: "highlighter"
        }
    }
}

// MARK: - Session

@MainActor
@Observable
final class DocumentSession: Identifiable {
    let id = UUID()
    /// Every open document is a notebook package — an imported PDF too.
    /// That way there is no second path through the app.
    let notebook: NotebookPackage
    let document: PDFDocument

    /// The name from the library — it is authoritative there, and
    /// `info.json` gets it on the next save.
    var displayName: String

    /// Controlled by the user, mirrored to the `PDFView` in `updateNSView`.
    var displayMode: PageDisplayMode = .singlePageContinuous
    var activeTool: AnnotationTool = .select
    var style = AnnotationStyle()

    /// The page you are on — *one* value for both modes. Otherwise the
    /// other view would start at the front again when switching. Inserted
    /// images without further information land here too.
    private(set) var currentPageIndex = 0

    private(set) var hasUnsavedChanges = false

    /// Issues found while opening — such as repaired page descriptions.
    private(set) var loadWarnings: [String] = []

    /// Last failed save attempt. It is shown instead of being silently
    /// swallowed: a silently failing autosave would be the worst of all
    /// options.
    var saveError: String?

    @ObservationIgnored
    private var autosaveTask: Task<Void, Never>?

    /// Short enough that little gets lost, long enough that a file is not
    /// written on every keystroke.
    private static let autosaveDelay = Duration.seconds(3)

    // MARK: Notebook

    var notebookMode: NotebookMode = .write {
        didSet {
            guard notebookMode != oldValue else { return }
            // Switching modes anchors the image — it should not come back
            // with its handles still showing.
            selectedOverlayID = nil
            applyModeRendering()
        }
    }

    @ObservationIgnored
    let textEngine: NotebookTextEngine

    /// Most recently edited text view — the formatting commands need its
    /// selection.
    @ObservationIgnored
    weak var activeTextView: NSTextView?

    /// Mirror of the package's page list so SwiftUI sees page changes.
    private(set) var pageDescriptors: [PageDescriptor] = []

    var ruling: PageRuling = .none

    /// *One* zoom value for both modes. Previously the PDF view had its own
    /// and computed one by itself when opening — so the size jumped when
    /// switching.
    private(set) var zoom: CGFloat = 1

    /// Visible width of the document area — for "fit to window width".
    var viewportWidth: CGFloat = 0

    private static let zoomSteps: [CGFloat] = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 2, 3, 4]

    /// Counter so SwiftUI sees image changes; the package is not
    /// observable.
    private(set) var overlayRevision = 0

    var selectedOverlayID: UUID?

    @ObservationIgnored
    private var imageCache: [String: NSImage] = [:]

    @ObservationIgnored
    weak var commandTarget: (any PDFViewCommandTarget)?

    @ObservationIgnored
    let undoManager = UndoManager()

    /// Only there so SwiftUI re-evaluates the undo buttons — the
    /// UndoManager itself is not observable.
    private(set) var editRevision = 0

    var url: URL { notebook.url }

    var pageCount: Int { document.pageCount }

    /// Line below the window title — the same in both modes.
    var subtitle: String {
        let pages = "\(pageCount) \(pageCount == 1 ? "page" : "pages")"
        return hasUnsavedChanges ? "\(pages) — edited" : pages
    }
    var canGoToNextPage: Bool { currentPageIndex + 1 < pageCount }
    var canGoToPreviousPage: Bool { currentPageIndex > 0 }
    var canUndo: Bool { _ = editRevision; return undoManager.canUndo }
    var canRedo: Bool { _ = editRevision; return undoManager.canRedo }

    /// Older highlights carried the marked text as `contents`, and PDFKit
    /// shows a clickable note button next to any highlight with contents.
    /// A highlight should be just the marking.
    private static func stripHighlightPopups(in document: PDFDocument) {
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            for annotation in page.annotations where annotation.type == "Highlight" {
                annotation.contents = nil
                if let popup = annotation.popup {
                    page.removeAnnotation(popup)
                    annotation.popup = nil
                }
            }
        }
    }

    init(package: NotebookPackage, name: String) {
        self.notebook = package
        self.document = package.pdf
        self.displayName = name

        let engine = NotebookTextEngine(rtf: package.bodyRTF)
        engine.updateContainers(sizes: package.textAreaSizes())
        self.textEngine = engine

        undoManager.levelsOfUndo = 100
        // Text pages with burned-in text may be on disk; in writing mode the
        // text comes from the text view.
        package.clearWritablePages()
        Self.stripHighlightPopups(in: package.pdf)
        loadWarnings = package.loadWarnings
        package.pruneUnreferencedAssets()
        pageDescriptors = package.info.pages
        ruling = package.info.ruling
        engine.onEdited = { [weak self] in self?.textDidChange() }
    }

    /// Prepare the text pages when switching: burned in for the annotation
    /// view, empty for writing mode.
    /// In annotation mode the text lives in the pages. If the page count
    /// changes it reflows — and then it has to be burned in again.
    private func refreshBurnedTextIfNeeded() {
        guard notebookMode == .annotate else { return }
        notebook.burnTextIntoWritablePages(engine: textEngine)
    }

    private func applyModeRendering() {
        switch notebookMode {
        case .annotate:
            notebook.burnTextIntoWritablePages(engine: textEngine)
        case .write:
            notebook.clearWritablePages()
        }
        commandTarget?.refreshDisplay()
    }

    // MARK: Notebook Editing

    /// Match the containers to the pages and mirror the page list.
    private func syncNotebookState() {
        let package = notebook
        let engine = textEngine
        engine.updateContainers(sizes: package.textAreaSizes())
        pageDescriptors = package.info.pages
    }

    private func textDidChange() {
        hasUnsavedChanges = true
        editRevision &+= 1
        formattingRevision &+= 1
        scheduleAutosave()
        // Only add pages in the next pass: while the layout manager is still
        // busy with the change, its containers must not be pulled out from
        // under it.
        Task { @MainActor [weak self] in self?.growPagesIfNeeded() }
    }

    /// If the text runs past the last page, a page is added. The reverse is
    /// *not* done automatically — a page the user created does not
    /// disappear by itself.
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
        refreshBurnedTextIfNeeded()
        hasUnsavedChanges = true
        scheduleAutosave()
        commandTarget?.refreshDisplay()
    }

    func removePage(at index: Int) {
        guard notebook.info.pages.count > 1 else { return }
        let package = notebook
        package.removePage(at: index)
        syncNotebookState()
        refreshBurnedTextIfNeeded()
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

    // MARK: Images

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
        addOverlay(overlay, pageID: pageID, actionName: "Insert Image")
        selectedOverlayID = overlay.id
        return overlay.id
    }

    /// Keeps the aspect ratio and fits into half the page width — a
    /// screenshot should not stick out over the edge.
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

    func removeOverlay(id: UUID, pageID: UUID, actionName: String = "Remove Image") {
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

    /// While dragging: only set the value, no undo step per mouse movement.
    func previewOverlayFrame(id: UUID, frame: CGRect, atPageIndex index: Int) {
        let package = notebook
        guard let pageID = package.pageID(at: index) else { return }
        var list = package.overlays[pageID]
        guard let position = list.firstIndex(where: { $0.id == id }) else { return }
        list[position].frame = frame
        package.overlays[pageID] = list
        overlayRevision &+= 1
    }

    /// After releasing: one undo step for the entire movement.
    func commitOverlayFrame(id: UUID, from oldFrame: CGRect, to newFrame: CGRect, atPageIndex index: Int) {
        guard oldFrame != newFrame, notebook.pageID(at: index) != nil else { return }
        previewOverlayFrame(id: id, frame: newFrame, atPageIndex: index)
        undoManager.setActionName("Move Image")
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

    /// Counter so SwiftUI re-evaluates the state of the format buttons.
    /// Neither `typingAttributes` nor the selection are observable.
    private(set) var formattingRevision = 0

    /// The font a change would affect right now: with a selection that of
    /// the selected text, otherwise that of the next keystroke.
    private var currentFont: NSFont {
        let range = selectedTextRange
        if range.length > 0, range.location < textEngine.textStorage.length,
           let font = textEngine.textStorage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont {
            return font
        }
        if let font = activeTextView?.typingAttributes[.font] as? NSFont {
            return font
        }
        return NotebookTextEngine.defaultFont
    }

    var isBoldActive: Bool {
        _ = formattingRevision
        return NSFontManager.shared.traits(of: currentFont).contains(.boldFontMask)
    }

    var isItalicActive: Bool {
        _ = formattingRevision
        return NSFontManager.shared.traits(of: currentFont).contains(.italicFontMask)
    }

    var isUnderlineActive: Bool {
        _ = formattingRevision
        let range = selectedTextRange
        if range.length > 0, range.location < textEngine.textStorage.length {
            let value = textEngine.textStorage.attribute(
                .underlineStyle, at: range.location, effectiveRange: nil
            ) as? Int
            return (value ?? 0) != 0
        }
        return (activeTextView?.typingAttributes[.underlineStyle] as? Int ?? 0) != 0
    }

    var currentFontSize: CGFloat {
        _ = formattingRevision
        return currentFont.pointSize
    }

    /// The text view reports cursor and selection changes here.
    func reportSelectionChanged() {
        formattingRevision &+= 1
    }

    func toggleBold() {
        applyTrait(.boldFontMask)
    }

    func toggleItalic() {
        applyTrait(.italicFontMask)
    }

    /// Sets the alignment of the paragraph and of the next typed text —
    /// otherwise a newly started paragraph would fall back.
    func setAlignment(_ alignment: NSTextAlignment) {
        defer { formattingRevision &+= 1 }
        textEngine.setAlignment(alignment, in: selectedTextRange)

        guard let view = activeTextView else { return }
        var attributes = view.typingAttributes
        let style = ((attributes[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy()
            as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        style.alignment = alignment
        attributes[.paragraphStyle] = style
        view.typingAttributes = attributes
    }

    /// `natural` counts as left-aligned — that is how the user sees it too.
    var currentAlignment: NSTextAlignment {
        _ = formattingRevision
        let storage = textEngine.textStorage
        if storage.length > 0 {
            let location = min(max(selectedTextRange.location, 0), storage.length - 1)
            if let style = storage.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle,
               style.alignment != .natural {
                return style.alignment
            }
        }
        if let style = activeTextView?.typingAttributes[.paragraphStyle] as? NSParagraphStyle,
           style.alignment != .natural {
            return style.alignment
        }
        return .left
    }

    func toggleUnderline() {
        let range = selectedTextRange
        defer { formattingRevision &+= 1 }

        if range.length > 0 {
            textEngine.toggleUnderline(in: range)
            return
        }
        guard let view = activeTextView else { return }
        var attributes = view.typingAttributes
        if (attributes[.underlineStyle] as? Int ?? 0) == 0 {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        } else {
            attributes.removeValue(forKey: .underlineStyle)
        }
        view.typingAttributes = attributes
    }

    func setFontSize(_ size: CGFloat) {
        let range = selectedTextRange
        defer { formattingRevision &+= 1 }
        if range.length > 0 {
            textEngine.setFontSize(size, in: range)
        } else {
            changeTypingFont { NSFontManager.shared.convert($0, toSize: size) }
        }
    }

    /// With a selection the existing text is changed, without one whatever
    /// is typed next. Without the second case bold could only be applied
    /// afterwards, not switched on beforehand.
    private func applyTrait(_ trait: NSFontTraitMask) {
        let range = selectedTextRange
        defer { formattingRevision &+= 1 }
        if range.length > 0 {
            textEngine.toggleTrait(trait, in: range)
            return
        }
        changeTypingFont { font in
            let manager = NSFontManager.shared
            return manager.traits(of: font).contains(trait)
                ? manager.convert(font, toNotHaveTrait: trait)
                : manager.convert(font, toHaveTrait: trait)
        }
    }

    private func changeTypingFont(_ transform: (NSFont) -> NSFont) {
        guard let view = activeTextView else { return }
        var attributes = view.typingAttributes
        let font = (attributes[.font] as? NSFont) ?? NotebookTextEngine.defaultFont
        attributes[.font] = transform(font)
        view.typingAttributes = attributes
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

    // MARK: Autosave

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.autosaveDelay)
            guard !Task.isCancelled else { return }
            self?.saveQuietly()
        }
    }

    /// Saves if needed and reports a failure via `saveError`.
    /// - Returns: whether everything is on disk in the end.
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

    // MARK: Navigation & Zoom (SwiftUI/Menu -> PDFView)

    func go(toPageIndex index: Int) {
        guard index >= 0, index < pageCount else { return }
        commandTarget?.go(toPageIndex: index)
    }

    func goToNextPage() { commandTarget?.goToNextPage() }
    func goToPreviousPage() { commandTarget?.goToPreviousPage() }

    // MARK: Zoom

    /// Whether text is being typed — only decides about the tools now, no
    /// longer about zoom or appearance.
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

    // MARK: Feedback (PDFView -> SwiftUI)

    func reportPageIndex(_ index: Int) {
        setCurrentPage(index)
    }

    func setCurrentPage(_ index: Int) {
        let clamped = min(max(index, 0), max(pageCount - 1, 0))
        guard clamped != currentPageIndex else { return }
        currentPageIndex = clamped
    }

    /// The `PDFView` can also zoom by itself (trackpad). The value ends up in
    /// the shared zoom so the editor adopts it.
    func reportScale(_ scale: CGFloat) {
        setZoom(scale)
    }

    // MARK: Annotations

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
        // Only annotations live in content.pdf. Text and images are stored
        // next to it — they do not need the pages rewritten.
        notebook.markPDFDirty()
        hasUnsavedChanges = true
        editRevision &+= 1
        commandTarget?.refreshDisplay()
        scheduleAutosave()
    }

    // MARK: Sticky Notes

    func noteMoved(_ annotation: PDFAnnotation, on page: PDFPage, from oldBounds: CGRect) {
        let newBounds = annotation.bounds
        guard newBounds != oldBounds else { return }
        let actionName = switch annotation.type {
        case "FreeText": "Move Note"
        case "Ink": "Move Drawing"
        default: "Move Annotation"
        }
        undoManager.setActionName(actionName)
        undoManager.registerUndo(withTarget: self) { session in
            annotation.bounds = oldBounds
            session.noteMoved(annotation, on: page, from: newBounds)
        }
        didEdit()
    }

    func noteEdited(_ annotation: PDFAnnotation, on page: PDFPage, from oldText: String?) {
        let newText = annotation.contents
        guard newText != oldText else { return }
        undoManager.setActionName("Edit Note")
        undoManager.registerUndo(withTarget: self) { session in
            annotation.contents = oldText
            session.noteEdited(annotation, on: page, from: newText)
        }
        didEdit()
    }

    // MARK: Saving & Export

    /// The flattened version is exported: typed text, images and guide
    /// lines are part of the page afterwards.
    private func exportDocument() throws -> PDFDocument {
        commandTarget?.endTransientPreviews()
        notebook.setBodyRTF(textEngine.rtfData())
        return try NotebookRenderer.flattened(notebook, engine: textEngine)
    }

    func save() throws {
        commandTarget?.endTransientPreviews()
        notebook.setTitle(displayName)
        notebook.setBodyRTF(textEngine.rtfData())
        try notebook.write()
        DocumentThumbnails.shared.invalidate(id: notebook.info.id)
        hasUnsavedChanges = false
    }

    /// Writes a copy to a freely chosen location.
    /// - Returns: the destination, or `nil` if the user cancelled.
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
        addAnnotations([annotation], on: page, actionName: "Freehand", alreadyPlaced: true)
    }

    func annotationView(_ view: AnnotatingPDFView, didCreate annotations: [PDFAnnotation], on page: PDFPage, actionName: String) {
        addAnnotations(annotations, on: page, actionName: actionName)
    }

    func annotationView(_ view: AnnotatingPDFView, didErase annotation: PDFAnnotation, on page: PDFPage) {
        removeAnnotations([annotation], on: page, actionName: "Delete")
    }

    func annotationView(_ view: AnnotatingPDFView, didMove annotation: PDFAnnotation, on page: PDFPage, from oldBounds: CGRect) {
        noteMoved(annotation, on: page, from: oldBounds)
    }

    func annotationView(_ view: AnnotatingPDFView, didEditNote annotation: PDFAnnotation, on page: PDFPage, from oldText: String?) {
        noteEdited(annotation, on: page, from: oldText)
    }

    func annotationView(_ view: AnnotatingPDFView, imageAt point: CGPoint, on page: PDFPage) -> (id: UUID, frame: CGRect)? {
        let index = document.index(for: page)
        guard index != NSNotFound else { return nil }
        // Drawn in this order, so the last one is on top.
        guard let hit = imageOverlays(atPageIndex: index).last(where: { $0.frame.contains(point) }) else {
            return nil
        }
        return (hit.id, hit.frame)
    }

    func annotationView(_ view: AnnotatingPDFView, didEraseImage id: UUID, on page: PDFPage) {
        let index = document.index(for: page)
        guard index != NSNotFound, let pageID = notebook.pageID(at: index) else { return }
        removeOverlay(id: id, pageID: pageID, actionName: "Delete Image")
    }
}
