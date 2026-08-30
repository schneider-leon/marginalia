//
//  NotebookTextEngine.swift
//  BestNotes
//
//  Der Textfluss eines Notizbuchs.
//
//  Ein einziger `NSTextStorage` laeuft ueber mehrere seitengrosse
//  `NSTextContainer` — genau das Modell, mit dem Textverarbeitungen Seiten
//  umbrechen. Wer auf Seite 2 eine Zeile einfuegt, schiebt den Rest ueber den
//  Seitenrand auf Seite 3; darum kuemmert sich der `NSLayoutManager` von
//  selbst.
//
//  Bewusst TextKit 1: mehrere Container an einem Layout-Manager sind dort der
//  vorgesehene Weg und tragen sowohl die Bearbeitung im NSTextView als auch
//  das Rendern beim Export.
//

import AppKit
import Foundation

@MainActor
final class NotebookTextEngine: NSObject, NSTextStorageDelegate {

    /// Wird nach jeder Aenderung am Text gerufen — die Session markiert
    /// daraufhin ungesicherte Aenderungen und zieht Seiten nach.
    var onEdited: (() -> Void)?

    let textStorage: NSTextStorage
    let layoutManager: NSLayoutManager

    /// Ein Container pro *beschreibbarer* Seite, in Dokumentreihenfolge.
    /// Importierte PDF-Seiten bekommen keinen — der Text fliesst an ihnen
    /// vorbei zur naechsten leeren Seite.
    private(set) var containers: [NSTextContainer] = []

    static let defaultFont = NSFont.systemFont(ofSize: 13)

    init(rtf: Data? = nil) {
        let attributed: NSAttributedString
        if let rtf, let restored = NSAttributedString(rtf: rtf, documentAttributes: nil) {
            attributed = restored
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

    static var defaultAttributes: [NSAttributedString.Key: Any] {
        [.font: defaultFont, .foregroundColor: NSColor.textColor]
    }

    var isEmpty: Bool { textStorage.length == 0 }

    // MARK: - Container

    /// Gleicht Anzahl und Groesse der Container an die beschreibbaren Seiten an.
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

    /// Ob der Text hinter dem letzten Container weiterlaeuft — dann fehlt eine Seite.
    var overflows: Bool {
        guard let last = containers.last else { return textStorage.length > 0 }
        for container in containers {
            layoutManager.ensureLayout(for: container)
        }
        let laid = layoutManager.glyphRange(for: last)
        return NSMaxRange(laid) < layoutManager.numberOfGlyphs
    }

    /// Wie viele Seiten der Text insgesamt braucht — auch ueber die
    /// vorhandenen Container hinaus.
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
                // Probelauf auf einer Kopie, damit der echte Fluss unberuehrt bleibt.
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
            if count > 5000 { return count }  // Notbremse
        }
    }

    /// Zeichenbereich, der auf der Seite mit diesem Container steht.
    func glyphRange(forContainerAt index: Int) -> NSRange? {
        guard containers.indices.contains(index) else { return nil }
        layoutManager.ensureLayout(for: containers[index])
        return layoutManager.glyphRange(for: containers[index])
    }

    // MARK: - Sichern

    func rtfData() -> Data? {
        textStorage.rtf(
            from: NSRange(location: 0, length: textStorage.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }

    // MARK: - Formatierung

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
