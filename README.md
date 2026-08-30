# BestNotes

Native macOS-App als Alternative zu Goodnotes — mit dem Fokus auf **getippten** Notizen,
PDF-Import und PDF-Annotation. Kein Handschrift-Input.

- **Sprache/UI:** Swift 5 (Compiler 6.x), SwiftUI mit AppKit-Interop
- **PDF:** PDFKit (Rendering, Annotationen, Export)
- **Metadaten/Bibliothek:** SwiftData
- **Deployment Target:** macOS 15.0
- **Sandbox:** aktiv, `com.apple.security.files.user-selected.read-write`

---

## Projektstruktur

```
bestNotes/
├── README.md
├── .gitignore
└── BestNotes/                      # Xcode-Projektordner
    ├── BestNotes.xcodeproj
    └── BestNotes/                  # Target-Quellen (file-system-synchronized group)
        ├── App/                    # Einstiegspunkt, Szenen, Menuebefehle, App-State
        ├── Models/                 # SwiftData-Modelle + Notizbuch-Dokumentformat
        ├── Features/
        │   ├── Library/            # Sidebar: Ordner-/Notizbuchbaum        (Schritt 4)
        │   ├── Tabs/               # Tab-Leiste fuer offene Dokumente      (Schritt 5)
        │   ├── Viewer/             # PDF-Anzeige + Annotationswerkzeuge    (Schritt 2/3)
        │   └── Editor/             # Textseiten, Bildplatzierung           (Schritt 7/8)
        ├── PDFKitBridge/           # NSViewRepresentable-Wrapper, PDFView-Subklassen
        ├── Services/               # Datei-I/O, Export, Thumbnails
        ├── Support/                # Extensions, Hilfstypen, Konstanten
        └── Assets.xcassets
```

Das Xcode-Projekt nutzt eine *file-system-synchronized group* (`objectVersion = 77`).
Neue Dateien und Ordner unter `BestNotes/BestNotes/` werden automatisch Teil des Targets —
es muss nichts manuell in Xcode hinzugefuegt werden, und die `project.pbxproj` bleibt
weitgehend merge-konfliktfrei.

Kehrseite: die Gruppe zieht *alle* Dateien ins Target, auch `.gitkeep`. Deshalb steht
`EXCLUDED_SOURCE_FILE_NAMES = ".gitkeep"` in den Projekt-Build-Settings — sonst
kollidieren gleichnamige Platzhalter beim Kopieren in `Contents/Resources`.

---

## Architekturueberblick

### 1. Schichten

```
        SwiftUI (Chrome)                     AppKit/PDFKit (Canvas)
 ┌───────────────────────────────┐   ┌──────────────────────────────────┐
 │ Sidebar · Tab-Leiste          │   │ PDFView (Scroll, Zoom, Auswahl)  │
 │ Toolbar · Inspector · Dialoge │◄─►│ PDFAnnotation-Werkzeuge          │
 └───────────────────────────────┘   └──────────────────────────────────┘
                 ▲                                   ▲
                 │        DocumentSession            │
                 └───────── (ObservableObject) ──────┘
                                   │
             ┌─────────────────────┴────────────────────┐
             │                                          │
   SwiftData (Bibliotheks-Index)            Dateisystem (.bestnote-Pakete, PDFs)
```

### 2. SwiftUI ↔ PDFKit

`PDFView` ist eine `NSView` mit eigenem, imperativem Zustand (Scrollposition, Zoom,
aktuelle Seite, Auswahl). Der Versuch, das deklarativ aus SwiftUI zu steuern, endet
zuverlaessig in Update-Schleifen. Deshalb:

- **`NSViewRepresentable` bleibt duenn.** `makeNSView` baut die `PDFView` einmal auf,
  `updateNSView` gleicht nur wenige, explizit versionierte Werte ab (z. B. aktives
  Werkzeug). Es wird nie das ganze `PDFDocument` neu gesetzt, solange es dasselbe ist.
- **Der Zustand lebt in einer `DocumentSession`-Klasse** (`@Observable`), nicht in
  `@State` der Wrapper-View. Die Session haelt `PDFDocument`, aktives Werkzeug,
  Undo-Manager und Dirty-Flag. SwiftUI liest daraus; die `PDFView` schreibt darauf
  ueber den `Coordinator`.
- **Kommandos statt Bindings:** Aktionen wie „springe zu Seite 12“ oder „Zoom
  zuruecksetzen“ laufen als imperative Methodenaufrufe auf der Session, die der
  Coordinator an die `PDFView` weiterreicht — nicht als Zustandsdiffs.
- **Eigene `PDFView`-Subklasse** fuer Maus-/Trackpad-Events der Annotationswerkzeuge
  (Highlight ziehen, Freihandstrich). PDFKit bietet dafuer keine Hooks, also
  `mouseDown/Dragged/Up` ueberschreiben und Punkte per `convert(_:to page:)` in
  Seitenkoordinaten umrechnen.
