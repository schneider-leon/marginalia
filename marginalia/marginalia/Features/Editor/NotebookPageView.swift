//
//  NotebookPageView.swift
//  marginalia
//
//  A page in the notebook editor: page background plus — on writable
//  pages — an `NSTextView` on this page's shared container.
//
//  The text views of all pages share one `NSLayoutManager`. Typing on
//  page 2 also changes what is on page 3 — that is exactly the point.
//

import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Background

final class NotebookPageBackgroundView: NSView {
    /// Size of the page in PDF points. SwiftUI frames the view larger or
    /// smaller, but its `bounds` stay the page size — that way AppKit scales
    /// content *and* subviews sharply instead of enlarging a finished image.
    var pageSize: CGSize = PDFPageFactory.a4 {
        didSet {
            applyPageScale()
            needsDisplay = true
        }
    }

    var page: PDFPage?
    var ruling: PageRuling = .none
    var insets: TextInsets = .standard
    var lineHeight: CGFloat = 16

    var onDropImageData: ((Data, String) -> Void)?
    var onDropFileURL: ((URL) -> Void)?

    override var isFlipped: Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        applyPageScale()
    }

    private func applyPageScale() {
        guard pageSize.width > 0, pageSize.height > 0, bounds.size != pageSize else { return }
        setBoundsSize(pageSize)
    }

    /// A page is white paper, regardless of the system appearance. Without
    /// this, AppKit draws white text, white lines and a white cursor on white
    /// paper in dark mode.
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        appearance = NSAppearance(named: .aqua)
        registerForDraggedTypes([.fileURL, .png, .tiff])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        appearance = NSAppearance(named: .aqua)
        registerForDraggedTypes([.fileURL, .png, .tiff])
    }

    // MARK: - Drag & Drop
    //
    // The drop is attached to the background view because it is always hit
    // — the image layer above deliberately declares itself not responsible
    // for empty spots.

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        droppableImageURL(sender) != nil || droppableImageData(sender) != nil ? .copy : []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        draggingEntered(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        if let url = droppableImageURL(sender) {
            onDropFileURL?(url)
            return true
        }
        if let (data, ext) = droppableImageData(sender) {
            onDropImageData?(data, ext)
            return true
        }
        return false
    }

    private func droppableImageURL(_ sender: any NSDraggingInfo) -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier]
        ]
        return (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options)
            as? [URL])?.first
    }

    private func droppableImageData(_ sender: any NSDraggingInfo) -> (Data, String)? {
        let board = sender.draggingPasteboard
        if let data = board.data(forType: .png) { return (data, "png") }
        if let data = board.data(forType: .tiff) { return (data, "tiff") }
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        NSColor.white.setFill()
        bounds.fill()

        if let page {
            // PDFKit draws in PDF coordinates (origin at the bottom left),
            // this view is flipped — so flip back once.
            context.saveGState()
            context.translateBy(x: 0, y: bounds.height)
            context.scaleBy(x: 1, y: -1)
            page.draw(with: .cropBox, to: context)
            context.restoreGState()
        }

        let area = CGRect(
            x: insets.leading,
            y: insets.top,
            width: bounds.width - insets.leading - insets.trailing,
            height: bounds.height - insets.top - insets.bottom
        )
        NotebookRenderer.drawRuling(ruling, in: area, lineHeight: lineHeight)
    }
}

// MARK: - Bridge

struct NotebookPageView: NSViewRepresentable {
    let session: DocumentSession
    let pageIndex: Int
    /// Index in the text flow — `nil` for imported PDF pages.
    let containerIndex: Int?
    let pageSize: CGSize
    let ruling: PageRuling
    let insets: TextInsets
    /// Only so SwiftUI triggers an update when images change.
    let overlayRevision: Int
    let selectedOverlayID: UUID?

    func makeNSView(context: Context) -> NotebookPageBackgroundView {
        let view = NotebookPageBackgroundView()
        view.autoresizingMask = []
        configure(view, context: context)

        let engine = session.textEngine
        if let containerIndex, engine.containers.indices.contains(containerIndex) {
            let textView = NSTextView(
                frame: textFrame(),
                textContainer: engine.containers[containerIndex]
            )
            textView.isEditable = true
            textView.isSelectable = true
            textView.isRichText = true
            textView.allowsUndo = true
            textView.drawsBackground = false
            textView.isVerticallyResizable = false
            textView.isHorizontallyResizable = false
            textView.textContainerInset = .zero
            textView.delegate = context.coordinator
            textView.typingAttributes = NotebookTextEngine.defaultAttributes
            textView.appearance = NSAppearance(named: .aqua)
            textView.insertionPointColor = .black
            // The text view may keep text drops; images and files should
            // fall through to the page.
            textView.unregisterDraggedTypes()
            textView.registerForDraggedTypes([.string])
            view.addSubview(textView)
            context.coordinator.textView = textView
        }

        // Added last means: on top.
        let overlayView = ImageOverlayNSView()
        overlayView.session = session
        overlayView.pageIndex = pageIndex
        overlayView.pageSize = pageSize
        overlayView.frame = CGRect(origin: .zero, size: pageSize)
        view.addSubview(overlayView)
        context.coordinator.overlayView = overlayView

        view.onDropFileURL = { [weak session] url in
            guard let session else { return }
            session.setCurrentPage(pageIndex)
            try? session.insertImage(from: url, atPageIndex: pageIndex)
        }
        view.onDropImageData = { [weak session] data, ext in
            guard let session else { return }
            session.setCurrentPage(pageIndex)
            session.insertImage(data: data, fileExtension: ext, atPageIndex: pageIndex)
        }
        return view
    }

    func updateNSView(_ nsView: NotebookPageBackgroundView, context: Context) {
        configure(nsView, context: context)
        context.coordinator.textView?.frame = textFrame()
        if let overlayView = context.coordinator.overlayView {
            overlayView.pageSize = pageSize
            overlayView.frame = CGRect(origin: .zero, size: pageSize)
            overlayView.needsDisplay = true
        }
        nsView.needsDisplay = true
    }

    private func configure(_ view: NotebookPageBackgroundView, context: Context) {
        view.pageSize = pageSize
        view.page = session.document.page(at: pageIndex)
        view.ruling = containerIndex == nil ? .none : ruling
        view.insets = insets
        view.lineHeight = session.textEngine.layoutManager
            .defaultLineHeight(for: NotebookTextEngine.defaultFont)
    }

    private func textFrame() -> CGRect {
        CGRect(
            x: insets.leading,
            y: insets.top,
            width: pageSize.width - insets.leading - insets.trailing,
            height: pageSize.height - insets.top - insets.bottom
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        private let session: DocumentSession
        weak var textView: NSTextView?
        weak var overlayView: ImageOverlayNSView?

        init(session: DocumentSession) {
            self.session = session
        }

        /// The formatting commands need the selection of the most recently
        /// used page — SwiftUI knows nothing about it.
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            session.activeTextView = view
            session.reportSelectionChanged()
        }

        func textDidBeginEditing(_ notification: Notification) {
            session.activeTextView = notification.object as? NSTextView
            session.reportSelectionChanged()
        }
    }
}
