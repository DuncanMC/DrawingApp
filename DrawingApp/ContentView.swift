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
//                var  flags: UInt = 0
//#if os(macOS)
//                flags = NSEvent.modifierFlags.rawValue
//#endif
                
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
                            drawingInfo.activeCurveIndex = curveIndex
                            drawingInfo.activePointIndex = pointIndex
                        default:
                            break
                        }
                    } else {
                        let coords = viewModel.viewPointToMetal(value.startLocation)
                        
                        // If we are currently in editing mode with a point selected,
                        // we want to add points from the selected point.

                        if drawingInfo.drawingMode == .editingCurve,
                            let activeCurveIndex = drawingInfo.activeCurveIndex,
                           let activePointIndex = drawingInfo.activePointIndex {
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
                                drawingInfo.activePointIndex = nil
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
                                drawingInfo.activeCurveIndex = drawingInfo.curves.count
                                drawingInfo.curves.append(newCurve)
                                drawingInfo.drawingMode = .creatingCurve
                                drawingInfo.activePointIndex = nil
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
                        drawingInfo.activeCurveIndex = drawingInfo.curves.count
                        drawingInfo.curves.append(newCurve)
                        drawingInfo.drawingMode = .creatingCurve
                        drawingInfo.activePointIndex = nil
                        drawingInfo.lastDragLocation = value.startLocation
                        drawingInfo.isDragging = true
                    }
                } else {
                    viewModel.handleDragging(value)
                }
            }
            .onEnded { value in
                if drawingInfo.drawingMode == .creatingCurve,
                let activeCurveIndex = drawingInfo.activeCurveIndex {
                    drawingInfo.drawingMode = .editingCurve
                    let curvePointsCount = drawingInfo.curves[activeCurveIndex].points.count
                    if curvePointsCount == 1  {
                        drawingInfo.activePointIndex = 0
                    }
                } else {
                    // Decide what to do about ending dragging of a point.
                    drawingInfo.activePointIndex = nil
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
                    viewModel.handleTap(location: location)
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