- Ein `PDFDocument` gehoert immer genau **einer** Session. Beim Tab-Wechsel wird die
  `PDFView` nicht wiederverwendet, damit Zoom-/Scrollzustand pro Tab erhalten bleibt.

### 3. Notizbuch-Datenformat (`.bestnote`)

Ein Notizbuch ist ein **Paket** (Ordner mit `NSFileWrapper`, im Finder als eine Datei
sichtbar):

```
Mathe-VL.bestnote/
├── info.json          # Schemaversion, Titel, IDs, Seitenreihenfolge, Seitentypen
├── content.pdf        # kanonischer Seitentraeger: importierte + leere Seiten
├── body.rtf           # der durchlaufende Text des Notizbuchs
├── overlays.json      # Bildplatzierungen pro Seite
└── assets/            # eingefuegte Originalbilder (unveraendert)
```

Die Pakete liegen im Sandbox-Container unter `Documents/Library/<uuid>.bestnote`.
Der Dateiname kommt aus der Notizbuch-ID, nicht aus dem Titel: Umbenennen soll
keine Datei verschieben, und zwei gleichnamige Notizbuecher duerfen nebeneinander
existieren. `.bestnote` ist in `Info.plist` als exportierter UTType deklariert und
konform zu `com.apple.package` — der Finder zeigt das Verzeichnis als eine Datei.

Beide JSON-Dateien haben eine **explizit geschriebene** Kodierung: Swifts
synthetisierte Enum-Form (`{"text": {"_0": …}}`) und `CGRect` als
`[[x,y],[w,h]]` waeren beide schlecht les- und schlecht versionierbar.
`OverlayContent` bekommt stattdessen einen `type`-Diskriminator, `frame` benannte
Felder.

**Warum ein Paket und nicht eine einzelne PDF?**
Eine reine PDF koennte fast alles per PDF-Annotation abbilden, aber getippter Text
waere dann in `FreeText`-Annotationen gefangen: kein sauberes Rich-Text-Modell, kein
verlaessliches Reflow, und jeder externe PDF-Reader duerfte daran herumeditieren.
Umgekehrt waere „alles in SwiftData/eine Datenbank“ teuer beim Import grosser PDFs
und wuerde den Export zu einem vollstaendigen Neu-Rendering machen.

Der Mittelweg: **`content.pdf` ist die Wahrheit ueber Seiten und Geometrie**,
`overlays.json` ist die Wahrheit ueber alles, was noch editierbar bleiben soll.

**Warum ein Paket und nicht eine Zip-Datei?** `NSFileWrapper` erlaubt inkrementelles
Schreiben — beim Speichern wird nur der geaenderte Teilbaum ersetzt, statt ein
100-MB-Archiv neu zu packen.

**Warum ist der Import-PDF unveraendert eingebettet?** Beim Import wird die Datei
byteweise kopiert, nicht neu encodiert: Textebene, Lesezeichen und Dateigroesse
bleiben erhalten.

### 3a. Getippter Text: ein Fluss ueber viele Seiten

Ein Notizbuch hat **einen** Textspeicher, nicht pro Seite einen Kasten. Ein
`NSTextStorage` laeuft ueber mehrere seitengrosse `NSTextContainer` an einem
gemeinsamen `NSLayoutManager` — das Modell, mit dem Textverarbeitungen Seiten
umbrechen. Wer auf Seite 2 eine Zeile einfuegt, schiebt den Rest ueber den
Seitenrand auf Seite 3.

Bewusst TextKit 1: mehrere Container an einem Layout-Manager sind dort der
vorgesehene Weg, und derselbe Layout-Manager traegt beides — die Bearbeitung im
`NSTextView` und das Zeichnen beim Export.

Der Fluss laeuft nur ueber **leere** Seiten. Importierte PDF-Seiten haben keinen
Container; der Text fliesst an ihnen vorbei zur naechsten leeren Seite. Laeuft er
hinter die letzte Seite, waechst automatisch eine nach. Umgekehrt wird nie
automatisch geloescht — eine Seite, die der Nutzer angelegt hat, verschwindet
nicht von selbst.

Folge daraus: eine *mitten* in den Fluss eingefuegte Seite bleibt nicht leer, der
Text rueckt nach. Eine wirklich leere Seite bekommt man am Ende des Notizbuchs.

### 3b. Bilder

Bilder liegen als Overlay ueber der Seite, mit Rahmen in PDF-Punkten. Die
Originaldatei wandert unveraendert nach `assets/`; `overlays.json` haelt nur
Dateinamen, Rahmen und Deckkraft. Verschieben und Skalieren aendern also nie
die Bilddaten.

