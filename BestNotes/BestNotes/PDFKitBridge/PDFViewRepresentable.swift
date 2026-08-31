//
//  PDFViewRepresentable.swift
//  BestNotes
//
//  Duenne Bruecke zwischen SwiftUI und PDFKit.
//
//  Regeln, die hier gelten:
//  1. `makeNSView` baut die `PDFView` einmal auf.
//  2. `updateNSView` gleicht nur wenige, explizit uebergebene Werte ab —
//     nie das ganze Dokument, solange es dasselbe ist.
//  3. Alles Imperative (scrollen, zoomen) laeuft ueber den Coordinator als
//     `PDFViewCommandTarget`, nicht ueber Zustandsdiffs.
//

import PDFKit
import SwiftUI

struct PDFViewRepresentable: NSViewRepresentable {
    let session: DocumentSession

    /// Bewusst eigene Parameter statt Zugriff ueber `session`: so haengt das
    /// SwiftUI-Update sichtbar an genau diesen Werten.
    let displayMode: PageDisplayMode
    let activeTool: AnnotationTool
    let style: AnnotationStyle

    func makeNSView(context: Context) -> AnnotatingPDFView {
        let view = AnnotatingPDFView()
        view.document = session.document
        view.editingDelegate = session
        view.activeTool = activeTool
        view.style = style
        view.displayMode = displayMode.pdfDisplayMode
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.pageShadowsEnabled = true
        view.backgroundColor = .documentBackground
        view.autoScales = true
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: AnnotatingPDFView, context: Context) {
        if nsView.document !== session.document {
            nsView.document = session.document
            nsView.autoScales = true
        }
        if nsView.displayMode != displayMode.pdfDisplayMode {
            nsView.displayMode = displayMode.pdfDisplayMode
        }
        if nsView.activeTool != activeTool {
            nsView.activeTool = activeTool
        }
        nsView.style = style
    }

    static func dismantleNSView(_ nsView: AnnotatingPDFView, coordinator: Coordinator) {
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, PDFViewCommandTarget {
        private let session: DocumentSession
        private weak var pdfView: AnnotatingPDFView?

        init(session: DocumentSession) {
            self.session = session
        }

        func attach(to view: AnnotatingPDFView) {
            pdfView = view
            session.commandTarget = self

            let center = NotificationCenter.default
            center.addObserver(
                self,
                selector: #selector(pageChanged),
                name: .PDFViewPageChanged,
                object: view
            )
            center.addObserver(
                self,
                selector: #selector(scaleChanged),
                name: .PDFViewScaleChanged,
                object: view
            )

            // Nach dem ersten Layout steht der Auto-Zoom-Faktor erst fest.
            DispatchQueue.main.async { [weak self] in
                self?.syncStateToSession()
            }
        }

        func detach() {
            NotificationCenter.default.removeObserver(self)
            if session.commandTarget === self {
                session.commandTarget = nil
            }
            pdfView = nil
        }

        // MARK: PDFView -> Session

        @objc private func pageChanged(_ notification: Notification) {
            syncStateToSession()
        }

        @objc private func scaleChanged(_ notification: Notification) {
            syncStateToSession()
        }

        private func syncStateToSession() {
            guard let pdfView, let document = pdfView.document else { return }
            if let page = pdfView.currentPage {
                let index = document.index(for: page)
                if index != NSNotFound { session.reportPageIndex(index) }
            }
            session.reportScale(
                pdfView.scaleFactor,
                min: pdfView.minScaleFactor,
                max: pdfView.maxScaleFactor
            )
        }

        // MARK: Session -> PDFView

        func go(toPageIndex index: Int) {
            guard let pdfView, let page = pdfView.document?.page(at: index) else { return }
            pdfView.go(to: page)
        }

        func goToNextPage() {
            guard let pdfView, pdfView.canGoToNextPage else { return }
            pdfView.goToNextPage(nil)
        }

        func goToPreviousPage() {
            guard let pdfView, pdfView.canGoToPreviousPage else { return }
            pdfView.goToPreviousPage(nil)
        }

        func zoomIn() {
            guard let pdfView, pdfView.canZoomIn else { return }
            pdfView.autoScales = false
            pdfView.zoomIn(nil)
            syncStateToSession()
        }

        func zoomOut() {
            guard let pdfView, pdfView.canZoomOut else { return }
            pdfView.autoScales = false
            pdfView.zoomOut(nil)
            syncStateToSession()
        }

        func fitToWindow() {
            guard let pdfView else { return }
            pdfView.autoScales = true
            syncStateToSession()
        }

        /// Nach Undo/Redo hat sich der Annotationsbestand geaendert, ohne dass
        /// PDFKit davon etwas mitbekommen haette.
        func refreshDisplay() {
            pdfView?.needsDisplay = true
        }
    }
}
