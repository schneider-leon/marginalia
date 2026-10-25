//
//  NotebookOverlay.swift
//  marginalia
//
//  Contents of `overlays.json` — everything that should stay editable and
//  is burned into the PDF page on export.
//
//  Why not as PDF annotations? Typed text would then be trapped in FreeText
//  annotations: no rich-text model, no reliable reflow, and any external
//  reader would be free to edit it.
//

import CoreGraphics
import Foundation

struct TextOverlayContent: Codable, Hashable {
    var string: String
    var fontSize: CGFloat
    var colorHex: String
    var isBold: Bool
    var isItalic: Bool
    /// 0 = left, 1 = centered, 2 = right (like `NSTextAlignment`).
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
    /// File name in the package's `assets/` folder.
    var assetName: String
    var opacity: Double

    init(assetName: String, opacity: Double = 1) {
        self.assetName = assetName
        self.opacity = opacity
    }
}

/// Custom encoding with a `type` discriminator instead of the synthesized
/// one.
///
/// Swift would write `{"text": {"_0": {...}}}` — a shape that can change as
/// soon as a case is added. For a file format that lives on the user's
/// disk, that is not a good foundation.
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
    /// In PDF points, origin at the bottom left — the same system as
    /// `PDFPage.bounds(for:)`, so nothing has to be converted when rendering.
    var frame: CGRect
    /// Degrees, counterclockwise.
    var rotation: Double
    /// Larger means further on top.
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

/// `CGRect` would encode as `[[x, y], [w, h]]`. Named fields are much
/// friendlier when looking into the file.
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

/// Custom wrapper instead of `[UUID: [Overlay]]`: JSONEncoder would write a
/// dictionary with non-string keys as a flat array, which makes the file
/// unreadable.
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

    /// Visible order: ascending by `zIndex`.
    func sortedOverlays(for pageID: UUID) -> [Overlay] {
        self[pageID].sorted { $0.zIndex < $1.zIndex }
    }
}
