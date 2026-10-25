//
//  NotebookInfo.swift
//  marginalia
//
//  Contents of `info.json` — a notebook's metadata.
//
//  The page order lives here, not in the PDF: `pages[i]` describes page
//  `i` of `content.pdf`. Overlays are attached to the page UUID instead of
//  the index so reordering does not shift them.
//

import CoreGraphics
import Foundation

enum PageKind: String, Codable, Hashable {
    /// Blank page inserted by the user (step 7).
    case blank
    /// Page from an imported PDF.
    case imported
}

struct PageDescriptor: Codable, Identifiable, Hashable {
    let id: UUID
    var kind: PageKind
    /// Purely informational: name of the file the page came from.
    var source: String?

    init(id: UUID = UUID(), kind: PageKind, source: String? = nil) {
        self.id = id
        self.kind = kind
        self.source = source
    }
}

/// Writing margin of a page in points.
struct TextInsets: Codable, Hashable {
    var top: CGFloat
    var leading: CGFloat
    var bottom: CGFloat
    var trailing: CGFloat

    /// About 2 cm — close to what word processors use by default.
    static let standard = TextInsets(top: 56, leading: 56, bottom: 56, trailing: 56)

    func textAreaSize(for page: CGSize) -> CGSize {
        CGSize(
            width: max(page.width - leading - trailing, 1),
            height: max(page.height - top - bottom, 1)
        )
    }
}

/// Guide lines on blank pages.
enum PageRuling: String, Codable, CaseIterable, Identifiable {
    case none
    case lines
    case grid

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "None"
        case .lines: "Lines"
        case .grid: "Grid"
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
    /// Checked when reading. Older versions are migrated, newer ones
    /// rejected — better to refuse than to corrupt data.
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

/// Fields added later are read leniently so older packages keep opening
/// without a schema change.
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
