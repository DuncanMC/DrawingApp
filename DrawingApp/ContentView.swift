//
//  ContentView.swift
//  DrawingApp
//
//  Created by Duncan Champney on 5/1/26.
//  Copyright (c) 2026 Duncan Champney. All rights reserved.
//

import SwiftUI
import Combine

@MainActor struct ContentView: View {
    @ObservedObject var drawingInfo: DrawingInfo
    @Environment(\.undoManager) var undoManager

    var viewModel: ViewModel

    var toggleAlignment: Alignment {
    #if os(macOS)
            return .leading
    #else
            return .trailing
    #endif

    }

    var body: some View {
        VStack {
            DrawingView(
                drawingInfo: drawingInfo,
                onTap: { location, event in
                    viewModel.handleTap(location: location, modifiers: event.modifierKeys)
                },
                onDoubleTap: { location, event in
                    viewModel.handleDoubleTap(location: location)
                },
                onDragBegan: { location, event in
                    viewModel.handleDragBegan(location: location, event: event)
                },
                onDragChanged: { location, event in
                    viewModel.handleDragChanged(location: location, event: event)
                },
                onDragEnded: { location, event in
                    viewModel.handleDragEnded()
                }
            )
                .frame(width: DrawingInfo.defaultSize.width, height: DrawingInfo.defaultSize.height)
                .border(Color.blue, width: 4)
                .aspectRatio(drawingInfo.imageSize, contentMode: .fit)
            HStack(spacing: 20) {
                //                    Spacer()

                ColorPicker("Curve color", selection: $drawingInfo.currentColor)
                    .frame(maxWidth: 150)

                Button("Delete point") {
                    viewModel.handleDeletePoint()
                }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(!drawingInfo.enableDeletePointButton)

                VStack(alignment: .center)   {
                    Text("Thickness")
                    Slider(value: $drawingInfo.currentThickness, in: minThickness...maxThickness)
                }
                .frame(maxWidth: 150)
                .padding(.trailing, 10)
//                .onChange(of: drawingInfo.lineThickness) {
//                    //print("Line thickness = \(drawingInfo.lineThickness)")
//                }

                VStack(alignment: .center)   {
                    Text("Line hardness")
                    Slider(value: $drawingInfo.lineHardness, in: 0...2)
                }
                .frame(maxWidth: 150)
                .onChange(of: drawingInfo.lineHardness) {
                    //print("lineHardness = \(drawingInfo.lineHardness). Computed hardness = \(drawingInfo.hardness)")
                }
                //                    Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding([.top, .bottom], 10)
        }
        #if os(iOS)
        .background {
            VStack {
                Button("") { drawingInfo.cutSelectedPoints() }
                    .keyboardShortcut("x", modifiers: .command)
                    .disabled(drawingInfo.selectedPoints.isEmpty)
                Button("") { drawingInfo.copySelectedPoints() }
                    .keyboardShortcut("c", modifiers: .command)
                    .disabled(drawingInfo.selectedPoints.isEmpty)
                Button("") { drawingInfo.pastePoints() }
                    .keyboardShortcut("v", modifiers: .command)
                    .disabled(!drawingInfo.canPaste)
                Button("") { drawingInfo.selectAll() }
                    .keyboardShortcut("a", modifiers: .command)
                Button("") { drawingInfo.selectedPoints = [] }
                    .keyboardShortcut("d", modifiers: .command)
                    .disabled(drawingInfo.selectedPoints.isEmpty)
            }
            .frame(width: 0, height: 0)
            .opacity(0)
        }
        #endif
        .focusedSceneObject(drawingInfo)
        .onAppear {
            drawingInfo.undoManager = undoManager
        }
        .onReceive(drawingInfo.objectWillChange) { _ in
            if !drawingInfo.suppressUndo {
                drawingInfo.registerUndo()
            }
        }
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Menu("Edit", systemImage: "scissors") {
                    Button("Cut") {
                        drawingInfo.cutSelectedPoints()
                    }
                    .disabled(drawingInfo.selectedPoints.isEmpty)

                    Button("Copy") {
                        drawingInfo.copySelectedPoints()
                    }
                    .disabled(drawingInfo.selectedPoints.isEmpty)

                    Button("Paste") {
                        drawingInfo.pastePoints()
                    }
                    .disabled(!drawingInfo.canPaste)


                    Button("Select All") {
                        drawingInfo.selectAll()
                    }
                    Button("Deselect All") {
                        drawingInfo.selectedPoints = []
//                      //drawingMode = .idle
                    }
                    .disabled(drawingInfo.selectedPoints.isEmpty)

                    Divider()

                    Button("Delete Point", role: .destructive) {
                        drawingInfo.deletePoints()
                    }
                    .disabled(!drawingInfo.enableDeletePointButton)

                    Button("Delete Entire Curve", role: .destructive) {
                        drawingInfo.deletePoints(deleteEntireCurve: true)
                    }
                    .disabled(!drawingInfo.enableDeletePointButton)

                    Toggle("Close Curve", isOn: Binding(
                        get: {  drawingInfo.selectedCurveIsClosed },
                        set: {  newValue in drawingInfo.selectedCurveIsClosed = newValue }
                    ))
                    .disabled(drawingInfo.selectedPoints.count != 1)
                    // xxx
                    Button("Join Curves") {
                        drawingInfo.joinCurves()
                    }
                    .disabled(drawingInfo.enableJoinCurves != true)

                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Menu("View Options", systemImage: "eye") {
                    Toggle("Smooth Curves", isOn: $drawingInfo.smoothCurves)
                    Toggle("Show Smoothing Points", isOn: $drawingInfo.showSmoothingPoints)
                    Toggle("Show Control Points", isOn: $drawingInfo.showControlPoints)
                    Toggle("Show Quads", isOn: $drawingInfo.showQuads)
                }
            }
        }
        #endif
    }

    init(drawingInfo: DrawingInfo) {
        self.drawingInfo = drawingInfo
        self.viewModel = .init(drawingInfo: drawingInfo)
    }
}

#Preview {
    ContentView(drawingInfo: DrawingInfo(title: "foo", text: "bar"))
}
