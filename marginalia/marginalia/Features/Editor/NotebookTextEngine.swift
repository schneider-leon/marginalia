//
//  NotebookTextEngine.swift
//  marginalia
//
//  The text flow of a notebook.
//
//  A single `NSTextStorage` runs across several page-sized
//  `NSTextContainer`s — exactly the model word processors use to break
//  pages. Inserting a line on page 2 pushes the rest over the page edge onto
//  page 3; the `NSLayoutManager` takes care of that by itself.
//
//  Deliberately TextKit 1: several containers on one layout manager are the
//  intended approach there and support both editing in the NSTextView and
//  rendering on export.
//

import AppKit
import Foundation

@MainActor
final class NotebookTextEngine: NSObject, NSTextStorageDelegate {

    /// Called after every change to the text — the session then marks
    /// unsaved changes and adds pages as needed.
    var onEdited: (() -> Void)?

    let textStorage: NSTextStorage
    let layoutManager: NSLayoutManager

    /// One container per *writable* page, in document order. Imported PDF
    /// pages get none — the text flows past them to the next blank page.
    private(set) var containers: [NSTextContainer] = []

    static let defaultFont = NSFont.systemFont(ofSize: 13)

    init(rtf: Data? = nil) {
        let attributed: NSAttributedString
        if let rtf, let restored = NSAttributedString(rtf: rtf, documentAttributes: nil) {
            attributed = Self.repairInvisibleInk(restored)
        } else {
            attributed = NSAttributedString(string: "", attributes: Self.defaultAttributes)
        }
        textStorage = NSTextStorage(attributedString: attributed)
        layoutManager = NSLayoutManager()
        layoutManager.usesFontLeading = true
        textStorage.addLayoutManager(layoutManager)
        super.init()
        textStorage.delegate = self
    }

