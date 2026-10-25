//
//  NotebookPackage.swift
//  marginalia
//
//  Reading and writing the `.marginalia` package.
//
//  Layout:
//      Notebook.marginalia/
//      ├── info.json       metadata + page order
//      ├── content.pdf     canonical page carrier
//      ├── overlays.json   editable text boxes and image placements
//      └── assets/         inserted original images
//
//  `content.pdf` is the truth about pages and geometry, `overlays.json` the
//  truth about everything that should stay editable.
//

import Foundation
import PDFKit

enum NotebookPackageError: LocalizedError {
    case notADirectory(URL)
    case missingComponent(String)
    case unreadablePDF
    case unsupportedSchema(found: Int, supported: Int)
    case pdfSerializationFailed

    var errorDescription: String? {
        switch self {
        case .notADirectory(let url):
            "“\(url.lastPathComponent)” is not a marginalia notebook."
        case .missingComponent(let name):
            "The notebook is missing “\(name)”."
        case .unreadablePDF:
            "The notebook's pages could not be read."
        case .unsupportedSchema(let found, let supported):
            "The notebook was created with a newer version (format \(found), supported is \(supported))."
        case .pdfSerializationFailed:
            "The notebook's pages could not be written."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .unsupportedSchema:
            "Update marginalia to open the notebook."
        default:
            "The package may be incomplete or damaged."
        }
    }
}

@MainActor
final class NotebookPackage {

    enum Component {
        static let info = "info.json"
        static let content = "content.pdf"
        static let overlays = "overlays.json"
        static let body = "body.rtf"
        static let assets = "assets"
    }

    private(set) var url: URL
    private(set) var info: NotebookInfo
    private(set) var pdf: PDFDocument
    var overlays: OverlayDocument

    /// The notebook's continuous text as RTF. `nil` means nothing has been
    /// typed yet.
    private(set) var bodyRTF: Data?

    /// Non-fatal issues found while reading — e.g. repaired page
    /// descriptors. For the error display in step 9.
    private(set) var loadWarnings: [String] = []

    /// Newly added images that have to end up in `assets/` on the next
    /// write.
    private var pendingAssets: [String: Data] = [:]

    /// `content.pdf` is only re-serialized when pages have changed — for
    /// large scripts that is the expensive part.
    private var pdfNeedsRewrite: Bool

    private init(
        url: URL,
        info: NotebookInfo,
        pdf: PDFDocument,
        overlays: OverlayDocument,
        bodyRTF: Data?,
        pdfNeedsRewrite: Bool
    ) {
        self.url = url
        self.info = info
        self.pdf = pdf
        self.overlays = overlays
        self.bodyRTF = bodyRTF
        self.pdfNeedsRewrite = pdfNeedsRewrite
    }

    /// Pages that are typed on — the text flows past imported PDF pages.
    var writablePageIndices: [Int] {
        info.pages.enumerated().compactMap { $0.element.kind == .blank ? $0.offset : nil }
    }

    /// Writing areas of the writable pages, in document order.
    func textAreaSizes() -> [CGSize] {
        writablePageIndices.map { index in
            let size = pdf.page(at: index)?.bounds(for: .cropBox).size ?? PDFPageFactory.a4
            return info.textInsets.textAreaSize(for: size)
        }
    }

    func pageID(at index: Int) -> UUID? {
        info.pages.indices.contains(index) ? info.pages[index].id : nil
    }

    func imageOverlays(atPageIndex index: Int) -> [Overlay] {
        guard let pageID = pageID(at: index) else { return [] }
        return overlays.sortedOverlays(for: pageID).filter {
            if case .image = $0.content { return true } else { return false }
        }
    }

    func setBodyRTF(_ data: Data?) {
        bodyRTF = data
    }

    func setRuling(_ ruling: PageRuling) {
        info.ruling = ruling
    }

    var title: String { info.title }
    var pageCount: Int { info.pages.count }

    // MARK: - Creating

