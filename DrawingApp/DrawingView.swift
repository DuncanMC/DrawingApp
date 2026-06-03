//
//  DrawingView.swift
//  DrawingApp
//
//  Created by Duncan Champney on 5/4/26.
//  Copyright (c) 2026 Duncan Champney. All rights reserved.
//

import SwiftUI
import MetalKit

#if os(macOS)
struct DrawingView: NSViewRepresentable {
    @ObservedObject var drawingInfo: DrawingInfo

    var onTap: ((CGPoint, GestureEvent) -> Void)?
    var onDoubleTap: ((CGPoint, GestureEvent) -> Void)?
    var onDragBegan: ((CGPoint, GestureEvent) -> Void)?
    var onDragChanged: ((CGPoint, GestureEvent) -> Void)?
    var onDragEnded: ((CGPoint, GestureEvent) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(drawingInfo: drawingInfo)
    }

    func makeNSView(context: Context) -> GestureCapturingView {
        let container = GestureCapturingView()

        let mtkView = MTKView()
        mtkView.sampleCount = context.coordinator.renderer.sampleCount
        mtkView.device = context.coordinator.renderer.device
        mtkView.delegate = context.coordinator.renderer
        mtkView.colorPixelFormat = .bgra8Unorm
        context.coordinator.renderer.mtkView = mtkView

        mtkView.autoresizingMask = [.width, .height]
        mtkView.frame = container.bounds
        container.addSubview(mtkView)

        let coord = context.coordinator
        let tap = TapRecognizer()
        tap.onTap = { [weak coord] loc, event in coord?.onTap?(loc, event) }
        tap.onDoubleTap = { [weak coord] loc, event in coord?.onDoubleTap?(loc, event) }

        let drag = DragRecognizer()
        drag.onDragBegan = { [weak coord] loc, event in coord?.onDragBegan?(loc, event) }
        drag.onDragChanged = { [weak coord] loc, event in coord?.onDragChanged?(loc, event) }
        drag.onDragEnded = { [weak coord] loc, event in coord?.onDragEnded?(loc, event) }

        container.eventRecognizers = [tap, drag]

        return container
    }

    func updateNSView(_ nsView: GestureCapturingView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onDoubleTap = onDoubleTap
        context.coordinator.onDragBegan = onDragBegan
        context.coordinator.onDragChanged = onDragChanged
        context.coordinator.onDragEnded = onDragEnded
    }

    class Coordinator {
        let renderer: DrawingRenderer
        var onTap: ((CGPoint, GestureEvent) -> Void)?
        var onDoubleTap: ((CGPoint, GestureEvent) -> Void)?
        var onDragBegan: ((CGPoint, GestureEvent) -> Void)?
        var onDragChanged: ((CGPoint, GestureEvent) -> Void)?
        var onDragEnded: ((CGPoint, GestureEvent) -> Void)?

        init(drawingInfo: DrawingInfo) {
            renderer = DrawingRenderer(drawingInfo: drawingInfo)
        }
    }
}

#else

struct DrawingView: UIViewRepresentable {
    @ObservedObject var drawingInfo: DrawingInfo

    var onTap: ((CGPoint, GestureEvent) -> Void)?
    var onDoubleTap: ((CGPoint, GestureEvent) -> Void)?
    var onDragBegan: ((CGPoint, GestureEvent) -> Void)?
    var onDragChanged: ((CGPoint, GestureEvent) -> Void)?
    var onDragEnded: ((CGPoint, GestureEvent) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(drawingInfo: drawingInfo)
    }

    func makeUIView(context: Context) -> GestureCapturingView {
        let container = GestureCapturingView()

        let mtkView = MTKView()
        mtkView.sampleCount = context.coordinator.renderer.sampleCount
        mtkView.isOpaque = true
        mtkView.device = context.coordinator.renderer.device
        mtkView.delegate = context.coordinator.renderer
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.isUserInteractionEnabled = false
        context.coordinator.renderer.mtkView = mtkView

        mtkView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mtkView.frame = container.bounds
        container.addSubview(mtkView)

        let coord = context.coordinator
        let tap = TapRecognizer()
        tap.onTap = { [weak coord] loc, event in coord?.onTap?(loc, event) }
        tap.onDoubleTap = { [weak coord] loc, event in coord?.onDoubleTap?(loc, event) }

        let drag = DragRecognizer()
        drag.onDragBegan = { [weak coord] loc, event in coord?.onDragBegan?(loc, event) }
        drag.onDragChanged = { [weak coord] loc, event in coord?.onDragChanged?(loc, event) }
        drag.onDragEnded = { [weak coord] loc, event in coord?.onDragEnded?(loc, event) }

        container.eventRecognizers = [tap, drag]

        return container
    }

    func updateUIView(_ uiView: GestureCapturingView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onDoubleTap = onDoubleTap
        context.coordinator.onDragBegan = onDragBegan
        context.coordinator.onDragChanged = onDragChanged
        context.coordinator.onDragEnded = onDragEnded
    }

    class Coordinator {
        let renderer: DrawingRenderer
        var onTap: ((CGPoint, GestureEvent) -> Void)?
        var onDoubleTap: ((CGPoint, GestureEvent) -> Void)?
        var onDragBegan: ((CGPoint, GestureEvent) -> Void)?
        var onDragChanged: ((CGPoint, GestureEvent) -> Void)?
        var onDragEnded: ((CGPoint, GestureEvent) -> Void)?

        init(drawingInfo: DrawingInfo) {
            renderer = DrawingRenderer(drawingInfo: drawingInfo)
        }
    }
}

#endif


#Preview {
//    DrawingView()
}
