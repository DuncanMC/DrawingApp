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
//                        print("\nUser dragged \(target.dragLocation.description)\n")
                        drawingInfo.isDragging = true
                        drawingInfo.lastDragLocation = value.startLocation
                        drawingInfo.draggingState = target.dragLocation
                    } else {
                        print("touch location not found")
                    }
                } else {
                    viewModel.handleDragging(value)
                }
            }
            .onEnded { value in
//                print("Dragging complete.")
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
                    .onTapGesture(count: 2) { location in
                        if let target = viewModel.getGestureLocation(touchLocation: location) {
                            print("Double-tap in \(target.dragLocation.description)\n")
                            let dragLocation = target.dragLocation
                            switch dragLocation {
                            case .inControlPoint(let curveIndex, let pointIndex):
                                var changed = drawingInfo.curves[curveIndex].points[pointIndex]
                                changed.pointType = (changed.pointType == .corner) ? .smooth : .corner
                                drawingInfo.curves[curveIndex].points[pointIndex] = changed
                            default:
                                break
                            }
                        } else {
                            print("double-tap location not found")
                        }
                    }
                    .gesture(dragGesture)
                TextEditor(text: $drawingInfo.text)
                    .frame(maxHeight: 50)
                HStack(spacing: 20) {
                    Spacer()

                    Toggle(isOn: $drawingInfo.showQuads) {
                        Text("Show quads")
                    }
                    .frame(maxWidth: 150, alignment: toggleAlignment)

                    Toggle(isOn: $drawingInfo.smoothCurves) {
                        Text("Smooth")
                    }
                    .frame(maxWidth: 140, alignment: toggleAlignment)
                    
                    Toggle(isOn: $drawingInfo.showSmoothingPoints) {
                        Text("Show points")
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
                        print("lineHardness = \(drawingInfo.lineHardness). Computed hardness = \(drawingInfo.hardness)")
                    }
                    Spacer()
                }
            }
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
