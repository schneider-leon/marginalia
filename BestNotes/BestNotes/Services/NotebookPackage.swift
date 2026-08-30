//
//  NotebookPackage.swift
//  BestNotes
//
//  Lesen und Schreiben des `.bestnote`-Pakets.
//
//  Aufbau:
//      Notizbuch.bestnote/
//      ├── info.json       Metadaten + Seitenreihenfolge
//      ├── content.pdf     kanonischer Seitentraeger
//      ├── overlays.json   editierbare Textboxen und Bildplatzierungen
//      └── assets/         eingefuegte Originalbilder
//
//  `content.pdf` ist die Wahrheit ueber Seiten und Geometrie, `overlays.json`
//  die Wahrheit ueber alles, was editierbar bleiben soll.
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
            "„\(url.lastPathComponent)“ ist kein BestNotes-Notizbuch."
        case .missingComponent(let name):
            "Im Notizbuch fehlt „\(name)“."
        case .unreadablePDF:
            "Die Seiten des Notizbuchs konnten nicht gelesen werden."
        case .unsupportedSchema(let found, let supported):
            "Das Notizbuch wurde mit einer neueren Version angelegt (Format \(found), unterstuetzt wird \(supported))."
        case .pdfSerializationFailed:
            "Die Seiten des Notizbuchs konnten nicht geschrieben werden."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .unsupportedSchema:
            "Aktualisiere BestNotes, um das Notizbuch zu oeffnen."
        default:
            "Das Paket ist moeglicherweise unvollstaendig oder beschaedigt."
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

    /// Der durchlaufende Text des Notizbuchs als RTF. `nil` heisst: noch nie
    /// getippt.
    private(set) var bodyRTF: Data?

    /// Nicht-fatale Auffaelligkeiten beim Lesen — z. B. reparierte
    /// Seitenbeschreibungen. Fuer die Fehleranzeige in Schritt 9.
    private(set) var loadWarnings: [String] = []

    /// Neu hinzugekommene Bilder, die beim naechsten Schreiben in `assets/`
    /// landen muessen.
    private var pendingAssets: [String: Data] = [:]

    /// `content.pdf` wird nur neu serialisiert, wenn sich Seiten geaendert
    /// haben — bei grossen Skripten ist das der teure Teil.
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

    /// Seiten, auf denen getippt wird — der Text fliesst an importierten
    /// PDF-Seiten vorbei.
    var writablePageIndices: [Int] {
        info.pages.enumerated().compactMap { $0.element.kind == .blank ? $0.offset : nil }
    }

    /// Schreibflaechen der beschreibbaren Seiten, in Dokumentreihenfolge.
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

    // MARK: - Anlegen

    /// Legt ein neues Notizbuch mit einer leeren Seite an und schreibt es sofort.
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

    // MARK: - Lesen

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

        // overlays.json darf fehlen — ein Notizbuch ohne Overlays ist gueltig.
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

    /// `info.pages` und `content.pdf` muessen 1:1 zueinander passen.
    ///
    /// Bei Abweichung wird repariert statt abgebrochen: eine unvollstaendige
    /// Beschreibung ist aergerlich, ein nicht mehr zu oeffnendes Notizbuch
    /// waere schlimmer.
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
            warnings.append("\(described - actual) Seitenbeschreibung(en) ohne Seite entfernt.")
        } else {
            info.pages.append(contentsOf: (0..<(actual - described)).map { _ in
                PageDescriptor(kind: .imported)
            })
            warnings.append("\(actual - described) Seite(n) ohne Beschreibung ergaenzt.")
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
            warnings.append("\(before - overlays.pages.count) Overlay-Gruppe(n) ohne zugehoerige Seite verworfen.")
        }
    }

    // MARK: - Schreiben

    func write() throws {
        try write(to: url)
    }

    func write(to destination: URL) throws {
        let fileManager = FileManager.default
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        info.modified = Date()

        // Erst in einen Nachbarordner schreiben, dann tauschen: ein Abbruch
        // mittendrin darf das vorhandene Paket nicht halb ueberschreiben.
        let staging = fileManager.temporaryDirectory
            .appending(path: "BestNotes-\(UUID().uuidString)", directoryHint: .isDirectory)
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
            // Unveraendert: hart verlinken statt kopieren. Bei einem
            // 100-MB-Skript ist das der Unterschied zwischen sofort und spuerbar.
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

    /// Hardlink, wo moeglich — sonst kopieren. Ueber Volumegrenzen hinweg
    /// scheitert `linkItem`, und ein stillschweigend uebersprungenes Asset
    /// waere Datenverlust.
    private static func materialize(from source: URL, to destination: URL) throws {
        do {
            try FileManager.default.linkItem(at: source, to: destination)
        } catch {
            try FileManager.default.copyItem(at: source, to: destination)
        }
    }

    // MARK: - Aendern

    func setTitle(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != info.title else { return }
        info.title = trimmed
    }

    /// Groesse der letzten Seite, damit eingefuegte Leerseiten zum Rest passen.
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

    /// Meldet, dass sich die Annotationen in `content.pdf` geaendert haben.
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

    /// Bilder, auf die kein Overlay mehr zeigt — Aufraeumkandidaten fuer Schritt 9.
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
