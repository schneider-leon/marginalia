//
//  NotebookOverlay.swift
//  BestNotes
//
//  Inhalt von `overlays.json` — alles, was editierbar bleiben soll und
//  beim Export in die PDF-Seite eingebrannt wird.
//
//  Warum nicht als PDF-Annotation? Getippter Text waere dann in FreeText-
//  Annotationen gefangen: kein Rich-Text-Modell, kein verlaessliches Reflow,
//  und jeder externe Reader duerfte daran herumeditieren.
//

import CoreGraphics
import Foundation

struct TextOverlayContent: Codable, Hashable {
    var string: String
    var fontSize: CGFloat
    var colorHex: String
    var isBold: Bool
    var isItalic: Bool
    /// 0 = links, 1 = zentriert, 2 = rechts (wie `NSTextAlignment`).
    var alignment: Int

    init(
        string: String = "",
        fontSize: CGFloat = 13,
        colorHex: String = "#000000",
        isBold: Bool = false,
        isItalic: Bool = false,
        alignment: Int = 0
    ) {
        self.string = string
        self.fontSize = fontSize
        self.colorHex = colorHex
        self.isBold = isBold
        self.isItalic = isItalic
        self.alignment = alignment
    }
}

struct ImageOverlayContent: Codable, Hashable {
    /// Dateiname im `assets/`-Ordner des Pakets.
    var assetName: String
    var opacity: Double

    init(assetName: String, opacity: Double = 1) {
        self.assetName = assetName
        self.opacity = opacity
    }
}

/// Eigene Kodierung mit `type`-Diskriminator statt der synthetisierten.
///
/// Swift wuerde `{"text": {"_0": {...}}}` schreiben — eine Form, die sich
/// aendern kann, sobald ein Fall dazukommt. Bei einem Dateiformat, das auf
/// der Platte des Nutzers liegt, ist das keine gute Grundlage.
enum OverlayContent: Hashable {
    case text(TextOverlayContent)
    case image(ImageOverlayContent)
}

extension OverlayContent: Codable {
    private enum CodingKeys: String, CodingKey { case type, text, image }
    private enum Kind: String, Codable { case text, image }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .text:
            self = .text(try container.decode(TextOverlayContent.self, forKey: .text))
        case .image:
            self = .image(try container.decode(ImageOverlayContent.self, forKey: .image))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let content):
            try container.encode(Kind.text, forKey: .type)
            try container.encode(content, forKey: .text)
        case .image(let content):
            try container.encode(Kind.image, forKey: .type)
            try container.encode(content, forKey: .image)
        }
    }
}

struct Overlay: Identifiable, Hashable {
    let id: UUID
    /// In PDF-Punkten, Ursprung unten links — dasselbe System wie
    /// `PDFPage.bounds(for:)`, damit beim Rendern nichts umgerechnet wird.
    var frame: CGRect
    /// Grad, gegen den Uhrzeigersinn.
    var rotation: Double
    /// Groesser heisst weiter oben.
    var zIndex: Int
    var content: OverlayContent

    init(
        id: UUID = UUID(),
        frame: CGRect,
        rotation: Double = 0,
        zIndex: Int = 0,
        content: OverlayContent
    ) {
        self.id = id
        self.frame = frame
        self.rotation = rotation
        self.zIndex = zIndex
        self.content = content
    }
}

/// `CGRect` wuerde als `[[x, y], [w, h]]` kodieren. Benannte Felder sind
/// beim Nachsehen in der Datei deutlich freundlicher.
extension Overlay: Codable {
    private enum CodingKeys: String, CodingKey { case id, frame, rotation, zIndex, content }
    private enum FrameKeys: String, CodingKey { case x, y, width, height }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        rotation = try container.decodeIfPresent(Double.self, forKey: .rotation) ?? 0
        zIndex = try container.decodeIfPresent(Int.self, forKey: .zIndex) ?? 0
        content = try container.decode(OverlayContent.self, forKey: .content)

        let frameContainer = try container.nestedContainer(keyedBy: FrameKeys.self, forKey: .frame)
        frame = CGRect(
            x: try frameContainer.decode(CGFloat.self, forKey: .x),
            y: try frameContainer.decode(CGFloat.self, forKey: .y),
            width: try frameContainer.decode(CGFloat.self, forKey: .width),
            height: try frameContainer.decode(CGFloat.self, forKey: .height)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(rotation, forKey: .rotation)
        try container.encode(zIndex, forKey: .zIndex)
        try container.encode(content, forKey: .content)

        var frameContainer = container.nestedContainer(keyedBy: FrameKeys.self, forKey: .frame)
        try frameContainer.encode(frame.origin.x, forKey: .x)
        try frameContainer.encode(frame.origin.y, forKey: .y)
        try frameContainer.encode(frame.size.width, forKey: .width)
        try frameContainer.encode(frame.size.height, forKey: .height)
    }
}

struct PageOverlays: Codable, Hashable {
    var pageID: UUID
    var overlays: [Overlay]
}

/// Eigener Wrapper statt `[UUID: [Overlay]]`: JSONEncoder wuerde ein
/// Dictionary mit Nicht-String-Schluessel als flaches Array schreiben,
/// was die Datei unlesbar macht.
struct OverlayDocument: Codable, Hashable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var pages: [PageOverlays]

    init(pages: [PageOverlays] = []) {
        self.schemaVersion = Self.currentSchemaVersion
        self.pages = pages
    }

    subscript(pageID: UUID) -> [Overlay] {
        get { pages.first { $0.pageID == pageID }?.overlays ?? [] }
        set {
            if let index = pages.firstIndex(where: { $0.pageID == pageID }) {
                if newValue.isEmpty {
                    pages.remove(at: index)
                } else {
                    pages[index].overlays = newValue
                }
            } else if !newValue.isEmpty {
                pages.append(PageOverlays(pageID: pageID, overlays: newValue))
            }
        }
    }

    /// Sichtbare Reihenfolge: aufsteigend nach `zIndex`.
    func sortedOverlays(for pageID: UUID) -> [Overlay] {
        self[pageID].sorted { $0.zIndex < $1.zIndex }
    }
}
