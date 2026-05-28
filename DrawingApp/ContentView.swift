//
//  ContentView.swift
//  DrawingApp
//
//  Created by Duncan Champney on 5/1/26.
//  Copyright (c) 2026 Duncan Champney. All rights reserved.
//

import SwiftUI

@MainActor struct ContentView: View {
    @ObservedObject var drawingInfo: DrawingInfo
    
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
                        let point =  CatmullRomPoint(coord: coords, pointType: .corner, hardness: 1.0, pointRadius: 10.0)

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
                    if curvePointsCount > 0 {
                        drawingInfo.activePointIndex = curvePointsCount - 1
                    }
                } else {
                    // Decide what to do about ending dragging of a point.
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
                TextEditor(text: $drawingInfo.text)
                    .frame(maxHeight: 50)
                HStack(spacing: 20) {
                    Spacer()

                    Button("Delete point") {
                        viewModel.handleDeletePoint()
                    }
                    .disabled(!drawingInfo.enableDeletePointButton)
                    
                    VStack(spacing: 10) {
                        Toggle(isOn: $drawingInfo.showQuads) {
                            Text("Show quads")
                        }
                        .frame(maxWidth: 130, alignment: toggleAlignment)
                        Toggle(isOn: $drawingInfo.showControlPoints) {
                            Text("Show control points")
                        }
                        .frame(maxWidth: 180, alignment: toggleAlignment)
                    }

                    Toggle(isOn: $drawingInfo.smoothCurves) {
                        Text("Smooth")
                    }
                    .frame(maxWidth: 100, alignment: toggleAlignment)
                    
                    Toggle(isOn: $drawingInfo.showSmoothingPoints) {
                        Text("Show smoothing")
                    }
                    .frame(maxWidth: 150, alignment: toggleAlignment)

                    VStack(alignment: .center)   {
                        Text("Thickness")
                        Slider(value: $drawingInfo.lineThickness, in: 2...70)
                    }
                    .frame(maxWidth: 200)
                    .onChange(of: drawingInfo.lineThickness) {
                        print("Line thickness = \(drawingInfo.lineThickness)")
                    }

                    VStack(alignment: .center)   {
                        Text("Line hardness")
                        Slider(value: $drawingInfo.lineHardness, in: 0...2)
                    }
                    .frame(maxWidth: 200)
                    .onChange(of: drawingInfo.lineHardness) {
                        //print("lineHardness = \(drawingInfo.lineHardness). Computed hardness = \(drawingInfo.hardness)")
                    }
                    Spacer()
                }
            }
            Spacer()
        }
    }
    
    init(drawingInfo: DrawingInfo) {
        self.drawingInfo = drawingInfo
        self.viewModel = .init(drawingInfo: drawingInfo)
    }
}

#Preview {
    ContentView(drawingInfo: DrawingInfo(title: "foo", text: "bar"))
}
