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
    
    @State private var showSettings = false
    

    var viewModel: ViewModel

    var toggleAlignment: Alignment {
    #if os(macOS)
            return .leading
    #else
            return .trailing
    #endif

    }

    
    var body: some View {
        ZStack {
            VStack {
                DrawingView(
                    drawingInfo: drawingInfo,
                    onTap: { location, event in
                        viewModel.handleTap(location: location, modifiers: event.modifierKeys)
                    },
                    onDoubleTap: { location, event in
                        viewModel.handleDoubleTap(location: location)
                    },
                    onTwoFingerTap: { location, event in
                        viewModel.handleTwoFingerTap(location: location)
                    },
                    onDragBegan: { location, event in
                        viewModel.handleDragBegan(location: location, event: event)
                    },
                    onDragChanged: { location, event in
                        viewModel.handleDragChanged(location: location, event: event)
                    },
                    onDragEnded: { location, event in
                        viewModel.handleDragEnded()
                    },
                    onPinchRotateBegan: { center in
                        viewModel.handlePinchRotateBegan(center: center)
                    },
                    onPinchRotateChanged: { scale, rotation, center in
                        // TODO: Put test here to ignore pinch/rotate when in transform mode?
                        viewModel.handlePinchRotateChanged(scale: scale, rotation: rotation, center: center)
                    },
                    onPinchRotateEnded: {
                        viewModel.handlePinchRotateEnded()
                    },
                    onShake: { [weak undoManager] in
                        undoManager?.undo()
                    }
                )
                .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
                    viewModel.handleArrowKey(press)
                    return .handled
                }
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
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            print("Button tapped")
                            showSettings = true
                        } label:  {
                            Image(systemName: "gear")
                                .resizable(resizingMode: .stretch)
                                .frame(width: 30, height: 30)
                        }
                        .padding([.trailing, .bottom])
                        .buttonStyle(.borderless)

                    }
                }
            #endif
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(doneButtonuttonAction: { showSettings = false } )
        }
        #if os(iOS)
        // MARK: hidden buttons for keyboard shortcuts.
        .background {
            VStack {
                Button("") { undoManager?.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!(undoManager?.canUndo ?? false))
                Button("") { undoManager?.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!(undoManager?.canRedo ?? false))
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
                Button("") { drawingInfo.deletePoints(deleteEntireCurve: true) }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(!drawingInfo.enableDeletePointButton)
                // Transform Selection
                Button("") {drawingInfo.transformSelection.toggle()}
                .disabled(drawingInfo.drawingMode != .editingCurve || drawingInfo.selectedPoints.count ?? 0 < 2)
                .keyboardShortcut("t", modifiers: .command)

                //Show control points
                Button("Show Control Points (⌥C)") { drawingInfo.showControlPoints.toggle() }
                    .keyboardShortcut("c", modifiers: .option)
                
                //Smooth Curves
                Button("Smooth Curves (⌥S)") { drawingInfo.smoothCurves.toggle() }
                    .keyboardShortcut("s", modifiers: .option)


                Button("Show Smoothing Points (⌥⇧S)") { drawingInfo.showSmoothingPoints.toggle() }
                    .keyboardShortcut("s", modifiers: [.option, .shift])
                //⌥
                Button("Show Quads (⌥Q)") { drawingInfo.showQuads.toggle() }
                    .keyboardShortcut("q", modifiers: [.option])


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
                    Button("Undo  (⌘Z)") {
                        undoManager?.undo()
                    }
                    .disabled(!(undoManager?.canUndo ?? false))

                    Button("Redo (⌘Shift+Z)") {
                        undoManager?.redo()
                    }
                    .disabled(!(undoManager?.canRedo ?? false))

                    Divider()

                    Button("Cut (⌘X)") {
                        drawingInfo.cutSelectedPoints()
                    }
                    .disabled(drawingInfo.selectedPoints.isEmpty)

                    Button("Copy (⌘C)") {
                        drawingInfo.copySelectedPoints()
                    }
                    .disabled(drawingInfo.selectedPoints.isEmpty)

                    Button("Paste (⌘P)") {
                        drawingInfo.pastePoints()
                    }
                    .disabled(!drawingInfo.canPaste)

                    Button("Select All (⌘A)") {
                        drawingInfo.selectAll()
                    }
                    Toggle("Transform Selection (⌘T)", isOn: Binding(
                        get: {  drawingInfo.transformSelection},
                        set: {  newValue in drawingInfo.transformSelection = newValue } ))
                    .disabled(drawingInfo.drawingMode != .editingCurve || drawingInfo.selectedPoints.count ?? 0 < 2)

                    Button("Deselect All (⌘D)") {
                        drawingInfo.selectedPoints = []
                    }
                    .disabled(drawingInfo.selectedPoints.isEmpty)

                    Divider()

                    Button("Delete Point (⌦)", role: .destructive) {
                        drawingInfo.deletePoints()
                    }
                    .disabled(!drawingInfo.enableDeletePointButton)

                    Button("Delete Entire Curve (⌘⌦)", role: .destructive) {
                        drawingInfo.deletePoints(deleteEntireCurve: true)
                    }
                    .disabled(!drawingInfo.enableDeletePointButton)

                    Toggle("Close Curve", isOn: Binding(
                        get: {  drawingInfo.selectedCurveIsClosed },
                        set: {  newValue in drawingInfo.selectedCurveIsClosed = newValue }
                    ))
                    .disabled(!drawingInfo.singleCurveSelected)
                    // xxx
                    Button("Join Curves") {
                        drawingInfo.joinCurves()
                    }
                    .disabled(drawingInfo.enableJoinCurves != true)

                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Menu("View Options", systemImage: "eye") {
                    Toggle("Smooth Curves (⌥S)", isOn: $drawingInfo.smoothCurves)
                    Toggle("Show Smoothing Points (⌥⇧S)", isOn: $drawingInfo.showSmoothingPoints)
                    Toggle("Show Control Points (⌥C)", isOn: $drawingInfo.showControlPoints)
                    Toggle("Show Quads (⌥Q)", isOn: $drawingInfo.showQuads)
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
