//
//  NotebookInfo.swift
//  BestNotes
//
//  Inhalt von `info.json` — die Metadaten eines Notizbuchs.
//
//  Die Seitenreihenfolge steht hier, nicht in der PDF: `pages[i]` beschreibt
//  Seite `i` von `content.pdf`. Overlays haengen an der Seiten-UUID statt am
//  Index, damit Umsortieren sie nicht verschiebt.
//

import Foundation

enum PageKind: String, Codable, Hashable {
    /// Vom Nutzer eingefuegte leere Seite (Schritt 7).
    case blank
    /// Seite aus einer importierten PDF.
    case imported
}

struct PageDescriptor: Codable, Identifiable, Hashable {
    let id: UUID
    var kind: PageKind
    /// Rein informativ: Name der Datei, aus der die Seite stammt.
    var source: String?

    init(id: UUID = UUID(), kind: PageKind, source: String? = nil) {
        self.id = id
        self.kind = kind
        self.source = source
    }
}

struct NotebookInfo: Codable, Hashable {
    /// Wird beim Lesen geprueft. Aeltere Versionen werden migriert,
    /// neuere abgelehnt — lieber verweigern als Daten zerschreiben.
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var id: UUID
    var title: String
    var created: Date
    var modified: Date
    var pages: [PageDescriptor]

    init(id: UUID = UUID(), title: String, pages: [PageDescriptor] = []) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.title = title
        self.created = Date()
        self.modified = Date()
        self.pages = pages
    }
}
