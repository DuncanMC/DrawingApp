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
    

    var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                var  flags: UInt = 0
#if os(macOS)
                flags = NSEvent.modifierFlags.rawValue
#endif
                
                if !drawingInfo.isDragging {
                    //                    //print("Begin dragging in view.")
                    if let target = viewModel.getGestureLocation(touchLocation: value.startLocation) {
                        drawingInfo.drawingMode = .editingCurve
                        switch target.gestureLocation {
                        case .inControlPoint(let curveIndex, let pointIndex):
                            print("\nUser dragged \(target.gestureLocation.description)\n")
                            drawingInfo.isDragging = true
                            drawingInfo.lastDragLocation = value.startLocation
                            drawingInfo.draggingState = target.gestureLocation
                            //If the shift key is down, add to the list of selected points, else make this the only selected point.
                            let newPoint = SelectedPoint(curveIndex: curveIndex, pointIndex: pointIndex)
                            if flags & NSEvent.ModifierFlags.shift.rawValue != 0 {
                                drawingInfo.selectedPoints.insert(newPoint)
                            } else {
                                if !drawingInfo.selectedPoints.contains(newPoint) {
                                    drawingInfo.selectedPoints = [newPoint]
                                }
                            }
                        default:
                            break
                        }
                    } else {
                        let coords = viewModel.viewPointToMetal(value.startLocation)
                        
                        // If we are currently in editing mode with a single point selected,
                        // we want to add points from the selected point.

                        if drawingInfo.drawingMode == .editingCurve,
                           drawingInfo.selectedPoints.count == 1 {
                            let activeCurveIndex = drawingInfo.selectedPoints.first!.curveIndex
                            let activePointIndex = drawingInfo.selectedPoints.first!.pointIndex
                            print("Begin dragging while in editing mode.")
                            let point =  CatmullRomPoint(coord: coords, pointType: .smooth)

                            switch activePointIndex {
                            case 0:
                                // The first point of an existing curve is selected.
                                // Reverse the point order and start adding at the end.
                                drawingInfo.curves[activeCurveIndex].points.reverse()
                                fallthrough
                                
                            case drawingInfo.curves[activeCurveIndex].points.count - 1:
                                // The last point of a curve is selected.
                                // Go back to creating mode and start adding points at the end.
                                drawingInfo.drawingMode = .creatingCurve
                                drawingInfo.curves[activeCurveIndex].points.append(point)
                                drawingInfo.selectedPoints = [SelectedPoint(curveIndex: activeCurveIndex, pointIndex: drawingInfo.curves[activeCurveIndex].points.count - 1)] // TODO: should we deselect all?
                                drawingInfo.isDragging = true
                                drawingInfo.lastDragLocation = value.startLocation
                                return
                            default:
                                // A point in the middle of a curve is selected. Create a new curve starting from
                                // the selected point.
                                let point =  CatmullRomPoint(coord: coords, pointType: .smooth)

                                let activePoint = drawingInfo.curves[activeCurveIndex].points[activePointIndex]
                                let newCurve = CatmullRomCurve(color: drawingInfo.brushSettings.color,
                                                               radius: drawingInfo.brushSettings.size,
                                                               outlineColor: nil,
                                                               points: [activePoint, point])
                                drawingInfo.selectedPoints = [SelectedPoint(curveIndex: drawingInfo.curves.count, pointIndex: 1)]
                                drawingInfo.curves.append(newCurve)
                                drawingInfo.drawingMode = .creatingCurve
                                drawingInfo.lastDragLocation = value.startLocation
                                drawingInfo.isDragging = true
                                return
                            }
                        }
                        
                        let point =  CatmullRomPoint(coord: coords, pointType: .smooth)

                        let newCurve = CatmullRomCurve(color: drawingInfo.brushSettings.color,
                                                       radius: drawingInfo.brushSettings.size,
                                                       outlineColor: nil,
                                                       points: [point])
                        drawingInfo.selectedPoints = [SelectedPoint(curveIndex: drawingInfo.curves.count, pointIndex: 0)]

                        drawingInfo.curves.append(newCurve)
                        drawingInfo.drawingMode = .creatingCurve
                        drawingInfo.lastDragLocation = value.startLocation
                        drawingInfo.isDragging = true
                    }
                } else {
                    viewModel.handleDragging(value)
                }
            }
            .onEnded { value in
                if drawingInfo.drawingMode == .creatingCurve
                 {
                    let activeCurveIndex = drawingInfo.selectedPoints.first!.curveIndex
                    drawingInfo.drawingMode = .editingCurve
                    let curvePointsCount = drawingInfo.curves[activeCurveIndex].points.count
                    if curvePointsCount == 1  {
                        drawingInfo.selectedPoints = [SelectedPoint(curveIndex: activeCurveIndex, pointIndex: 0)]
                    } else {
                        drawingInfo.selectedPoints = []
                        let curve = drawingInfo.curves[activeCurveIndex]
                        let paredCurve = viewModel.parePoints(curve, autoTerminate: true, maxError: 0.01)
                        let startingPointCount = curve.points.count
                        let paredCurvePointCount = paredCurve.points.count
                        let percent = Float(startingPointCount - paredCurvePointCount) / Float(startingPointCount) * 100
                        let percentString = String(format: "%.1f", percent)
                        print("pared curve from \(curve.points.count) to \(paredCurve.points.count). \(percentString)% reduction.")
                        drawingInfo.curves[activeCurveIndex] = paredCurve
                        //                            Task {
                        //                                try await Task.sleep(nanoseconds: UInt64(0.5 * 1_000_000_000))
                        //                                Task { @MainActor in
                        //                                    drawingInfo.curves[activeCurveIndex] = paredCurve
                        //                                }
                        //                            }
                        
                        
                    }
                } else {
                    // Decide what to do about ending dragging of a point.
                    
//                    drawingInfo.selectedPoints = []
                    
                }
                drawingInfo.isDragging = false
                drawingInfo.lastDragLocation = nil
            }
    }
    
    var toggleAlignment: Alignment {
    #if os(macOS)
            return .leading
    #else
            return .trailing
    #endif

    }

    var body: some View {
        VStack {
            DrawingView(drawingInfo: drawingInfo)
                .frame(width: DrawingInfo.defaultSize.width, height: DrawingInfo.defaultSize.height)
                .border(Color.blue, width: 4)
                .aspectRatio(drawingInfo.imageSize, contentMode: .fit)
                .onTapGesture(count: 1) { location in
                    var flags: UInt = 0
                #if os(macOS)
                    flags = NSEvent.modifierFlags.rawValue
                #endif

                    viewModel.handleTap(location: location, flags: flags) // flags
                }
                .onTapGesture(count: 2) { location in
                    viewModel.handleDoubleTap(location: location)                    }
                .gesture(dragGesture)
            HStack(spacing: 20) {
                //                    Spacer()
                
                ColorPicker("Curve color", selection: $drawingInfo.currentColor)
                    .frame(maxWidth: 150)

                Button("Delete point") {
                    viewModel.handleDeletePoint()
                }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(!drawingInfo.enableDeletePointButton)
                
//                VStack(alignment: .leading, spacing: 10) {
//                    Toggle(isOn: $drawingInfo.showControlPoints) {
//                        Text("Show control points")
//                    }
//                    .frame(maxWidth: 180, alignment: toggleAlignment)
//
//                    Toggle(isOn: $drawingInfo.showQuads) {
//                        Text("Show quads")
//                    }
//                    .frame(maxWidth: 130, alignment: toggleAlignment)
//                    
//                }
//                
//                Toggle(isOn: $drawingInfo.smoothCurves) {
//                    Text("Smooth")
//                }
//                .frame(maxWidth: 100, alignment: toggleAlignment)
//                
//                Toggle(isOn: $drawingInfo.showSmoothingPoints) {
//                    Text("Show smoothing")
//                }
//                .frame(maxWidth: 150, alignment: toggleAlignment)
                
                VStack(alignment: .center)   {
                    Text("Thickness")
                    Slider(value: $drawingInfo.lineThickness, in: 2...70)
                }
                .frame(maxWidth: 150)
                .padding(.trailing, 10)
                .onChange(of: drawingInfo.lineThickness) {
                    //print("Line thickness = \(drawingInfo.lineThickness)")
                }
                
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
        .focusedSceneObject(drawingInfo)
        .onReceive(drawingInfo.objectWillChange) { _ in
            drawingInfo.registerUndo(with: undoManager)
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
                    Divider()

                    Button("Delete Point", role: .destructive) {
                        drawingInfo.deletePoints()
                    }
                    .disabled(!drawingInfo.enableDeletePointButton)

                    Button("Delete Entire Curve", role: .destructive) {
                        drawingInfo.deletePoints(deleteEntireCurve: true)
                    }
                    .disabled(!drawingInfo.enableDeletePointButton)
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
