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
├── overlays.json      # editierbare Textboxen & Bildplatzierungen pro Seite
├── assets/            # eingefuegte Originalbilder (unveraendert)
└── thumbnails/        # Cache, regenerierbar, nicht versionsrelevant
```

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

### 4. Zwei Arten von „Annotation“ — bewusst getrennt

| | Speicherung | Warum |
|---|---|---|
| Highlight, Freihand, Notizzettel auf PDF-Seiten | echte `PDFAnnotation` in `content.pdf` | PDFKit kann das nativ, ist standardkonform und ueberlebt den Export ohne Zutun |
| Getippte Textbloecke, platzierte Bilder | eigenes Modell in `overlays.json` | bleibt beliebig editierbar; wird beim Export ins PDF **eingebrannt** |

Export (Schritt 7) = Kopie von `content.pdf` anlegen → Overlays per Core Graphics in
die jeweilige Seite rendern → Annotationen bleiben, wo sie sind → fertige PDF schreiben.
Der Nutzer bekommt eine flache, ueberall lesbare PDF; die Arbeitskopie bleibt editierbar.

### 5. SwiftData ist der Index, nicht der Speicher

SwiftData haelt nur die Bibliotheksstruktur: Ordner, Notizbuch-Eintraege, Titel,
Zeitstempel, Sortierung, zuletzt geoeffnete Tabs. Der Inhalt bleibt im Dateisystem.
Damit gilt: eine kaputte oder migrierte Datenbank kostet nie Notizen, und ein
Notizbuch laesst sich per Drag & Drop aus dem Finder weitergeben. Referenziert wird
ueber **security-scoped bookmarks** (Sandbox-tauglich, ueberlebt Umbenennen/Verschieben)
mit dem Pfad als Fallback.

---

## Stand / Roadmap

| Schritt | Inhalt | Status |
|---|---|---|
| 1 | Projekt-Setup, Struktur, Git, README | ✅ |
| 2 | Minimaler PDF-Viewer (laden, anzeigen, Zoom/Scroll) | ✅ |
| 3 | Annotationen: Highlight, Freihand, Textkommentar + Export | offen |
| 4 | Sidebar mit Ordnerbaum (Dummy-Daten) | offen |
| 5 | Tab-Leiste fuer mehrere offene Dokumente | offen |
| 6 | `.bestnote`-Format + SwiftData-Bibliothek | offen |
| 7 | Leere Seiten, Textoverlays, Einbrennen beim Export | offen |
| 8 | Bilder einfuegen (Drag & Drop / Dateiauswahl) | offen |
| 9 | Persistenz haerten, Fehlerbehandlung, Refactoring | offen |

## Build

```
xcodebuild -project BestNotes/BestNotes.xcodeproj -scheme BestNotes -destination 'platform=macOS' build
```
