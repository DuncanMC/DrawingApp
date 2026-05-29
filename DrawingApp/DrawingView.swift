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
    @ObservedObject var drawingInfo: DrawingInfo

    func makeCoordinator() -> DrawingRenderer {
        DrawingRenderer(drawingInfo: drawingInfo)
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
    }

    func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.sampleCount = context.coordinator.sampleCount
        mtkView.device = context.coordinator.device
        mtkView.delegate = context.coordinator
        mtkView.colorPixelFormat = .bgra8Unorm
        context.coordinator.mtkView = mtkView
        return mtkView
    }
}
#else
struct DrawingView: UIViewRepresentable {
    @ObservedObject var drawingInfo: DrawingInfo

    func makeCoordinator() -> DrawingRenderer {
        DrawingRenderer(drawingInfo: drawingInfo)
    }

    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.sampleCount = context.coordinator.sampleCount
        mtkView.isOpaque = true
        mtkView.device = context.coordinator.device
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
