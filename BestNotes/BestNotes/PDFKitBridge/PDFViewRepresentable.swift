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
    let zoom: CGFloat

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
        // Dieselbe Farbe wie hinter dem Editor; der Seitenabstand ebenso.
        view.backgroundColor = .documentBackground
        view.pageBreakMargins = NSEdgeInsets(
            top: DocumentAppearance.pageGap,
            left: DocumentAppearance.pageGap,
            bottom: DocumentAppearance.pageGap,
            right: DocumentAppearance.pageGap
        )
        // Kein autoScales: sonst rechnet die PDFView beim Oeffnen einen
        // eigenen Zoom aus und der Wert springt beim Moduswechsel.
        view.autoScales = false
        view.scaleFactor = zoom
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: AnnotatingPDFView, context: Context) {
        if nsView.document !== session.document {
            nsView.document = session.document
        }
        if abs(nsView.scaleFactor - zoom) > 0.001 {
            nsView.scaleFactor = zoom
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
        // Beim Moduswechsel verschwindet die Ansicht; eine offene Eingabe
        // muss vorher noch in die Annotation geschrieben werden.
        nsView.finishNoteEditing()
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

            // Erst nach dem ersten Layout laesst sich zuverlaessig springen.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.restoreCurrentPage()
                self.syncStateToSession()
            }
        }

        func detach() {
            NotificationCenter.default.removeObserver(self)
            if session.commandTarget === self {
                session.commandTarget = nil
            }
            pdfView = nil
        }

        /// Beim Moduswechsel wird die Ansicht neu aufgebaut — sie muss dort
        /// weitermachen, wo der Nutzer war.
        private func restoreCurrentPage() {
            guard let pdfView,
                  let page = pdfView.document?.page(at: session.currentPageIndex)
            else { return }
            pdfView.go(to: page)
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
            session.reportScale(pdfView.scaleFactor)
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

        /// Nach Undo/Redo hat sich der Annotationsbestand geaendert, ohne dass
        /// PDFKit davon etwas mitbekommen haette.
        func refreshDisplay() {
            pdfView?.needsDisplay = true
        }
    }
}
