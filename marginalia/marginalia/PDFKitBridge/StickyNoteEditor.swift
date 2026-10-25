//
//  StickyNoteEditor.swift
//  marginalia
//
//  Input field that sits in place of the sticky note while typing.
//
//  PDFKit cannot edit FreeText annotations by itself. Instead of a dialog
//  we put an `NSTextView` in its place — it lives in the `PDFView`'s
//  document view and therefore scrolls along on its own.
//
//  While typing, the annotation is *not on the page*. Merely hiding it via
//  `shouldDisplay` was not enough: PDFKit does not redraw the page because
//  of it, and the note then stayed invisible even though it was in the
//  document. Removing and re-adding reliably triggers a redraw.
//

import AppKit
import PDFKit

@MainActor
final class StickyNoteEditor: NSObject, NSTextViewDelegate {

    enum Outcome {
        /// New note with text — has to go onto the page and onto the undo stack.
        case created
        /// Existing note, text changed.
        case edited(oldText: String?)
        /// New note without text — it never made it onto the page.
        case discarded
        /// Nothing changed.
        case unchanged
    }

    private var annotation: PDFAnnotation?
    private var page: PDFPage?
    private var originalText: String?
    private var isNewNote = false

    private weak var pdfView: PDFView?
    private var textView: NSTextView?
    private var scaleObserver: Any?

    var onFinish: ((_ annotation: PDFAnnotation, _ page: PDFPage, _ outcome: Outcome) -> Void)?

    var isEditing: Bool { textView != nil }

    /// Did editing end because the view lost focus?
    ///
    /// The click that triggered it should not create a new note — and
    /// depending on the order of events, editing is already over before our
    /// `mouseDown` runs.
    private var endedByFocusLoss = false

    func consumeFocusLossFinish() -> Bool {
        defer { endedByFocusLoss = false }
        return endedByFocusLoss
    }

    func begin(
        editing annotation: PDFAnnotation,
        on page: PDFPage,
        isNew: Bool,
        in pdfView: PDFView,
        style: AnnotationStyle
    ) {
        finish()
        guard let documentView = pdfView.documentView else { return }

        self.pdfView = pdfView
        self.annotation = annotation
        self.page = page
        self.originalText = annotation.contents
        self.isNewNote = isNew
        self.endedByFocusLoss = false

        let field = makeTextView(for: annotation, style: style)
        documentView.addSubview(field)
        textView = field
        reposition()

        // If we do not get the input focus, we do not take over either.
        guard pdfView.window?.makeFirstResponder(field) == true else {
            field.removeFromSuperview()
            clearState()
            return
        }

        // The existing note makes way for the input field.
        if !isNew {
            page.removeAnnotation(annotation)
            invalidate(annotation.bounds, on: page)
        }

        scaleObserver = NotificationCenter.default.addObserver(
            forName: .PDFViewScaleChanged,
            object: pdfView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
    }

    private func makeTextView(for annotation: PDFAnnotation, style: AnnotationStyle) -> NSTextView {
        let field = NSTextView(frame: .zero)
        field.delegate = self
        field.isRichText = false
        field.allowsUndo = true
        field.drawsBackground = true
        field.backgroundColor = style.noteNSColor
        field.textColor = style.textNSColor
        field.font = .systemFont(ofSize: style.textSize)
        field.textContainerInset = NSSize(width: 5, height: 5)
        field.string = annotation.contents ?? ""
        field.appearance = NSAppearance(named: .aqua)
        field.insertionPointColor = style.textNSColor
        field.wantsLayer = true
        field.layer?.cornerRadius = 3
        // The border shows which note is currently being edited.
        field.layer?.borderWidth = 2
        field.layer?.borderColor = NSColor.controlAccentColor.cgColor
        return field
    }

    /// Places the field where the note is — in document view coordinates so
    /// it moves along when scrolling.
    func reposition() {
        guard let textView,
              let pdfView,
              let documentView = pdfView.documentView,
              let annotation,
              let page
        else { return }
        let inView = pdfView.convert(annotation.bounds, from: page)
        textView.frame = documentView.convert(inView, from: pdfView)
    }

    func textDidEndEditing(_ notification: Notification) {
        endedByFocusLoss = true
        finish()
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.cancelOperation(_:)):
            finish()
            return true

        case #selector(NSResponder.insertNewline(_:)):
            // Return finishes the note, Shift-Return starts a new line. Some
            // keyboard layouts send this command for Shift-Return too — so we
            // look at the modifiers instead of relying on the command alone.
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                textView.insertText("\n", replacementRange: textView.selectedRange())
            } else {
                finish()
            }
            return true

        case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            textView.insertText("\n", replacementRange: textView.selectedRange())
            return true

        default:
            return false
        }
    }

    @discardableResult
    func finish() -> Bool {
        guard let textView, let annotation, let page else { return false }

        let typed = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let previous = (originalText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let wasNew = isNewNote

        textView.removeFromSuperview()
        self.textView = nil
        if let scaleObserver {
            NotificationCenter.default.removeObserver(scaleObserver)
            self.scaleObserver = nil
        }

        let outcome: Outcome
        if typed.isEmpty && previous.isEmpty {
            // A note that never got any text — it stays away.
            outcome = wasNew ? .discarded : .unchanged
            if !wasNew { page.addAnnotation(annotation) }
        } else {
            // An empty field must not delete existing text.
            if !typed.isEmpty {
                annotation.contents = typed
                resizeToFitText(annotation, on: page)
            }
            page.addAnnotation(annotation)
            outcome = wasNew ? .created : (annotation.contents == originalText ? .unchanged : .edited(oldText: originalText))
        }

        invalidate(annotation.bounds, on: page)
        clearState()
        onFinish?(annotation, page, outcome)
        return true
    }

    private func clearState() {
        annotation = nil
        page = nil
        originalText = nil
        isNewNote = false
    }

    private func invalidate(_ bounds: CGRect, on page: PDFPage) {
        guard let pdfView else { return }
        pdfView.setNeedsDisplay(pdfView.convert(bounds, from: page).insetBy(dx: -12, dy: -12))
    }

    /// The note size follows the text: the top left stays put, the note
    /// grows downward and stays on the page.
    private func resizeToFitText(_ annotation: PDFAnnotation, on page: PDFPage) {
        guard let text = annotation.contents, !text.isEmpty else { return }
        let font = annotation.font ?? .systemFont(ofSize: 13)
        let padding: CGFloat = 10
        let maxWidth = max(annotation.bounds.width, AnnotationStyle.defaultNoteSize.width)

        let measured = (text as NSString).boundingRect(
            with: CGSize(width: maxWidth - padding, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        let size = CGSize(
            width: min(maxWidth, ceil(measured.width) + padding * 2),
            height: ceil(measured.height) + padding
        )

        let pageBounds = page.bounds(for: .cropBox)
        let top = annotation.bounds.maxY
        var frame = CGRect(x: annotation.bounds.minX, y: top - size.height, width: size.width, height: size.height)
        frame.origin.x = min(max(frame.minX, pageBounds.minX), pageBounds.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, pageBounds.minY), pageBounds.maxY - frame.height)
        annotation.bounds = frame
    }
}
