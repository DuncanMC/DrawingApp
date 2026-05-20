//
//  DrawingView.swift
//  DrawingApp
//
//  Created by Duncan Champney on 5/4/26.
//  Copyright (c) 2026 Duncan Champney. All rights reserved.
//

import SwiftUI
import Combine
import simd
import MetalKit

typealias ViewType = MTKView

#if os(macOS)
struct DrawingView: NSViewRepresentable {
    @StateObject var drawingInfo: DrawingInfo
    
    var isDragging: Bool = false
    
    var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                var  flags: UInt = 0
#if os(macOS)
                flags = NSEvent.modifierFlags.rawValue
#endif

                if !isDragging {
                    //print("Begin dragging in view.")
//                    if let target = scopeState.getDragLocation( value.startLocation) {
////                        print("\nUser tapped in \(target.dragLocation.rawValue)\n")
//                        scopeState.draggingState = target.dragLocation
//                        scopeState.lastDragLocation = value.startLocation
//                        self.isDragging = true
//                    } else {
//                        //print("\nUser did not tap in a known location\n")
//                    }

                } else {
                    //print("continuing drag.")
//                    scopeState.handleDragging(value: value, flags: flags)
                }
            }
            .onEnded { value in
//                self.isDragging = false
//                isRotating = false
//                scopeState.lastDragLocation = nil
////                let draggingStateString = scopeState.draggingState?.rawValue ?? "nil"
//                //print("\ndragGesture ended. scopeState.draggingState = \(draggingStateString). texAspect = \(scopeState.texAspect).")
//                //print("rotationCenter = \(scopeState.rotationCenter.myDescription)")
//                //print("TrianglePoints = \n\(scopeState.trianglePoints)")
            }
    }

    func makeCoordinator() -> DrawingRenderer {
        DrawingRenderer(drawingInfo: drawingInfo)
    }
    
    func updateNSView(_ nsView: MTKView, context: Context) {
    }
    
    func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.sampleCount = context.coordinator.sampleCount
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.delegate = context.coordinator
        mtkView.colorPixelFormat = .bgra8Unorm
        context.coordinator.mtkView = mtkView
        return mtkView
    }
}
#else
struct DrawingView: UIViewRepresentable {
    
    
    
    @Binding var drawingInfo: DrawingInfo

    
    func makeCoordinator() -> DrawingRenderer {
        DrawingRenderer(drawingInfo: $drawingInfo)
    }
    
    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.sampleCount = 4
        
        mtkView.isOpaque = true
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.delegate = context.coordinator
        mtkView.colorPixelFormat = .bgra8Unorm
        context.coordinator.mtkView = mtkView
        return mtkView
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {
        
    }
}

    #endif




#Preview {
//    DrawingView()
}
