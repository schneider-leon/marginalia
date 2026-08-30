//
//  PDFPageFactory.swift
//  BestNotes
//

import CoreGraphics
import Foundation
import PDFKit

enum PDFPageFactory {
    static let a4 = CGSize(width: 595, height: 842)
    static let usLetter = CGSize(width: 612, height: 792)

    /// Erzeugt leere weisse Seiten.
    ///
    /// Der Umweg ueber einen CGPDFContext statt `PDFPage()` ist noetig, weil
    /// eine so erzeugte Seite eine feste Standardgroesse haette — wir wollen
    /// die Groesse aber vorgeben (und sie soll zur Nachbarseite passen).
    static func blankDocument(size: CGSize = a4, count: Int = 1) -> PDFDocument? {
        guard count > 0, size.width > 0, size.height > 0 else { return nil }

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }
        var mediaBox = CGRect(origin: .zero, size: size)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        for _ in 0..<count {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(mediaBox)
            context.endPDFPage()
        }
        context.closePDF()

        return PDFDocument(data: data as Data)
    }

    static func blankPage(size: CGSize = a4) -> PDFPage? {
        blankDocument(size: size)?.page(at: 0)
    }
}
