//
//  DrawingView.swift
//  DrawingApp
//
//  Created by Duncan Champney on 5/4/26.
//

import SwiftUI
import Combine
import simd
import MetalKit

typealias ViewType = MTKView

#if os(macOS)
struct DrawingView: NSViewRepresentable {
    @Binding var drawingInfo: DrawingInfo
    
    func makeCoordinator() -> DrawingRenderer {
        DrawingRenderer(drawingInfo: $drawingInfo)
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
