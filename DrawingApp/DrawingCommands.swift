//
//  DrawingCommands.swift
//  DrawingApp
//
//  Created by Assistant on 5/29/26.
//

import SwiftUI

struct DrawingCommands: Commands {
    @FocusedObject var drawingInfo: DrawingInfo?

    var body: some Commands {
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
            
            Toggle("Show Quads", isOn: Binding(
                get: { drawingInfo?.showQuads ?? false },
                set: { newValue in drawingInfo?.showQuads = newValue }
            ))
            .keyboardShortcut("q", modifiers: [.option])
            .disabled(drawingInfo == nil)
        }
    }
}

