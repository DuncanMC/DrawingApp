//
//  DrawingCommands.swift
//  DrawingApp
//
//  Created by Assistant on 5/29/26.
//

import SwiftUI

struct DrawingCommands: Commands {
    @FocusedObject var drawingInfo: DrawingInfo?

    // MacOS menus
    var body: some Commands {
        CommandGroup(replacing: .pasteboard) {
            Button("Cut") {
                drawingInfo?.cutSelectedPoints()
            }
            .keyboardShortcut("x", modifiers: .command)
            .disabled(drawingInfo?.selectedPoints.isEmpty != false)

            Button("Copy") {
                drawingInfo?.copySelectedPoints()
            }
            .keyboardShortcut("c", modifiers: .command)
            .disabled(drawingInfo?.selectedPoints.isEmpty != false)

            Button("Paste") {
                drawingInfo?.pastePoints()
            }
            .keyboardShortcut("v", modifiers: .command)

            Button("Select All") {
                drawingInfo?.selectAll()
            }
            .disabled(!(drawingInfo?.curves.isEmpty == false))
            .keyboardShortcut("a", modifiers: .command)
            

            Button("Deselect All") {
                drawingInfo?.selectedPoints = []
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(drawingInfo?.selectedPoints.isEmpty == true)
            
            Divider()

            Toggle("Transform Selection", isOn: Binding(
                get: {  drawingInfo?.transformSelection ?? false },
                set: {  newValue in drawingInfo?.transformSelection = newValue } ))
            .disabled(drawingInfo?.drawingMode != .editingCurve || drawingInfo?.selectedPoints.count ?? 0 < 2)
            .keyboardShortcut("t", modifiers: .command)
        }

        CommandGroup(after: .pasteboard) {
            Button(drawingInfo?.deleteSelectedPointString ?? "Delete Selected Point") {
                drawingInfo?.deletePoints()
            }
            .keyboardShortcut(.delete, modifiers: [])
            .disabled(drawingInfo?.enableDeletePointButton != true)
            Button(drawingInfo?.deleteSelectedCurveString ?? "Delete Selected Curve") {
                drawingInfo?.deletePoints(deleteEntireCurve: true)
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(drawingInfo?.enableDeletePointButton != true)
            
            Toggle("Close Curve", isOn: Binding(
                get: {  drawingInfo?.selectedCurveIsClosed ?? false },
                set: {  newValue in drawingInfo?.selectedCurveIsClosed = newValue }
            ))
            .disabled(!(drawingInfo?.singleCurveSelected ?? false))

            Section("Arrange Curves") {
                Button("Move Forward") {
                    drawingInfo?.moveCurveForward()
                }
                .keyboardShortcut(.pageUp, modifiers: [])
                .disabled(drawingInfo?.singleCurveSelectedAndNotLast != true)

                Button("Move to Front") {
                    drawingInfo?.bringCurveToFront()
                }
                .keyboardShortcut(.home, modifiers: [])
                .disabled(drawingInfo?.singleCurveSelectedAndNotLast != true)

                Button("Move Backward") {
                    drawingInfo?.moveCurveBackward()
                }
                .keyboardShortcut(.pageDown, modifiers: [])
                .disabled(drawingInfo?.singleCurveSelectedAndNotFirst != true)

                Button("Move to Back") {
                    drawingInfo?.sendCurveToBack()
                }
                .keyboardShortcut(.end, modifiers: [])
                .disabled(drawingInfo?.singleCurveSelectedAndNotFirst != true)
            }


            Button("Join Curves") {
                drawingInfo?.joinCurves()
            }
            .keyboardShortcut("j", modifiers: [.command])
            .disabled(drawingInfo?.enableJoinCurves != true)

        }

        CommandGroup(before: .toolbar) {
            Toggle("Smooth curves", isOn: Binding(
                get: { drawingInfo?.smoothCurves ?? false },
                set: { newValue in drawingInfo?.smoothCurves = newValue }
            ))
            .keyboardShortcut("s", modifiers: [.option])
            .disabled(drawingInfo == nil)
            
            Toggle("Show Smoothing Points", isOn: Binding(
                get: { drawingInfo?.showSmoothingPoints ?? false },
                set: { newValue in drawingInfo?.showSmoothingPoints = newValue }
            ))
            .keyboardShortcut("s", modifiers: [.shift,.option])
            .disabled(drawingInfo == nil)

            Toggle("Show Control Points", isOn: Binding(
                get: { drawingInfo?.showControlPoints ?? false },
                set: { newValue in drawingInfo?.showControlPoints = newValue }
            ))
            .keyboardShortcut("c", modifiers: [.option])
            .disabled(drawingInfo == nil)

            Toggle("Show Grid Lines", isOn: Binding(
                get: { drawingInfo?.showGridLines ?? false },
                set: { newValue in drawingInfo?.showGridLines = newValue }
            ))
            .keyboardShortcut("g", modifiers: [.option])
            .disabled(drawingInfo == nil)

            //showGridLines
            
            Toggle("Show Quads", isOn: Binding(
                get: { drawingInfo?.showQuads ?? false },
                set: { newValue in drawingInfo?.showQuads = newValue }
            ))
            .keyboardShortcut("q", modifiers: [.option])
            .disabled(drawingInfo == nil)
        }
    }
}

