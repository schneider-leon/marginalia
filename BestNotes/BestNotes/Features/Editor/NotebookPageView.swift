//
//  NotebookPageView.swift
//  BestNotes
//
//  Eine Seite im Notizbuch-Editor: Seitenhintergrund plus — auf
//  beschreibbaren Seiten — ein `NSTextView` auf dem gemeinsamen Container
//  dieser Seite.
//
//  Die Textansichten aller Seiten teilen sich einen `NSLayoutManager`. Wer
//  auf Seite 2 tippt, veraendert damit auch, was auf Seite 3 steht — genau
//  das ist der Punkt.
//

import AppKit
import PDFKit
import SwiftUI

// MARK: - Hintergrund

final class NotebookPageBackgroundView: NSView {
    var page: PDFPage?
    var ruling: PageRuling = .none
    var insets: TextInsets = .standard
    var lineHeight: CGFloat = 16

    override var isFlipped: Bool { true }

    /// Eine Seite ist weisses Papier, unabhaengig vom Systemdesign. Ohne das
    /// zeichnet AppKit im Dunkelmodus weisse Schrift, weisse Linien und einen
    /// weissen Cursor auf weisses Papier.
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        appearance = NSAppearance(named: .aqua)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        appearance = NSAppearance(named: .aqua)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        NSColor.white.setFill()
        bounds.fill()

        if let page {
            // PDFKit zeichnet in PDF-Koordinaten (Ursprung unten links),
            // diese View ist geflippt — also einmal zurueckdrehen.
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

// MARK: - Brücke

struct NotebookPageView: NSViewRepresentable {
    let session: DocumentSession
    let pageIndex: Int
    /// Index im Textfluss — `nil` bei importierten PDF-Seiten.
    let containerIndex: Int?
    let pageSize: CGSize
    let ruling: PageRuling
    let insets: TextInsets

    func makeNSView(context: Context) -> NotebookPageBackgroundView {
        let view = NotebookPageBackgroundView()
        view.autoresizingMask = []
        configure(view, context: context)

        if let containerIndex, let engine = session.textEngine,
           engine.containers.indices.contains(containerIndex) {
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
            view.addSubview(textView)
            context.coordinator.textView = textView
        }
        return view
    }

    func updateNSView(_ nsView: NotebookPageBackgroundView, context: Context) {
        configure(nsView, context: context)
        context.coordinator.textView?.frame = textFrame()
        nsView.needsDisplay = true
    }

    private func configure(_ view: NotebookPageBackgroundView, context: Context) {
        view.page = session.document.page(at: pageIndex)
        view.ruling = containerIndex == nil ? .none : ruling
        view.insets = insets
        view.lineHeight = session.textEngine.map {
            $0.layoutManager.defaultLineHeight(for: NotebookTextEngine.defaultFont)
        } ?? 16
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

        init(session: DocumentSession) {
            self.session = session
        }

        /// Die Formatierbefehle brauchen die Auswahl der zuletzt benutzten
        /// Seite — SwiftUI weiss von der nichts.
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            session.activeTextView = view
        }

        func textDidBeginEditing(_ notification: Notification) {
            session.activeTextView = notification.object as? NSTextView
        }
    }
}
