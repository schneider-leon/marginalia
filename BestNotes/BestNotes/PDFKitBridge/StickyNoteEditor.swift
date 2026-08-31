//
//  StickyNoteEditor.swift
//  BestNotes
//
//  Eingabefeld, das waehrend des Tippens ueber dem Notizzettel liegt.
//
//  PDFKit kann FreeText-Annotationen nicht selbst bearbeiten. Statt eines
//  Dialogs legen wir eine `NSTextView` genau auf die Annotation — sie haengt
//  in der Dokumentansicht der `PDFView`, scrollt also von allein mit.
//

import AppKit
import PDFKit

@MainActor
final class StickyNoteEditor: NSObject, NSTextViewDelegate {

    private(set) var annotation: PDFAnnotation?
    private(set) var page: PDFPage?
    private(set) var originalText: String?

    private weak var pdfView: PDFView?
    private var textView: NSTextView?
    private var scrollObserver: Any?

    /// Wird beim Beenden gerufen: leerer Text heisst, der Zettel soll weg.
    var onFinish: ((_ annotation: PDFAnnotation, _ page: PDFPage, _ oldText: String?, _ isEmpty: Bool) -> Void)?

    var isEditing: Bool { textView != nil }

    func begin(
        editing annotation: PDFAnnotation,
        on page: PDFPage,
        in pdfView: PDFView,
        style: AnnotationStyle
    ) {
        finish()

        guard let documentView = pdfView.documentView else { return }
        self.pdfView = pdfView
        self.annotation = annotation
        self.page = page
        self.originalText = annotation.contents

        let field = NSTextView(frame: .zero)
        field.delegate = self
        field.isRichText = false
        field.allowsUndo = true
        field.drawsBackground = true
        field.backgroundColor = style.noteNSColor
        field.textColor = style.textNSColor
        field.font = .systemFont(ofSize: style.textSize)
        field.textContainerInset = NSSize(width: 4, height: 4)
        field.string = annotation.contents ?? ""
        field.appearance = NSAppearance(named: .aqua)
        field.insertionPointColor = style.textNSColor
        field.wantsLayer = true
        field.layer?.cornerRadius = 3

        documentView.addSubview(field)
        textView = field
        reposition()

        // Bekommen wir die Eingabe nicht, uebernehmen wir auch nicht: sonst
        // stuende ein leeres Feld ueber der Annotation und wuerde sie beim
        // Beenden mit seinem leeren Inhalt ueberschreiben.
        guard pdfView.window?.makeFirstResponder(field) == true else {
            field.removeFromSuperview()
            textView = nil
            self.annotation = nil
            self.page = nil
            self.originalText = nil
            return
        }

        // Erst jetzt verdecken: das Feld zeigt den Inhalt, die Annotation
        // darunter waere sonst doppelt zu sehen.
        annotation.shouldDisplay = false

        scrollObserver = NotificationCenter.default.addObserver(
            forName: .PDFViewScaleChanged,
            object: pdfView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
    }

    /// Legt das Feld genau auf die Annotation — in Koordinaten der
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

    /// Escape beendet die Eingabe.
    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        finish()
        return true
    }

    @discardableResult
    func finish() -> Bool {
        guard let textView, let annotation, let page else { return false }

        let typed = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = (annotation.contents ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        // Nur schreiben, wenn wirklich etwas getippt wurde. Vorhandenen Text
        // mit einem leeren Feld zu ueberschreiben waere Datenverlust — und
        // genau das hat Zettel verschwinden lassen.
        if !typed.isEmpty {
            annotation.contents = typed
            resizeToFitText(annotation, on: page)
        }
        let isEmpty = typed.isEmpty && existing.isEmpty

        annotation.shouldDisplay = true

        textView.removeFromSuperview()
        self.textView = nil

        if let scrollObserver {
            NotificationCenter.default.removeObserver(scrollObserver)
            self.scrollObserver = nil
        }

        let oldText = originalText
        self.annotation = nil
        self.page = nil
        self.originalText = nil

        onFinish?(annotation, page, oldText, isEmpty)
        return true
    }

    /// Zettel an den Text anpassen — die Groesse soll dem Inhalt folgen.
    private func resizeToFitText(_ annotation: PDFAnnotation, on page: PDFPage) {
        guard let text = annotation.contents, !text.isEmpty else { return }
        let font = annotation.font ?? .systemFont(ofSize: 13)
        let padding: CGFloat = 10
        let maxWidth = max(annotation.bounds.width, 180)

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
        // Oben links bleibt stehen, der Zettel waechst nach unten.
        let top = annotation.bounds.maxY
        var frame = CGRect(x: annotation.bounds.minX, y: top - size.height, width: size.width, height: size.height)
        frame.origin.x = min(max(frame.minX, pageBounds.minX), pageBounds.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, pageBounds.minY), pageBounds.maxY - frame.height)
        annotation.bounds = frame
    }
}