    /// Creates a new notebook with one blank page and writes it right away.
    static func create(
        id: UUID = UUID(),
        title: String,
        size: CGSize = PDFPageFactory.a4,
        at directory: URL
    ) throws -> NotebookPackage {
        guard let pdf = PDFPageFactory.blankDocument(size: size) else {
            throw NotebookPackageError.pdfSerializationFailed
        }

        var info = NotebookInfo(id: id, title: title)
        info.pages = [PageDescriptor(kind: .blank)]

        let package = NotebookPackage(
            url: NotebookLibraryLocation.packageURL(for: info.id, in: directory),
            info: info,
            pdf: pdf,
            overlays: OverlayDocument(),
            bodyRTF: nil,
            pdfNeedsRewrite: true
        )
        try package.write()
        return package
    }

    /// Creates a notebook whose pages come from a PDF.
    ///
    /// That way an imported PDF is not a special case in the app but a
    /// notebook like any other — just without blank pages. Appending pages,
    /// writing and annotating then work exactly the same.
    static func create(
        id: UUID = UUID(),
        title: String,
        from document: PDFDocument,
        sourceName: String,
        at directory: URL
    ) throws -> NotebookPackage {
        guard document.pageCount > 0 else {
            throw NotebookPackageError.unreadablePDF
        }
        var info = NotebookInfo(id: id, title: title)
        info.pages = (0..<document.pageCount).map { _ in
            PageDescriptor(kind: .imported, source: sourceName)
        }

        let package = NotebookPackage(
            url: NotebookLibraryLocation.packageURL(for: id, in: directory),
            info: info,
            pdf: document,
            overlays: OverlayDocument(),
            bodyRTF: nil,
            pdfNeedsRewrite: true
        )
        try package.write()
        return package
    }

    // MARK: - Reading

    static func read(from url: URL) throws -> NotebookPackage {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw NotebookPackageError.notADirectory(url)
        }

        let infoURL = url.appending(path: Component.info)
        guard let infoData = try? Data(contentsOf: infoURL) else {
            throw NotebookPackageError.missingComponent(Component.info)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var info = try decoder.decode(NotebookInfo.self, from: infoData)

        guard info.schemaVersion <= NotebookInfo.currentSchemaVersion else {
            throw NotebookPackageError.unsupportedSchema(
                found: info.schemaVersion,
                supported: NotebookInfo.currentSchemaVersion
            )
        }

        let contentURL = url.appending(path: Component.content)
        guard FileManager.default.fileExists(atPath: contentURL.path) else {
            throw NotebookPackageError.missingComponent(Component.content)
        }
        guard let pdf = PDFDocument(url: contentURL) else {
            throw NotebookPackageError.unreadablePDF
        }

        // overlays.json may be missing — a notebook without overlays is valid.
        var overlays = OverlayDocument()
        if let overlayData = try? Data(contentsOf: url.appending(path: Component.overlays)) {
            overlays = (try? decoder.decode(OverlayDocument.self, from: overlayData)) ?? OverlayDocument()
        }

        var warnings: [String] = []
        repairPageDescriptors(&info, pdf: pdf, warnings: &warnings)
        dropOrphanOverlays(&overlays, info: info, warnings: &warnings)

        let package = NotebookPackage(
            url: url,
            info: info,
            pdf: pdf,
            overlays: overlays,
            bodyRTF: try? Data(contentsOf: url.appending(path: Component.body)),
            pdfNeedsRewrite: false
        )
        package.loadWarnings = warnings
        return package
    }

    /// `info.pages` and `content.pdf` have to match 1:1.
    ///
    /// On a mismatch we repair instead of aborting: an incomplete
    /// description is annoying, a notebook that can no longer be opened
    /// would be worse.
    private static func repairPageDescriptors(
        _ info: inout NotebookInfo,
        pdf: PDFDocument,
        warnings: inout [String]
    ) {
        let described = info.pages.count
        let actual = pdf.pageCount
        guard described != actual else { return }

        if described > actual {
            info.pages.removeLast(described - actual)
            warnings.append("Removed \(described - actual) page description(s) without a page.")
        } else {
            info.pages.append(contentsOf: (0..<(actual - described)).map { _ in
                PageDescriptor(kind: .imported)
            })
            warnings.append("Descriptions added for \(actual - described) page(s) that had none.")
        }
    }

