//
//  PDFViewRepresentable.swift
//  marginalia
//
//  Thin bridge between SwiftUI and PDFKit.
//
//  Rules that apply here:
//  1. `makeNSView` builds the `PDFView` once.
//  2. `updateNSView` only reconciles a few, explicitly passed values —
//     never the whole document as long as it is the same one.
//  3. Everything imperative (scrolling, zooming) goes through the
//     coordinator as `PDFViewCommandTarget`, not through state diffs.
//

import PDFKit
import SwiftUI

struct PDFViewRepresentable: NSViewRepresentable {
    let session: DocumentSession

    /// Deliberately separate parameters instead of access via `session`:
    /// this way the SwiftUI update visibly depends on exactly these values.
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
        // The same color as behind the editor; the page spacing too.
        view.backgroundColor = .documentBackground
        view.pageBreakMargins = NSEdgeInsets(
            top: DocumentAppearance.pageGap,
            left: DocumentAppearance.pageGap,
            bottom: DocumentAppearance.pageGap,
            right: DocumentAppearance.pageGap
        )
        // No autoScales: otherwise the PDFView computes its own zoom when
        // opening and the value jumps when switching modes.
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
        // When switching modes the view disappears; any open input has to be
        // written into the annotation first.
        nsView.finishNoteEditing()
        nsView.hideHover()
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

            // Jumping only works reliably after the first layout.
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

        /// The view is rebuilt when switching modes — it has to continue
        /// where the user was.
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

        /// After undo/redo the set of annotations has changed without PDFKit
        /// noticing.
        func refreshDisplay() {
            // The annotation under the eraser may just have disappeared.
            pdfView?.hideHover()
            pdfView?.needsDisplay = true
        }

        func endTransientPreviews() {
            pdfView?.hideHover()
        }
    }
}