    nonisolated func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        MainActor.assumeIsolated { onEdited?() }
    }

    /// Deliberately `NSColor.black` instead of `.textColor`: the page is
    /// always white paper — in dark mode too, and all the more so in the
    /// exported PDF. A dynamic color would resolve to white there and be
    /// invisible.
    /// Previously saved text can carry white text: the default color used to
    /// be `NSColor.textColor`, which resolves to white in dark mode —
    /// invisible on white paper. This is reverted on load so old notes do
    /// not stay invisible.
    private static func repairInvisibleInk(_ text: NSAttributedString) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: text)
        let full = NSRange(location: 0, length: mutable.length)
        mutable.enumerateAttribute(.foregroundColor, in: full) { value, range, _ in
            guard let color = (value as? NSColor)?.usingColorSpace(.deviceRGB) else { return }
            if color.brightnessComponent > 0.9 && color.saturationComponent < 0.1 {
                mutable.addAttribute(.foregroundColor, value: NSColor.black, range: range)
            }
        }
        return mutable
    }

    static var defaultAttributes: [NSAttributedString.Key: Any] {
        [.font: defaultFont, .foregroundColor: NSColor.black]
    }

    var isEmpty: Bool { textStorage.length == 0 }

    // MARK: - Containers

    /// Matches the number and size of the containers to the writable pages.
    func updateContainers(sizes: [CGSize]) {
        while containers.count < sizes.count {
            let container = NSTextContainer(size: .zero)
            container.lineFragmentPadding = 0
            container.widthTracksTextView = false
            container.heightTracksTextView = false
            layoutManager.addTextContainer(container)
            containers.append(container)
        }
        while containers.count > sizes.count {
            layoutManager.removeTextContainer(at: containers.count - 1)
            containers.removeLast()
        }
        for (index, size) in sizes.enumerated() where containers[index].size != size {
            containers[index].size = size
        }
    }

    /// Whether the text runs past the last container — then a page is missing.
    var overflows: Bool {
        guard let last = containers.last else { return textStorage.length > 0 }
        for container in containers {
            layoutManager.ensureLayout(for: container)
        }
        let laid = layoutManager.glyphRange(for: last)
        return NSMaxRange(laid) < layoutManager.numberOfGlyphs
    }

    /// How many pages the text needs in total — beyond the existing
    /// containers too.
    func requiredPageCount(pageSize: CGSize) -> Int {
        guard textStorage.length > 0 else { return max(containers.count, 1) }

        var count = containers.count
        var probeStorage: NSTextStorage?
        var probeLayout: NSLayoutManager?

        while true {
            let manager: NSLayoutManager
            if count == containers.count {
                manager = layoutManager
                for container in containers { manager.ensureLayout(for: container) }
                guard let last = containers.last else { return 1 }
                if NSMaxRange(manager.glyphRange(for: last)) >= manager.numberOfGlyphs { return count }
            } else {
                // Trial run on a copy so the real flow stays untouched.
                if probeStorage == nil {
                    let storage = NSTextStorage(attributedString: textStorage)
                    let layout = NSLayoutManager()
                    storage.addLayoutManager(layout)
                    probeStorage = storage
                    probeLayout = layout
                }
                guard let layout = probeLayout else { return count }
                while layout.textContainers.count < count {
                    let container = NSTextContainer(size: pageSize)
                    container.lineFragmentPadding = 0
                    layout.addTextContainer(container)
                }
                for container in layout.textContainers { layout.ensureLayout(for: container) }
                if let last = layout.textContainers.last,
                   NSMaxRange(layout.glyphRange(for: last)) >= layout.numberOfGlyphs {
                    return count
                }
            }
            count += 1
            if count > 5000 { return count }  // Emergency brake
        }
    }

    /// Glyph range that sits on the page with this container.
    func glyphRange(forContainerAt index: Int) -> NSRange? {
        guard containers.indices.contains(index) else { return nil }
        layoutManager.ensureLayout(for: containers[index])
        return layoutManager.glyphRange(for: containers[index])
    }

    // MARK: - Saving

    func rtfData() -> Data? {
        textStorage.rtf(
            from: NSRange(location: 0, length: textStorage.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }

    // MARK: - Formatting

    func toggleTrait(_ trait: NSFontTraitMask, in range: NSRange) {
        guard range.length > 0 else { return }
        let manager = NSFontManager.shared
        var allSet = true

        textStorage.enumerateAttribute(.font, in: range) { value, _, _ in
            let font = (value as? NSFont) ?? Self.defaultFont
            if !manager.traits(of: font).contains(trait) { allSet = false }
        }

        textStorage.beginEditing()
        textStorage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            let font = (value as? NSFont) ?? Self.defaultFont
            let updated = allSet
                ? manager.convert(font, toNotHaveTrait: trait)
                : manager.convert(font, toHaveTrait: trait)
            textStorage.addAttribute(.font, value: updated, range: subrange)
        }
        textStorage.endEditing()
    }

    /// Underlining is not a trait of the font but an attribute of its own —
    /// hence a separate path instead of `NSFontTraitMask`.
    func toggleUnderline(in range: NSRange) {
        guard range.length > 0 else { return }
        var allSet = true

        textStorage.enumerateAttribute(.underlineStyle, in: range) { value, _, _ in
            if (value as? Int ?? 0) == 0 { allSet = false }
        }

        textStorage.beginEditing()
        if allSet {
            textStorage.removeAttribute(.underlineStyle, range: range)
        } else {
            textStorage.addAttribute(
                .underlineStyle,
                value: NSUnderlineStyle.single.rawValue,
                range: range
            )
        }
        textStorage.endEditing()
    }

    /// Alignment applies to whole paragraphs — so the range is extended to
    /// the affected paragraphs.
    func setAlignment(_ alignment: NSTextAlignment, in range: NSRange) {
        guard textStorage.length > 0 else { return }
        let clamped = NSRange(
            location: min(range.location, textStorage.length - 1),
            length: min(range.length, textStorage.length - min(range.location, textStorage.length - 1))
        )
        let paragraphRange = (textStorage.string as NSString).paragraphRange(for: clamped)
        guard paragraphRange.length > 0 else { return }

        textStorage.beginEditing()
        textStorage.enumerateAttribute(.paragraphStyle, in: paragraphRange) { value, subrange, _ in
            let style = ((value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle)
                ?? NSMutableParagraphStyle()
            style.alignment = alignment
            textStorage.addAttribute(.paragraphStyle, value: style, range: subrange)
        }
        textStorage.endEditing()
    }

    func setFontSize(_ size: CGFloat, in range: NSRange) {
        guard range.length > 0 else { return }
        textStorage.beginEditing()
        textStorage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            let font = (value as? NSFont) ?? Self.defaultFont
            let updated = NSFontManager.shared.convert(font, toSize: size)
            textStorage.addAttribute(.font, value: updated, range: subrange)
        }
        textStorage.endEditing()
    }
}
