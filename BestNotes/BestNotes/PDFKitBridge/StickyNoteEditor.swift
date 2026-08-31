//
//  StickyNoteEditor.swift
//  BestNotes
//
//  Eingabefeld, das waehrend des Tippens an der Stelle des Notizzettels liegt.
//
//  PDFKit kann FreeText-Annotationen nicht selbst bearbeiten. Statt eines
//  Dialogs legen wir eine `NSTextView` an die Stelle — sie haengt in der
//  Dokumentansicht der `PDFView` und scrollt daher von allein mit.
//
//  Waehrend der Eingabe ist die Annotation *nicht auf der Seite*. Sie ueber
//  `shouldDisplay` nur zu verstecken hat nicht gereicht: PDFKit zeichnet die
//  Seite deswegen nicht neu, und der Zettel blieb danach unsichtbar, obwohl
//  er im Dokument stand. Wegnehmen und wieder Anhaengen loest zuverlaessig
//  eine Neuzeichnung aus.
//

import AppKit
import PDFKit

@MainActor
final class StickyNoteEditor: NSObject, NSTextViewDelegate {

    enum Outcome {
        /// Neuer Zettel mit Text — muss auf die Seite und in den Undo-Stapel.
        case created
        /// Vorhandener Zettel, Text geaendert.
        case edited(oldText: String?)
        /// Neuer Zettel ohne Text — er kam nie auf die Seite.
        case discarded
        /// Nichts hat sich geaendert.
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

        let field = makeTextView(for: annotation, style: style)
        documentView.addSubview(field)
        textView = field
        reposition()

        // Bekommen wir die Eingabe nicht, uebernehmen wir auch nicht.
        guard pdfView.window?.makeFirstResponder(field) == true else {
            field.removeFromSuperview()
            clearState()
            return
        }

        // Der vorhandene Zettel weicht dem Eingabefeld.
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
        return field
    }

    /// Legt das Feld an die Stelle des Zettels — in Koordinaten der
    /// Dokumentansicht, damit es beim Scrollen mitwandert.
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
        finish()
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        finish()
        return true
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
            // Nie beschrifteter Zettel — er bleibt weg.
            outcome = wasNew ? .discarded : .unchanged
            if !wasNew { page.addAnnotation(annotation) }
        } else {
            // Ein leeres Feld darf vorhandenen Text nicht loeschen.
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

    /// Zettelgroesse folgt dem Text: oben links bleibt stehen, er waechst
    /// nach unten und bleibt auf der Seite.
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