Die Bedienung sitzt in einer eigenen `NSView` **ueber** der Textansicht. Deren
`hitTest` meldet sich nur fuer Punkte auf einem Bild oder einem Anfasser
zustaendig und gibt sonst `nil` zurueck — der Klick faellt dann durch und landet
im Text. Eine SwiftUI-Ueberlagerung koennte das nicht so genau trennen.

Drops nimmt dagegen die *Hintergrund*ansicht entgegen, weil die immer getroffen
wird. Damit Dateien nicht vorher in der Textansicht landen, nimmt die nur noch
Text-Drops an.

### 4. Zwei Arten von „Annotation“ — bewusst getrennt

| | Speicherung | Warum |
|---|---|---|
| Highlight, Freihand, Notizzettel auf PDF-Seiten | echte `PDFAnnotation` in `content.pdf` | PDFKit kann das nativ, ist standardkonform und ueberlebt den Export ohne Zutun |
| Getippter Fliesstext | `body.rtf` + Layout zur Laufzeit | bleibt beliebig editierbar und umbruchfaehig; wird beim Export ins PDF **eingebrannt** |
| Platzierte Bilder | `overlays.json` + Originaldatei in `assets/` | bleibt beliebig verschiebbar und skalierbar; wird beim Export ins PDF **eingebrannt** |

Export = neues PDF-Dokument aufbauen: pro Seite erst die Originalseite samt ihrer
PDF-Annotationen zeichnen, dann Hilfslinien und den Text dieser Seite darueber.
Der Text wird dabei als **echter Text** gezeichnet, nicht als Bild — Suchen und
Kopieren funktionieren im Ergebnis weiter. Die Arbeitskopie im Paket bleibt
editierbar.

### 5. SwiftData ist der Index, nicht der Speicher

`LibraryEntry` haelt nur die Bibliotheksstruktur: Name, Art, Ordnung, Elternschaft,
Zeitstempel. Der Inhalt bleibt im Dateisystem. Damit kostet eine kaputte oder
migrierte Datenbank nie Notizen.

Referenziert wird ueber die **`id` des Eintrags**, nicht ueber gespeicherte Pfade:
ein Eintrag findet seine Datei als `Library/<id>.bestnote` bzw. `Library/<id>.pdf`.
Keine Bookmarks, keine toten Pfade.

**Importierte PDFs werden kopiert, nicht verknuepft.** Die Bibliothek besitzt ihre
Dokumente selbst. Das erspart security-scoped bookmarks samt Entitlement, ueberlebt
Verschieben und Umbenennen des Originals, und Annotationen landen in der Kopie statt
in der Datei des Nutzers. Preis: doppelter Speicherplatz.

`LibraryStore` ist die Fassade davor und liefert den Views weiterhin nur einen Baum
aus `LibraryNode`-Werttypen — die Sidebar aus Schritt 4 blieb unveraendert.

---

## Stand / Roadmap

| Schritt | Inhalt | Status |
|---|---|---|
| 1 | Projekt-Setup, Struktur, Git, README | ✅ |
| 2 | Minimaler PDF-Viewer (laden, anzeigen, Zoom/Scroll) | ✅ |
| 3 | Annotationen: Highlight, Freihand, Textkommentar + Export | ✅ |
| 4 | Sidebar mit Ordnerbaum (Dummy-Daten) | ✅ |
| 5 | Tab-Leiste fuer mehrere offene Dokumente | ✅ |
| 6a | `.bestnote`-Format: Lesen, Schreiben, Reparatur | ✅ |
| 6b | SwiftData-Bibliothek, Notizbuecher in der Sidebar | ✅ |
| 7 | Leere Seiten, durchlaufender Text, Einbrennen beim Export | ✅ |
| 8 | Bilder einfuegen (Drag & Drop / Dateiauswahl) | ✅ |
| 9 | Persistenz haerten, Fehlerbehandlung, Refactoring | offen |

## Tastenkuerzel

| Kuerzel | Aktion |
|---|---|
| ⌘O | PDF importieren |
| ⌘S / ⇧⌘E | Sichern / als PDF exportieren |
| ⌘Z / ⇧⌘Z | Widerrufen / Wiederholen |
| ⌃1–⌃5 | Werkzeug: Auswahl, Markieren, Freihand, Kommentar, Radierer |
| ⌘1–⌘9 | Tab wechseln |
| ⇧⌘[ / ⇧⌘] | Vorheriger / naechster Tab |
| ⌘W | Tab schliessen |
| ⌘+ / ⌘- / ⌘0 | Zoom |
| ⌥⌘↑ / ⌥⌘↓ | Seite zurueck / vor |

## Build

```
xcodebuild -project BestNotes/BestNotes.xcodeproj -scheme BestNotes -destination 'platform=macOS' build
```
