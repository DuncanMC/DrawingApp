//
//  DrawingRenderer.swift
//  DrawingApp
//
//  Created by Duncan Champney on 5/4/26.
//  Copyright (c) 2026 Duncan Champney. All rights reserved.
//

import Foundation
import SwiftUI
import MetalKit
import simd

#if os(iOS)
import UIKit
#endif

class DrawingRenderer: NSObject, MTKViewDelegate {
    
    var log = false
    var useVertexBuffers = true
    var maxVerticiesSize = 3840

    // Ring buffer configuration
    private let ringBufferSize: Int = 64 * 1024 // 64KB for transient verticies
    private let ringBufferAlignment: Int = 256  // Metal requires 256-byte alignment for buffers bound with offsets
    private var ringWriteOffset: Int = 0        // Current write position into the ring buffer
    private var frameStride: Int { ringBufferSize / max(1, inFlightFrameCount) }
    private let inFlightFrameCount: Int = 3
    
    let vertexBuffer: MTLBuffer

    let red: SIMD4<Float> = SIMD4<Float>(0.7, 0, 0, 1)
    let yellow: SIMD4<Float> = SIMD4<Float>(1, 1, 0, 1)
    let blue: SIMD4<Float> = SIMD4<Float>(0, 0, 1, 1)
    let green: SIMD4<Float> = SIMD4<Float>(0, 1, 0, 1)
    let black: SIMD4<Float> = SIMD4<Float>(0, 0, 0, 1)
    let white: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1)
    let zeroPoint: vector_float2 = simd_make_float2(0,0)

    
    var sampleCount: Int = 1
    var scale: Float = 1.0
    
    weak var mtkView: MTKView?
    var device: MTLDevice!
    var commandQueue: MTLCommandQueue!
    var pipeline: MTLRenderPipelineState!
    var aspectRatio: Float = 1.0
    
    private(set) var drawableSize: CGSize = .zero {
        didSet {
            aspectRatio = Float(drawableSize.width / drawableSize.height)
        }
    }

    let drawingInfo: DrawingInfo

    struct Uniforms {
        let color: simd_float4      //Only used when drawing outlines
        let drawWithTetxure: Bool   // Tells shader to draw with texture rather than color
        let orthoMatrix: float4x4
    }

    init(drawingInfo: DrawingInfo) {
        self.drawingInfo = drawingInfo
        device = MTLCreateSystemDefaultDevice()
        guard let vertBuffer = device.makeBuffer(
            length: ringBufferSize,
            options: .storageModeShared
        ) else {
            fatalError("Could not create vertex buffer")
        }
        vertexBuffer = vertBuffer
        vertexBuffer.label = "TransientVertexRingBuffer"
        
        super.init()
        

        //MARK: Oversampling
        if device.supportsTextureSampleCount(4) {
            sampleCount = 4
        } else if device.supportsTextureSampleCount(2) {
            sampleCount = 2
        }
        commandQueue = device.makeCommandQueue()
        makePipeline()
    }
    
    func makePipeline() {
        let library = device.makeDefaultLibrary()
        let pipelineDesc = MTLRenderPipelineDescriptor()

        pipelineDesc.vertexFunction = library?.makeFunction(name: "vertex_main")
        pipelineDesc.fragmentFunction = library?.makeFunction(name: "fragment_main")
        pipelineDesc.colorAttachments[0].pixelFormat = .bgra8Unorm

        // Enable blending for transparent drawing
        pipelineDesc.rasterSampleCount = sampleCount // xxx
        pipelineDesc.colorAttachments[0].isBlendingEnabled = true
        pipelineDesc.colorAttachments[0].rgbBlendOperation = .add
        pipelineDesc.colorAttachments[0].alphaBlendOperation = .add
        pipelineDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineDesc.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        pipelineDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        pipeline = try! device.makeRenderPipelineState(descriptor: pipelineDesc)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {


        drawableSize = size
        Task { @MainActor in
            let newScale: CGFloat
    #if os(macOS)
            if let backingScaleFactor = mtkView?.window?.screen?.backingScaleFactor
            {
                newScale = CGFloat(backingScaleFactor)
            } else {
                print("backingScaleFactor is nil!")
                newScale = 1
            }
    #else
            newScale = CGFloat(mtkView?.contentScaleFactor ?? 1)
    #endif
            let scaledSize =   CGSize(width: size.width/newScale, height: size.height/newScale)
            //print("In SourceImageRenderer, scale = \(newScale). scaled image size = \(scaledSize)")

            drawingInfo.viewportSize = scaledSize
        }
        // For example, you may want to adjust your projection or drawing to match portrait/landscape changes
    }
    
    func draw(in view: MTKView) {
        
        enum ArrowHeadDirection {
            case down
            case left
        }

        guard let drawable = view.currentDrawable else {
            print("[ScopeRenderer] currentDrawable is nil")
            return
        }
        guard let descriptor = view.currentRenderPassDescriptor else {
            print("[ScopeRenderer] currentRenderPassDescriptor is nil")
            return
        }
        guard let pipeline = pipeline else {
            print("[ScopeRenderer] pipeline is nil")
            return
        }
#if os(macOS)
        scale = Float(mtkView?.window?.screen?.backingScaleFactor ?? 1.0)
#else
        scale = Float(mtkView?.contentScaleFactor ?? 1)
#endif
        let orthoMatrix = matrix_identity_float4x4
        
        // Reset ring write offset at the start of a frame region
        // Simple partitioning by frame without explicit GPU sync. For robust sync, use in-flight semaphores.
        if ringWriteOffset >= ringBufferSize - ringBufferAlignment {
            ringWriteOffset = 0
        }
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        
        let colorComponents = drawingInfo.backgroundColor.components()
        descriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: colorComponents[0],
            green: colorComponents[1],
            blue: colorComponents[2],
            alpha: colorComponents[3])

        descriptor.colorAttachments[0].loadAction =  MTLLoadAction.clear
        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)!
        encoder.setRenderPipelineState(pipeline)

        // Drawing code goes here:
        
        var uniforms = Uniforms(
            color: black,
            drawWithTetxure: false,
            orthoMatrix: orthoMatrix
        )

        
        // MARK: Test drawing code.
        let limit: Float = 0.9
        

