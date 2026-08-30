//
//  PDFExportService.swift
//  BestNotes
//

import AppKit
import PDFKit
import UniformTypeIdentifiers

enum PDFExportError: LocalizedError {
    case writeFailed(URL)

    var errorDescription: String? {
        switch self {
        case .writeFailed(let url):
            "„\(url.lastPathComponent)“ konnte nicht geschrieben werden."
        }
    }

    var recoverySuggestion: String? {
        "Pruefe, ob genug Speicherplatz frei ist und der Zielordner beschreibbar ist."
    }
}

@MainActor
enum PDFExportService {

    static func chooseExportURL(suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(suggestedName).pdf"
        panel.canCreateDirectories = true
        panel.title = "Als PDF exportieren"
        panel.message = "Annotationen werden mitgeschrieben."
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Schreibt ueber eine Zwischendatei und ersetzt das Ziel erst danach.
    ///
    /// Direkt auf die Quell-URL zu schreiben waere riskant: PDFKit haelt die
    /// Datei ggf. gemappt, und ein Abbruch mittendrin haette das Original
    /// zerstoert.
    static func write(_ document: PDFDocument, to url: URL) throws {
        let fileManager = FileManager.default
        let temporary = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("BestNotes-\(UUID().uuidString).pdf")

        guard document.write(to: temporary) else {
            throw PDFExportError.writeFailed(url)
        }

        if fileManager.fileExists(atPath: url.path) {
            _ = try fileManager.replaceItemAt(url, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: url)
        }
    }
}