    private static func dropOrphanOverlays(
        _ overlays: inout OverlayDocument,
        info: NotebookInfo,
        warnings: inout [String]
    ) {
        let known = Set(info.pages.map(\.id))
        let before = overlays.pages.count
        overlays.pages.removeAll { !known.contains($0.pageID) }
        if overlays.pages.count != before {
            warnings.append("Discarded \(before - overlays.pages.count) overlay group(s) without a matching page.")
        }
    }

    // MARK: - Writing

    func write() throws {
        try write(to: url)
    }

    func write(to destination: URL) throws {
        let fileManager = FileManager.default
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        info.modified = Date()

        // Write into a sibling folder first, then swap: an interruption
        // halfway through must not half-overwrite the existing package.
        let staging = fileManager.temporaryDirectory
            .appending(path: "marginalia-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        try encoder.encode(info).write(to: staging.appending(path: Component.info))
        try encoder.encode(overlays).write(to: staging.appending(path: Component.overlays))
        if let bodyRTF {
            try bodyRTF.write(to: staging.appending(path: Component.body))
        }

        let stagedContent = staging.appending(path: Component.content)
        let existingContent = url.appending(path: Component.content)
        if pdfNeedsRewrite || !fileManager.fileExists(atPath: existingContent.path) {
            guard let data = pdf.dataRepresentation() else {
                throw NotebookPackageError.pdfSerializationFailed
            }
            try data.write(to: stagedContent)
        } else {
            // Unchanged: hard-link instead of copying. For a 100 MB script
            // that is the difference between instant and noticeable.
            try Self.materialize(from: existingContent, to: stagedContent)
        }

        let stagedAssets = staging.appending(path: Component.assets, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: stagedAssets, withIntermediateDirectories: true)
        let existingAssets = url.appending(path: Component.assets, directoryHint: .isDirectory)
        if let names = try? fileManager.contentsOfDirectory(atPath: existingAssets.path) {
            for name in names where pendingAssets[name] == nil {
                try Self.materialize(
                    from: existingAssets.appending(path: name),
                    to: stagedAssets.appending(path: name)
                )
            }
        }
        for (name, data) in pendingAssets {
            try data.write(to: stagedAssets.appending(path: name))
        }

        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: staging)
        } else {
            try fileManager.moveItem(at: staging, to: destination)
        }