//        drawCircle(center: simd_float2(0, 0), color: blue, radius: 280, steps: 120, lineThickness: 6)
//
//        drawCircle(center: simd_float2(-0.75, -0.75), color: blue, radius: 30, lineThickness: 6)
//        drawCircle(center: simd_float2(-0.75, -0.75), color: black, radius: 20, lineThickness: 6)
//        drawCircle(center: simd_float2(-0.75, -0.75), color: blue, radius: 10, lineThickness: 6)
//        drawCircle(center: simd_float2(-0.75, -0.75), color: black, radius: 2, lineThickness: 4)
        
        drawThickLine(
            p1: simd_float2(-limit,limit * drawingInfo.linePlacement),
            p2: simd_float2(limit, -limit * drawingInfo.linePlacement),
            color: black,
            thickness: 20,
        )

        
//        drawSquare(center: simd_float2(0.7, 0.7), color: red, width: 58, orthoMatrix: orthoMatrix)
        
        drawCurves(drawingInfo.curves)


        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()


        // MARK: - nested drawing functions
        
        func drawCurves(_ curves: [CatmullRomCurve]) {
            let aspect = drawingInfo.imageAspectRatio
            let landscape = aspect > 1
            let adjustment: simd_float2 = landscape ?  simd_float2(1, 1/aspect) : simd_float2(1*aspect, 1)
            
            let widthPerPixel: Float = scale / Float(max(drawableSize.width, drawableSize.height))
            var vertexes = [simd_float2]()
            
            vertexes.reserveCapacity(curves.count * 2)
            
            for curve in curves {
                
                let radius = curve.radius * widthPerPixel
                for index in 1 ..< curve.points.count {
                    let first = curve.points[index-1].coord * adjustment
                    let middle = curve.points[index].coord * adjustment
                    
                    let dir1 = normalize(middle - first)
                    let normal1 = simd_float2(-dir1.y, dir1.x) * radius
                    
                    let firstLeft = (first + normal1) / adjustment
                    let firstRight = (first - normal1) / adjustment
                    let secondLeftOne = (middle + normal1) / adjustment
                    let secondRightOne = (middle - normal1) / adjustment
                    if false {
                        vertexes += [firstLeft, firstRight, secondLeftOne, secondRightOne]
                        
                    } else {
                        
                        if index == 1 {
                            vertexes += [firstLeft, firstRight]
                        } else if index == curve.points.count - 1 {
                            vertexes += [secondLeftOne, secondRightOne]
                        }
                        if index < curve.points.count - 1 {
                            
                            //Calculate the intersection of "left" and right line segments and use them as the middle points.
                            let last = curve.points[index+1].coord * adjustment
                            
                            let dir2 = normalize(last - middle)
                            let normal2 = simd_float2(-dir2.y, dir2.x) * radius
                            let secondLeftTwo = (middle + normal2) / adjustment
                            let secondRightTwo = (middle - normal2) / adjustment
                            let lastLeft = (last + normal2) / adjustment
                            let lastRight = (last - normal2) / adjustment
                            let firstLeftLine = equationForLine(from: firstLeft, to: secondLeftOne)
                            let secondLeftLine = equationForLine(from: secondLeftTwo, to: lastLeft)
                            
                            let firstRightLine = equationForLine(from: firstRight, to: secondRightOne)
                            let secondRightLine = equationForLine(from: secondRightTwo, to: lastRight)
                            guard
                                let leftIntersection = intersection(line1: firstLeftLine, line2: secondLeftLine),
                                let rightIntersection = intersection(line1: firstRightLine, line2: secondRightLine) else {
                                fatalError("Can't compute intersections!")
                            }
                            vertexes += [leftIntersection, rightIntersection]
                            if index == 1 && log {
                                print("index = 1")
                                print("first = \(first/adjustment)")
                                print("firstleft = \(firstLeft)")
                                print("middle = \(middle/adjustment)")
                                print("secondLeftOne = \(secondLeftOne)")
                                print("lastLeft = \(lastLeft)")
                                print("leftIntersection = \(leftIntersection)")
                                print("----")
                            }
                        }
                    }
                }
                if useVertexBuffers {
                    let verticiesSize = MemoryLayout<simd_float2>.stride * vertexes.count
                    let offset = allocateVerticiesInRing(byteCount: verticiesSize)
                    let dst = vertexBuffer.contents().advanced(by: offset)
                    dst.copyMemory(from: vertexes, byteCount: verticiesSize)
                    encoder.setVertexBuffer(vertexBuffer, offset: offset, index: 0)
                } else {
                    encoder.setVertexBytes(vertexes, length: MemoryLayout<simd_float2>.stride * vertexes.count, index: 0)
                }
                
                uniforms = Uniforms(
                    color: curve.color,
                    drawWithTetxure: false,
                    orthoMatrix: orthoMatrix
                )
                
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: vertexes.count)
                
                // Now draw outlined sqares for the corner points and circles for the smooth points.
                for index in 0 ..< curve.points.count {
                    let point = curve.points[index].coord
                    if curve.points[index].pointType == .corner {
                        drawCircle(center: point, color: white, radius: 8, lineThickness: 2)
                        drawCircle(center: point, color: blue, radius: 6, lineThickness: 3)
                    } else {
                        drawSquare(center: point, color: white, width: 16, orthoMatrix: orthoMatrix)
                        drawSquare(center: point, color: blue, width: 14, orthoMatrix: orthoMatrix)
                    }
                }
            }
            
        }

        
        func drawCircle(
            center: simd_float2,
            color: SIMD4<Float>,
            radius: Float,
            steps: Int = 24,
            lineThickness: Float,
        ) {
            drawArc(
                center: center,
                color: color,
                radius: radius,
                steps: steps,
                lineThickness: lineThickness)
        }
        
        func drawArc(
            center: simd_float2,
            color: SIMD4<Float>,
            radius: Float,
            startAngle: Float = 0,
            endAngle: Float = 360.0,
            steps: Int = 24,
            lineThickness: Float,
            asDiamond: Bool = false) {
                
                let aspect = drawingInfo.imageAspectRatio
                let landscape = aspect > 1
                let adjustment: simd_float2 = landscape ?  simd_float2(1, aspect) : simd_float2(1/aspect, 1)

                let widthPerPixel: Float = scale / Float(max(drawableSize.width, drawableSize.height))

                let startAngleRadians = startAngle.degreesToRadians
                let arcDelta = endAngle.degreesToRadians - startAngleRadians
                let notFullCircle = startAngle != 0.0 || endAngle != 360.0
                
                var vertexes = [simd_float2]()
                vertexes.reserveCapacity(steps * 2)
                let radius = 2 * radius + lineThickness / 8
                
                let loopSteps = notFullCircle ? steps - 1 : steps
                for step in 0 ..< loopSteps {
                    let angle: Float = startAngleRadians + Float(step) / Float(steps) * arcDelta
                    let angle2 = startAngleRadians + Float((step+1) % steps) / Float(loopSteps) * arcDelta
                    
                    var deltaX = cos(angle) * widthPerPixel * (radius - lineThickness) * adjustment.x
                    var deltaY = sin(angle) * widthPerPixel * (radius - lineThickness) * adjustment.y
                    
                    let p1Inside = simd_float2(x: center.x + deltaX, y: center.y + deltaY)
                    
                    deltaX = cos(angle) * widthPerPixel  * (radius + lineThickness) * adjustment.x
                    deltaY = sin(angle) * widthPerPixel * (radius + lineThickness) * adjustment.y
                    
                    let p1Outside = simd_float2(x: center.x + deltaX, y: center.y + deltaY)
                    
                    deltaX = cos(angle2) * widthPerPixel * (radius - lineThickness) * adjustment.x
                    deltaY = sin(angle2) * widthPerPixel * (radius - lineThickness) * adjustment.y
                    let p2Inside = simd_float2(x: center.x + deltaX, y: center.y + deltaY)
                    
                    deltaX = cos(angle2) * widthPerPixel  * (radius + lineThickness) * adjustment.x
                    deltaY = sin(angle2) * widthPerPixel * (radius + lineThickness) * adjustment.y
                    let p2Outside = simd_float2(x: center.x + deltaX, y: center.y + deltaY)
                    
                    vertexes += [p1Inside, p1Outside, p2Inside, p2Outside]
                }
                
                uniforms = Uniforms(
                    color: color,
                    drawWithTetxure: false,
                    orthoMatrix: orthoMatrix
                )
                
                let verticiesSize = MemoryLayout<simd_float2>.stride * vertexes.count
                if maxVerticiesSize < verticiesSize {
                    maxVerticiesSize = verticiesSize
                    print("maxVerticiesSize = \(maxVerticiesSize). verticies.count = \(vertexes.count)")
                }
                if useVertexBuffers {
                    let offset = allocateVerticiesInRing(byteCount: verticiesSize)
                    let dst = vertexBuffer.contents().advanced(by: offset)
                    dst.copyMemory(from: vertexes, byteCount: verticiesSize)
                    encoder.setVertexBuffer(vertexBuffer, offset: offset, index: 0)
                } else {
                    encoder.setVertexBytes(vertexes, length: verticiesSize, index: 0)
                }
                
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: vertexes.count)
            }
        
        func drawSquare(
            center: simd_float2,
            color: SIMD4<Float>,
            width: Float,
            orthoMatrix: float4x4,
            asDiamond: Bool = false) {
                
                let aspect = drawingInfo.imageAspectRatio
                let landscape = aspect > 1
                let adjustment: simd_float2 = landscape ?  simd_float2(1, 1/aspect) : simd_float2(1*aspect, 1)

                let width = width
                let center: simd_float2 = simd_float2(x: center.x, y: center.y)
                let widthPerPixel: Float = scale / Float(max(drawableSize.width, drawableSize.height))
                let yOffset = (widthPerPixel * width) / adjustment.y
                let xOffset = widthPerPixel * width  / adjustment.x
                let p1: simd_float2
                let p2: simd_float2
                let p3: simd_float2
                let p4: simd_float2
                if !asDiamond {
                    p1 = simd_float2(x: center.x - xOffset, y: center.y + yOffset)
                    p2 = simd_float2(x: center.x + xOffset, y: center.y + yOffset)
                    p3 = simd_float2(x: center.x + xOffset, y: center.y - yOffset)
                    p4 = simd_float2(x: center.x - xOffset, y: center.y - yOffset)
                    
                } else {
                    p1 = simd_float2(x: center.x, y: center.y + yOffset)
                    p2 = simd_float2(x: center.x + xOffset, y: center.y)
                    p3 = simd_float2(x: center.x, y: center.y - yOffset)
                    p4 = simd_float2(x: center.x - xOffset, y: center.y)
                }
                
                var vertexes: [simd_float2] = [p1, p2, p3]
                                
                var uniforms: Uniforms = Uniforms(
                    color: color,
                    drawWithTetxure: false,
                    orthoMatrix: orthoMatrix
                )
                
                var verticiesSize = MemoryLayout<simd_float2>.stride * vertexes.count

                if useVertexBuffers {
                    let offset = allocateVerticiesInRing(byteCount: verticiesSize)
                    let dst = vertexBuffer.contents().advanced(by: offset)
                    dst.copyMemory(from: vertexes, byteCount: verticiesSize)
                    encoder.setVertexBuffer(vertexBuffer, offset: offset, index: 0)
                } else {
                    encoder.setVertexBytes(vertexes, length: MemoryLayout<simd_float2>.stride * 3, index: 0)
                }

                encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                
                vertexes = [p1, p3, p4]
                verticiesSize = MemoryLayout<simd_float2>.stride * vertexes.count

                if useVertexBuffers {
                    let offset2 = allocateVerticiesInRing(byteCount: verticiesSize)
                    let dst2 = vertexBuffer.contents().advanced(by: offset2)
                    dst2.copyMemory(from: vertexes, byteCount: verticiesSize)
                    encoder.setVertexBuffer(vertexBuffer, offset: offset2, index: 0)
                } else {
                    encoder.setVertexBytes(vertexes, length: MemoryLayout<simd_float2>.stride * 3, index: 0)
                }
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                
            }

        
        func drawArrowHead(
            point: simd_float2,
            size: Float,
            direction: ArrowHeadDirection,
            color: SIMD4<Float>,
            thickness: Float,
            orthoMatrix: float4x4
        ) {
                let thickness = thickness * scale
                let widthPerPixel: Float = scale / Float(max(drawableSize.width, drawableSize.height))

                let tipXOffset = (direction == .left ? -widthPerPixel * thickness / 2 : 0)
                let tipYOffset = (direction == .down ? -widthPerPixel * thickness / 2 : 0)
                
                let point = simd_float2(point.x + (direction == .left ? tipXOffset / 2 : 0), point.y + (direction == .down ? tipYOffset / 2 : 0))
                
                let deltaX = Float(sqrt(2)) / 2 * size * scale * widthPerPixel
                let deltaY = Float(sqrt(2)) / 2 * size * scale * widthPerPixel
                let pointTip = simd_float2(
                    point.x + tipXOffset * (direction == .down ? 0 : 1),
                    point.y + tipYOffset * (direction == .left ? 0 : 1)
                )
                let trailingPoint = simd_float2(
                    point.x - tipXOffset,
                    point.y - tipYOffset
                )
                let leadingOutsidePoint = simd_float2(
                    pointTip.x + deltaX,
                    pointTip.y + deltaY
                )
                let trailingOutsidePoint = simd_float2(
                    leadingOutsidePoint.x - tipXOffset * 2,
                    leadingOutsidePoint.y - tipYOffset * 2
                )
                
                let leadingInsidePoint = simd_float2(
                    pointTip.x + deltaX * (direction == .down ? -1 : 1),
                    pointTip.y + deltaY * (direction == .down ? 1 : -1)
                )
                
                let trailingInsidePoint = simd_float2(
                    leadingInsidePoint.x + tipXOffset * 2 * (direction == .down ? 1 : -1),
                    leadingInsidePoint.y + tipYOffset * 2 * (direction == .down ? -1 : 1)
                )
                let verticies: [simd_float2] = [leadingOutsidePoint,
                                                trailingOutsidePoint,
                                                pointTip,
                                                trailingPoint,
                                                leadingInsidePoint,
                                                trailingInsidePoint,
                ]
                
                var uniforms: Uniforms = Uniforms(
                    color: color,
                    drawWithTetxure: false,
                    orthoMatrix: orthoMatrix
                )
                
//                encoder.setVertexBytes(verticies, length: MemoryLayout<simd_float2>.stride * verticies.count, index: 0)

                let verticiesSize = MemoryLayout<simd_float2>.stride * verticies.count
                
                if useVertexBuffers {
                    let offset = allocateVerticiesInRing(byteCount: verticiesSize)
                    let dst = vertexBuffer.contents().advanced(by: offset)
                    dst.copyMemory(from: verticies, byteCount: verticiesSize)
                    encoder.setVertexBuffer(vertexBuffer, offset: offset, index: 0)
                } else {
                    encoder.setVertexBytes(verticies, length: verticiesSize, index: 0)
                }

                encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: verticies.count)
                
            }
        
        func drawThickLine(
            p1: simd_float2,
            p2: simd_float2,
            color: SIMD4<Float>,
            thickness: Float
        ) {
                
                let aspect = drawingInfo.imageAspectRatio
                let landscape = aspect > 1
                let adjustment: simd_float2 = landscape ?  simd_float2(1, 1/aspect) : simd_float2(1*aspect, 1)
                let p1Tweaked = p1  * adjustment
                let p2Tweaked = p2  * adjustment
                
                let thickness = thickness * scale / Float(max(drawableSize.width, drawableSize.height))
                let dir = normalize(p2Tweaked - p1Tweaked)
                let normal = simd_float2(-dir.y, dir.x) * thickness
                
                
                let v0 = (p1Tweaked + normal) / adjustment
                let v1 = (p1Tweaked - normal) / adjustment
                let v2 = (p2Tweaked + normal) / adjustment
                let v3 = (p2Tweaked - normal) / adjustment
                let vertexes = [v0, v1, v2, v3]
            
            if useVertexBuffers {
                let verticiesSize = MemoryLayout<simd_float2>.stride * 4
                let offset = allocateVerticiesInRing(byteCount: verticiesSize)
                let dst = vertexBuffer.contents().advanced(by: offset)
                dst.copyMemory(from: vertexes, byteCount: verticiesSize)
                encoder.setVertexBuffer(vertexBuffer, offset: offset, index: 0)
            } else {
                encoder.setVertexBytes(vertexes, length: MemoryLayout<simd_float2>.stride * 4, index: 0)
            }
                
                 uniforms = Uniforms(
                    color: color,
                    drawWithTetxure: false,
                    orthoMatrix: orthoMatrix
                )
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            }
        
        // MARK: Helper function for managing offsets into the ring buffer
        
        @inline(__always)
        func allocateVerticiesInRing(byteCount: Int) -> Int {
            let alignedSize = ((byteCount + ringBufferAlignment - 1) / ringBufferAlignment) * ringBufferAlignment
            if ringWriteOffset + alignedSize > ringBufferSize {
                // Wrap to start if not enough space
                ringWriteOffset = 0
            }
            let offset = ringWriteOffset
            ringWriteOffset += alignedSize
            return offset
        }
    }
}

