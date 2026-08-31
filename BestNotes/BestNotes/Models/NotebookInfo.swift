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

import CoreGraphics
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

/// Schreibrand einer Seite in Punkten.
struct TextInsets: Codable, Hashable {
    var top: CGFloat
    var leading: CGFloat
    var bottom: CGFloat
    var trailing: CGFloat

    /// Rund 2 cm — nah an dem, was Textverarbeitungen voreinstellen.
    static let standard = TextInsets(top: 56, leading: 56, bottom: 56, trailing: 56)

    func textAreaSize(for page: CGSize) -> CGSize {
        CGSize(
            width: max(page.width - leading - trailing, 1),
            height: max(page.height - top - bottom, 1)
        )
    }
}

/// Hilfslinien auf leeren Seiten.
enum PageRuling: String, Codable, CaseIterable, Identifiable {
    case none
    case lines
    case grid

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "Ohne"
        case .lines: "Linien"
        case .grid: "Karo"
        }
    }

    var symbol: String {
        switch self {
        case .none: "rectangle"
        case .lines: "line.3.horizontal"
        case .grid: "square.grid.3x3"
        }
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
    var textInsets: TextInsets
    var ruling: PageRuling

    init(id: UUID = UUID(), title: String, pages: [PageDescriptor] = []) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.title = title
        self.created = Date()
        self.modified = Date()
        self.pages = pages
        self.textInsets = .standard
        self.ruling = .none
    }
}

/// Nachgereichte Felder werden tolerant gelesen, damit aeltere Pakete ohne
/// Schemawechsel weiter aufgehen.
extension NotebookInfo {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        created = try container.decode(Date.self, forKey: .created)
        modified = try container.decode(Date.self, forKey: .modified)
        pages = try container.decode([PageDescriptor].self, forKey: .pages)
        textInsets = try container.decodeIfPresent(TextInsets.self, forKey: .textInsets) ?? .standard
        ruling = try container.decodeIfPresent(PageRuling.self, forKey: .ruling) ?? .none
    }
}