        url = destination
        pendingAssets.removeAll()
        pdfNeedsRewrite = false
    }

    /// Hard link where possible — otherwise copy. `linkItem` fails across
    /// volume boundaries, and a silently skipped asset would be data loss.
    private static func materialize(from source: URL, to destination: URL) throws {
        do {
            try FileManager.default.linkItem(at: source, to: destination)
        } catch {
            try FileManager.default.copyItem(at: source, to: destination)
        }
    }

    // MARK: - Changing

    func setTitle(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != info.title else { return }
        info.title = trimmed
    }

    /// Size of the last page, so inserted blank pages match the rest.
    var preferredPageSize: CGSize {
        guard let last = pdf.page(at: pdf.pageCount - 1) else { return PDFPageFactory.a4 }
        return last.bounds(for: .cropBox).size
    }

    @discardableResult
    func insertBlankPage(at index: Int? = nil, size: CGSize? = nil) throws -> PageDescriptor {
        guard let blank = PDFPageFactory.blankPage(size: size ?? preferredPageSize) else {
            throw NotebookPackageError.pdfSerializationFailed
        }
        let position = min(max(index ?? info.pages.count, 0), info.pages.count)
        pdf.insert(blank.page, at: position)
        withExtendedLifetime(blank.owner) {}

        let descriptor = PageDescriptor(kind: .blank)
        info.pages.insert(descriptor, at: position)
        pdfNeedsRewrite = true
        return descriptor
    }

    @discardableResult
    func appendPages(fromPDFAt source: URL) throws -> [PageDescriptor] {
        guard let imported = PDFDocument(url: source) else {
            throw NotebookPackageError.unreadablePDF
        }
        let name = source.lastPathComponent
        var descriptors: [PageDescriptor] = []

        for index in 0..<imported.pageCount {
            guard let page = imported.page(at: index)?.copy() as? PDFPage else { continue }
            pdf.insert(page, at: pdf.pageCount)
            let descriptor = PageDescriptor(kind: .imported, source: name)
            info.pages.append(descriptor)
            descriptors.append(descriptor)
        }

        pdfNeedsRewrite = true
        return descriptors
    }

    func removePage(at index: Int) {
        guard info.pages.indices.contains(index), index < pdf.pageCount else { return }
        let descriptor = info.pages[index]
        pdf.removePage(at: index)
        info.pages.remove(at: index)
        overlays[descriptor.id] = []
        pdfNeedsRewrite = true
    }

    // MARK: - Text Pages for the Annotation View
    //
    // The typed text lives in `body.rtf`, not in `content.pdf`. The
    // annotation view, however, shows `content.pdf` — the text pages would
    // be empty there. So when switching to annotation mode, the text is
    // burned into the pages, and removed again when switching back.
    // Annotations move along.

    /// Swaps a page and takes its annotations along.
    private func replacePage(at index: Int, with page: PDFPage, owner: PDFDocument) {
        guard let old = pdf.page(at: index) else { return }
        let annotations = old.annotations
        annotations.forEach(old.removeAnnotation)

        pdf.removePage(at: index)
        pdf.insert(page, at: index)
        withExtendedLifetime(owner) {}

        annotations.forEach(page.addAnnotation)
        pdfNeedsRewrite = true
    }

    func burnTextIntoWritablePages(engine: NotebookTextEngine) {
        for (containerIndex, pageIndex) in writablePageIndices.enumerated() {
            let size = pdf.page(at: pageIndex)?.bounds(for: .cropBox).size ?? PDFPageFactory.a4
            guard let rendered = NotebookRenderer.textPage(
                size: size,
                containerIndex: containerIndex,
                engine: engine,
                insets: info.textInsets,
                ruling: info.ruling
            ) else { continue }
            replacePage(at: pageIndex, with: rendered.page, owner: rendered.owner)
        }
    }

    /// Resets the writable pages to blank paper.
    ///
    /// Needed on open too: if a version with burned-in text is still on
    /// disk, writing mode would show it twice — once from the page, once
    /// from the text view.
    func clearWritablePages() {
        for pageIndex in writablePageIndices {
            let size = pdf.page(at: pageIndex)?.bounds(for: .cropBox).size ?? PDFPageFactory.a4
            guard let blank = PDFPageFactory.blankPage(size: size) else { continue }
            replacePage(at: pageIndex, with: blank.page, owner: blank.owner)
        }
    }

    /// Reports that the annotations in `content.pdf` have changed.
    func markPDFDirty() {
        pdfNeedsRewrite = true
    }

    // MARK: - Assets

    @discardableResult
    func addAsset(data: Data, fileExtension: String) -> String {
        let name = "\(UUID().uuidString).\(fileExtension)"
        pendingAssets[name] = data
        return name
    }

    func assetData(named name: String) -> Data? {
        if let pending = pendingAssets[name] { return pending }
        return try? Data(contentsOf: url.appending(path: Component.assets).appending(path: name))
    }

    /// Deletes image files no overlay points to anymore.
    ///
    /// Deliberately only called on open, not on every save: during a session
    /// an undo can bring back a deleted image, and then the file still has
    /// to be there. On open the undo stack is empty.
    @discardableResult
    func pruneUnreferencedAssets() -> [String] {
        let names = unreferencedAssetNames()
        let directory = url.appending(path: Component.assets)
        for name in names {
            try? FileManager.default.removeItem(at: directory.appending(path: name))
            pendingAssets.removeValue(forKey: name)
        }
        return names
    }

    /// Images no overlay points to anymore.
    func unreferencedAssetNames() -> [String] {
        var referenced: Set<String> = []
        for page in overlays.pages {
            for overlay in page.overlays {
                if case .image(let content) = overlay.content {
                    referenced.insert(content.assetName)
                }
            }
        }
        let onDisk = (try? FileManager.default.contentsOfDirectory(
            atPath: url.appending(path: Component.assets).path
        )) ?? []
        return (onDisk + Array(pendingAssets.keys)).filter { !referenced.contains($0) }
    }
}
