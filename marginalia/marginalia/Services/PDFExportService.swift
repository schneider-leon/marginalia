//
//  PDFExportService.swift
//  marginalia
//

import AppKit
import PDFKit
import UniformTypeIdentifiers

enum PDFExportError: LocalizedError {
    case writeFailed(URL)

    var errorDescription: String? {
        switch self {
        case .writeFailed(let url):
            "“\(url.lastPathComponent)” could not be written."
        }
    }

    var recoverySuggestion: String? {
        "Check that there is enough free disk space and that the destination folder is writable."
    }
}

@MainActor
enum PDFExportService {

    static func chooseExportURL(suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(suggestedName).pdf"
        panel.canCreateDirectories = true
        panel.title = "Export as PDF"
        panel.message = "Annotations are included."
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Writes to a temporary file and only replaces the destination after
    /// that.
    ///
    /// Writing directly to the source URL would be risky: PDFKit may keep
    /// the file mapped, and an interruption halfway through would have
    /// destroyed the original.
    static func write(_ document: PDFDocument, to url: URL) throws {
        let fileManager = FileManager.default
        let temporary = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("marginalia-\(UUID().uuidString).pdf")

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
