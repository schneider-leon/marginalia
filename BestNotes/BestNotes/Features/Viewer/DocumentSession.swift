//
//  DocumentSession.swift
//  BestNotes
//
//  Zustand *eines* geoeffneten Dokuments. Ab Schritt 5 existiert pro Tab
//  genau eine Session.
//

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

// MARK: - Session

@MainActor
@Observable
final class DocumentSession: Identifiable {
    let id = UUID()
    let url: URL
    let document: PDFDocument

    /// Vom Nutzer steuerbar, wird in `updateNSView` an die `PDFView` gespiegelt.
    var displayMode: PageDisplayMode = .singlePageContinuous

    /// Aus der `PDFView` zurueckgespiegelt — nur der Coordinator schreibt hier.
    private(set) var currentPageIndex = 0
    private(set) var scaleFactor: CGFloat = 1
    private(set) var minScaleFactor: CGFloat = 0.25
    private(set) var maxScaleFactor: CGFloat = 5

    @ObservationIgnored
    weak var commandTarget: (any PDFViewCommandTarget)?

    @ObservationIgnored
    private let access: SecurityScopedAccess

    var displayName: String { url.deletingPathExtension().lastPathComponent }
    var pageCount: Int { document.pageCount }
    var canGoToNextPage: Bool { currentPageIndex + 1 < pageCount }
    var canGoToPreviousPage: Bool { currentPageIndex > 0 }

    init(url: URL) throws {
        let access = SecurityScopedAccess(url: url)
        guard let document = PDFDocument(url: url) else {
            access.release()
            throw DocumentSessionError.unreadablePDF(url)
        }
        self.url = url
        self.document = document
        self.access = access
    }

    func close() {
        commandTarget = nil
        access.release()
    }

    // MARK: Kommandos (SwiftUI/Menue -> PDFView)

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
}
