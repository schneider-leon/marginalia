//
//  AnnotationToolbar.swift
//  marginalia
//
//  Toolbar above the page view. Deliberately not a toolbar item: tool
//  selection belongs to the document, not the window, and the macOS
//  toolbar would start collapsing in narrow windows.
//

import SwiftUI

struct AnnotationToolbar: View {
    @Bindable var session: DocumentSession

    var body: some View {
        ToolStrip {
            DocumentModePicker(session: session)

            Divider().frame(height: 18)

            InsertToolGroup(session: session)

            Divider().frame(height: 18)

            HStack(spacing: 6) {
                toolPicker
                ToolGroup {
                    InsertImageButton(session: session)
                }
            }
            Divider().frame(height: 18)
            styleControls
            Spacer(minLength: 0)
            historyControls
        }
    }

    private var toolPicker: some View {
        Picker("Tool", selection: $session.activeTool) {
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
            ColorPicker("Color", selection: $session.style.highlightColor, supportsOpacity: false)
                .labelsHidden()
            Text("Highlight")
                .font(.callout)
                .foregroundStyle(.secondary)

        case .ink:
            ColorPicker("Color", selection: $session.style.inkColor, supportsOpacity: false)
                .labelsHidden()
            Slider(value: $session.style.inkWidth, in: 0.5...12) {
                Text("Width")
            }
            .frame(width: 120)
            Text("\(session.style.inkWidth, format: .number.precision(.fractionLength(1))) pt")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)

        case .text:
            ColorPicker("Note Color", selection: $session.style.noteColor, supportsOpacity: false)
                .labelsHidden()
                .help("Background of the note")
            ColorPicker("Text Color", selection: $session.style.textColor, supportsOpacity: false)
                .labelsHidden()
                .help("Text color")
            Stepper(value: $session.style.textSize, in: 8...48, step: 1) {
                Text("\(Int(session.style.textSize)) pt")
                    .font(.callout)
                    .monospacedDigit()
            }
            .fixedSize()

            Text("Return finishes, Shift-Return starts a new line.")
                .font(.callout)
                .foregroundStyle(.secondary)

        case .eraser:
            Text("Click an annotation to remove it.")
                .font(.callout)
                .foregroundStyle(.secondary)

        case .select:
            Text("Select and copy text.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var historyControls: some View {
        HStack(spacing: 4) {
            if session.hasUnsavedChanges {
                Text("Not Saved")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ToolGroup {
                Button(action: session.undo) {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .frame(width: 24, height: 20)
                }
                .disabled(!session.canUndo)

                ToolGroupDivider()

                Button(action: session.redo) {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                        .frame(width: 24, height: 20)
                }
                .disabled(!session.canRedo)
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
    }
}
