//
//  AnnotationToolbar.swift
//  BestNotes
//
//  Werkzeugleiste ueber der Seitenansicht. Bewusst kein Toolbar-Item:
//  die Werkzeugauswahl gehoert zum Dokument, nicht zum Fenster, und die
//  macOS-Toolbar wuerde bei schmalen Fenstern anfangen einzuklappen.
//

import SwiftUI

struct AnnotationToolbar: View {
    @Bindable var session: DocumentSession

    var body: some View {
        HStack(spacing: 12) {
            DocumentModePicker(session: session)

            Divider().frame(height: 18)

            toolPicker
            Divider().frame(height: 18)
            styleControls
            Spacer(minLength: 0)
            historyControls
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var toolPicker: some View {
        Picker("Werkzeug", selection: $session.activeTool) {
            ForEach(AnnotationTool.allCases) { tool in
                Image(systemName: tool.symbol)
                    .help(tool.label)
                    .tag(tool)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    @ViewBuilder
    private var styleControls: some View {
        switch session.activeTool {
        case .highlight:
            ColorPicker("Farbe", selection: $session.style.highlightColor, supportsOpacity: false)
                .labelsHidden()
            Text("Markierung")
                .font(.callout)
                .foregroundStyle(.secondary)

        case .ink:
            ColorPicker("Farbe", selection: $session.style.inkColor, supportsOpacity: false)
                .labelsHidden()
            Slider(value: $session.style.inkWidth, in: 0.5...12) {
                Text("Staerke")
            }
            .frame(width: 120)
            Text("\(session.style.inkWidth, format: .number.precision(.fractionLength(1))) pt")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)

        case .text:
            ColorPicker("Farbe", selection: $session.style.textColor, supportsOpacity: false)
                .labelsHidden()
            Stepper(value: $session.style.textSize, in: 8...48, step: 1) {
                Text("\(Int(session.style.textSize)) pt")
                    .font(.callout)
                    .monospacedDigit()
            }
            .fixedSize()

        case .eraser:
            Text("Klicke auf eine Annotation, um sie zu entfernen.")
                .font(.callout)
                .foregroundStyle(.secondary)

        case .select:
            Text("Text auswaehlen und kopieren.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var historyControls: some View {
        HStack(spacing: 4) {
            if session.hasUnsavedChanges {
                Text("Nicht gesichert")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Button(action: session.undo) {
                Label("Widerrufen", systemImage: "arrow.uturn.backward")
            }
            .disabled(!session.canUndo)

            Button(action: session.redo) {
                Label("Wiederholen", systemImage: "arrow.uturn.forward")
            }
            .disabled(!session.canRedo)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
    }
}
