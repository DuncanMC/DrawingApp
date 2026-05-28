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
    
    var maxAlpha: Float = 1
    var maxVerticiesSize = 3840
    
    var miterLimit: Float = 5

    // Ring buffer configuration
    private let ringBufferSize: Int = 4 * 1024 * 1024 // 4 MB for transient verticies
    private let ringBufferAlignment: Int = 256  // Metal requires 256-byte alignment for buffers bound with offsets
    private var ringWriteOffset: Int = 0        // Current write position into the ring buffer
    private var frameStride: Int { ringBufferSize / max(1, inFlightFrameCount) }
    private let inFlightFrameCount: Int = 3
    
    let vertexBuffer: MTLBuffer

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
            metalWidthPerPixel = scale / Float(max(drawableSize.width, drawableSize.height))

        }
    }

    let drawingInfo: DrawingInfo

    struct Uniforms {
        let color: simd_float4      //Only used when drawing outlines
        let drawWithTetxure: Bool   // Tells shader to draw with texture rather than color
        let orthoMatrix: float4x4
        let hardness: Float
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
        pipelineDesc.rasterSampleCount = sampleCount
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
            color: MetalColors.black,
            drawWithTetxure: false,
            orthoMatrix: orthoMatrix,
            hardness: drawingInfo.hardness
        )

        
        
        if false {
            let limit: Float = 0.9
            drawRing(center: simd_float2(0, 0), color: MetalColors.blue, radius: 280, steps: 120, lineThickness: 6)
            
            drawRing(center: simd_float2(-0.75, -0.75), color: MetalColors.blue, radius: 30, lineThickness: 6)
            drawRing(center: simd_float2(-0.75, -0.75), color: MetalColors.black, radius: 20, lineThickness: 6)
            drawRing(center: simd_float2(-0.75, -0.75), color: MetalColors.blue, radius: 10, lineThickness: 6)
            drawRing(center: simd_float2(-0.75, -0.75), color: MetalColors.black, radius: 2, lineThickness: 4)
            
            drawThickLine(
                p1: simd_float2(-limit,limit * drawingInfo.lineThickness),
                p2: simd_float2(limit, -limit * drawingInfo.lineThickness),
                color: MetalColors.black,
                thickness: 20,
            )
            
            
            drawSquare(center: simd_float2(0.7, 0.7), color: MetalColors.red, width: 58, orthoMatrix: orthoMatrix)
        }
        
        drawCurves(drawingInfo.curves)


        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()


        // MARK: - nested drawing functions
        struct Vertex: CustomStringConvertible {
        let position: SIMD2<Float>
        let alpha: Float
            
            var description: String {
                "\(position.x)\t\(position.y)\t\(alpha)"
            }
        }
        
        func curveToCatmullRomPoints(_ curve: CatmullRomCurve) -> [simd_float2] {
            var controlPoints = [simd_float2]()
            
            for (index, point) in curve.points.enumerated() {
                // Add each control point to the array of control points.
                controlPoints.append(point.coord)
                
                // Add the first and last point and all corner points twice.
                if index == 0 || index == curve.points.count - 1 || point.pointType == .corner {
                    controlPoints.append(point.coord)
                }
            }
            let (resultPoints, _) = smoothPointsInArray(controlPoints, granularity: 8, adjustGranularity: true)
            
            var filteredResultPoints: [simd_float2] = []
            var last: simd_float2? = nil
            for point in resultPoints {
                if point != last {
                    filteredResultPoints.append(point)
                }
                last = point
            }
            return filteredResultPoints
        }
        
        func drawCurves(_ curves: [CatmullRomCurve]) {
            let aspect = drawingInfo.imageAspectRatio
            let landscape = aspect > 1
            let adjustment: simd_float2 = landscape ?  simd_float2(1, 1/aspect) : simd_float2(1*aspect, 1)
            
            let widthPerPixel: Float = scale / Float(max(drawableSize.width, drawableSize.height))
            
            var leftIntersections: [simd_float2] = []
            var rightIntersections: [simd_float2] = []
            var leftVertexes = [Vertex]()
            leftVertexes.reserveCapacity(curves.count * 2)
            
            var rightVertexes = [Vertex]()
            rightVertexes.reserveCapacity(curves.count * 2)

            var leftLines = [Vertex]()
            var rightLines = [Vertex]()
            var cornerTriangles = [Vertex]()

            for (_, curve) in curves.enumerated() {
                
                let radius = drawingInfo.lineThickness * widthPerPixel
                let smoothedPoints: [simd_float2]
                if drawingInfo.smoothCurves == false {
                    smoothedPoints = curve.points.map { $0.coord  }
                } else {
                    smoothedPoints = curveToCatmullRomPoints(curve)
                }
                
                if smoothedPoints.count == 1  {
                    drawCircle(center: smoothedPoints[0], color: curve.color, radius: drawingInfo.lineThickness * 0.5, hardness: drawingInfo.hardness)
                } else {
                    for index in 1 ..< smoothedPoints.count {
                        let first = smoothedPoints[index-1] * adjustment
                        let middle = smoothedPoints[index] * adjustment
                        
                        let dir1 = normalize(middle - first)
                        let normal1 = simd_float2(-dir1.y, dir1.x) * radius
                        
                        let firstLeft = (first + normal1) / adjustment
                        let firstRight = (first - normal1) / adjustment
                        let secondLeftOne = (middle + normal1) / adjustment
                        let secondRightOne = (middle - normal1) / adjustment
                        let adjustedFirst = first / adjustment
                        if drawingInfo.showQuads {
                            let adjustedMiddle = middle / adjustment
                            leftLines += [
                                Vertex(position: secondLeftOne, alpha: 1),
                                Vertex(position: adjustedMiddle, alpha: 1),
                                
                                Vertex(position: adjustedMiddle, alpha: 1),
                                Vertex(position: adjustedFirst, alpha: 1),
                                
                                Vertex(position: adjustedFirst, alpha: 1),
                                Vertex(position: firstLeft, alpha: 1),
                                
                                Vertex(position: firstLeft, alpha: 1),
                                Vertex(position: secondLeftOne, alpha: 1)
                            ]
                            rightLines += [
                                Vertex(position: secondRightOne, alpha: 1),
                                Vertex(position: adjustedMiddle, alpha: 1),
                                
                                Vertex(position: adjustedMiddle, alpha: 1),
                                Vertex(position: adjustedFirst, alpha: 1),
                                
                                Vertex(position: adjustedFirst, alpha: 1),
                                Vertex(position: firstRight, alpha: 1),
                                
                                Vertex(position: firstRight, alpha: 1),
                                Vertex(position: secondRightOne, alpha: 1)
                            ]
                        }
                        if index == 1 {
                            leftVertexes += [Vertex(position: firstLeft, alpha: 0),
                                             Vertex(position: first/adjustment, alpha: maxAlpha)
                                             
                            ]
                            rightVertexes += [
                                Vertex(position: firstRight, alpha: 0),
                                Vertex(position: first/adjustment, alpha: maxAlpha)
                            ]
                        }
                        if index == smoothedPoints.count - 1 {
                            leftVertexes += [
                                Vertex(position: secondLeftOne, alpha: 0),
                                Vertex(position: middle/adjustment, alpha: maxAlpha)
                            ]
                            
                            rightVertexes += [
                                Vertex(position: secondRightOne, alpha: 0),
                                Vertex(position: middle/adjustment, alpha: maxAlpha)
                            ]
                        }
                        if index < smoothedPoints.count - 1 {
                            
                            //Calculate the intersection of "left" and right line segments and use them as the middle points.
                            let last = smoothedPoints[index+1] * adjustment
                            
                            let adjustedMiddle = middle/adjustment
                            let adjustedLast = last/adjustment
                            
                            let vectorAB = middle - first
                            let vectorBC = last - middle
                            
                            let crossProduct = vectorAB.x * vectorBC.y - vectorAB.y * vectorBC.x
                            
                            //                        if abs(crossProduct) < 2e-9 {
                            //                            print("Skipping point at index \(index)")
                            //                            continue
                            //                        }
                            
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
                            var leftIntersection: simd_float2
                            var rightIntersection: simd_float2
                            
                            
                            
                            if distanceSquaredBetween(p1: secondLeftOne, p2: secondLeftTwo) < widthPerPixel * widthPerPixel * 0.04 {
                                leftIntersection = midpoint(p1: secondLeftOne, p2: secondLeftTwo)
                            } else {
                                leftIntersection = intersection(line1: firstLeftLine, line2: secondLeftLine) ?? midpoint(p1: secondLeftOne, p2: secondLeftTwo)
                                // If this is a right-hand turn
                                if crossProduct < 0 {
                                    let squaredDistance = distanceSquaredBetween(p1: leftIntersection, p2: secondLeftOne)
                                    if squaredDistance > (radius * radius) * (miterLimit * miterLimit) / 4.0 {
                                        leftVertexes += [
                                            Vertex(position: secondLeftOne, alpha: 0),
                                            Vertex(position: adjustedMiddle, alpha: maxAlpha)
                                        ]
                                        leftIntersection = secondLeftTwo
                                    }
                                    leftIntersections.append(leftIntersection)
                                }
                                else if crossProduct > 0 {
                                    // Lefthand turn, so left side is inside
                                    let distanceToIntersection = distanceBetween(p1: secondLeftOne, p2: leftIntersection)
                                    let distanceFirstToMiddle = distanceBetween(p1: adjustedFirst, p2: adjustedMiddle)
                                    if distanceToIntersection > distanceFirstToMiddle {
                                        leftIntersection = firstLeft
                                    }
                                }
                            }
                            
                            
                            if distanceSquaredBetween(p1: secondRightOne, p2: secondRightTwo) < widthPerPixel * widthPerPixel * 0.04 {
                                // don't use the right intersection
                                rightIntersection = midpoint(p1: secondRightOne, p2: secondRightTwo)
                            } else {
                                rightIntersection = intersection(line1: firstRightLine, line2: secondRightLine) ?? midpoint(p1: secondRightOne, p2: secondRightTwo)
                                if crossProduct > 0
                                {
                                    let squaredDistance = distanceSquaredBetween(p1: rightIntersection, p2: secondRightOne)
                                    if squaredDistance > (radius * radius) * (miterLimit * miterLimit) / 4.0 {
                                        rightVertexes += [
                                            Vertex(position: secondRightOne, alpha: 0),
                                            Vertex(position: adjustedMiddle, alpha: maxAlpha)
                                        ]
                                        rightIntersection = secondRightTwo
                                    }
                                } else if crossProduct < 0 {
                                    // righthand turn, so right side is inside
                                    let distanceToIntersection = distanceBetween(p1: secondRightOne, p2: rightIntersection)
                                    let distanceFirstToMiddle = distanceBetween(p1: adjustedFirst, p2: adjustedMiddle)
                                    if distanceToIntersection > distanceFirstToMiddle {
                                        rightIntersection = firstRight
                                    }
                                }
                                
                                //                        if squaredDistance > (radius * radius) * (miterLimit * miterLimit) / 4.0 {
                                //                                rightIntersection = midpoint(p1: firstLeft, p2: secondLeftTwo)
                            }
                            //                        }
                            
                            //Testing
                            rightIntersections.append(rightIntersection)
                            
                            
                            
                            // Add triangles to show the adjustment between the normals and the left and right line intersections
                            if drawingInfo.showQuads {
                                
                                //                            if crossProduct < 0 { //right intersection is the miter.
                                //                                cornerTriangles += [
                                //                                    Vertex(position: rightIntersection, alpha: 0.25),
                                //                                    Vertex(position: secondRightOne, alpha: 0.25),
                                //                                    Vertex(position: secondRightTwo, alpha: 0.25),
                                //                                ]
                                //                            }
                                //                            if crossProduct > 0 {
                                //
                                //                                cornerTriangles += [
                                //                                    Vertex(position: leftIntersection, alpha: 0.25),
                                //                                    Vertex(position: secondLeftOne, alpha: 0.25),
                                //                                    Vertex(position: secondLeftTwo, alpha: 0.25),
                                //                                ]
                                //                            }
                                //
                                
                            }
                            leftVertexes += [
                                Vertex(position: leftIntersection, alpha: 0),
                                Vertex(position: adjustedMiddle, alpha: maxAlpha)
                            ]
                            rightVertexes += [
                                Vertex(position: rightIntersection, alpha: 0),
                                Vertex(position: adjustedMiddle, alpha: maxAlpha)
                            ]
                        }
                    } // For index
                }
                
                uniforms = Uniforms(
                    color: curve.color,
                    drawWithTetxure: false,
                    orthoMatrix: orthoMatrix,
                    hardness: drawingInfo.hardness
                )
                
                if leftVertexes.count >= 3 {
                    // Draw the left side triangle strips
                    let verticiesSize = MemoryLayout<Vertex>.stride * leftVertexes.count
                    var offset = allocateVerticiesInRing(byteCount: verticiesSize)
                    var dst = vertexBuffer.contents().advanced(by: offset)
                    dst.copyMemory(from: leftVertexes, byteCount: verticiesSize)
                    encoder.setVertexBuffer(vertexBuffer, offset: offset, index: 0)
                    
                    encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                    encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: leftVertexes.count)
                }
                leftVertexes = []
                
                uniforms = Uniforms(
                    color: curve.color,
                    drawWithTetxure: false,
                    orthoMatrix: orthoMatrix,
                    hardness: drawingInfo.hardness
                )

                if rightVertexes.count >= 3 {
                    // Draw the right side triangle strips
                    let verticiesSize = MemoryLayout<Vertex>.stride * rightVertexes.count
                    let offset = allocateVerticiesInRing(byteCount: verticiesSize)
                    let dst = vertexBuffer.contents().advanced(by: offset)
                    dst.copyMemory(from: rightVertexes, byteCount: verticiesSize)
                    encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                    encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                    
                    encoder.setVertexBuffer(vertexBuffer, offset: offset, index: 0)
                    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: rightVertexes.count)
                }
                
                rightVertexes = []
                if drawingInfo.showQuads {
                    
                    //Draw the left side quad outlines
                    uniforms = Uniforms(
                        color: MetalColors.black,
                        drawWithTetxure: false,
                        orthoMatrix: orthoMatrix,
                        hardness: 1.0
                    )
                    if !leftLines.isEmpty {
                        
                        var verticiesSize = MemoryLayout<Vertex>.stride * leftLines.count
                        var offset = allocateVerticiesInRing(byteCount: verticiesSize)
                        var dst = vertexBuffer.contents().advanced(by: offset)
                        dst.copyMemory(from: leftLines, byteCount: verticiesSize)
                        encoder.setVertexBuffer(vertexBuffer, offset: offset, index: 0)
                        
                        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                        encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: leftLines.count)
                        
                        leftLines = []
                    }

                    
                    // Draw the right side quad outlines
                    if !rightLines.isEmpty {
                        uniforms = Uniforms(
                            color: MetalColors.black,
                            drawWithTetxure: false,
                            orthoMatrix: orthoMatrix,
                            hardness: 1.0
                        )
                        let verticiesSize = MemoryLayout<Vertex>.stride * rightLines.count
                        let offset = allocateVerticiesInRing(byteCount: verticiesSize)
                        let dst = vertexBuffer.contents().advanced(by: offset)
                        dst.copyMemory(from: rightLines, byteCount: verticiesSize)
                        encoder.setVertexBuffer(vertexBuffer, offset: offset, index: 0)
                        
                        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                        encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: rightLines.count)
                        
                        rightLines = []
                    }
                    
                    // Draw the filled corner triangles
                    if !cornerTriangles.isEmpty {
                        uniforms = Uniforms(
                            color: simd_float4(1, 0.0, 0.0, 0.6),  // 75% opaque darkish red.
                            drawWithTetxure: false,
                            orthoMatrix: orthoMatrix,
                            hardness: 1.0
                        )
                        
                        let verticiesSize = MemoryLayout<Vertex>.stride * cornerTriangles.count
                        let offset = allocateVerticiesInRing(byteCount: verticiesSize)
                        let dst = vertexBuffer.contents().advanced(by: offset)
                        dst.copyMemory(from: cornerTriangles, byteCount: verticiesSize)
                        encoder.setVertexBuffer(vertexBuffer, offset: offset, index: 0)
                        
                        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: cornerTriangles.count)
                        cornerTriangles = []
                    }
                }



                
                // Show the left and right intersection points.
                if drawingInfo.smoothCurves && drawingInfo.showQuads {
                    for aPoint in leftIntersections {
                        drawSquare(center: aPoint, color: MetalColors.blue, width: 2,  orthoMatrix: orthoMatrix)
                    }
                    for aPoint in rightIntersections {
                        drawSquare(center: aPoint, color: MetalColors.blue, width: 2,  orthoMatrix: orthoMatrix)
                    }
                    leftIntersections = []
                    rightIntersections = []
                }
                if drawingInfo.smoothCurves && drawingInfo.showSmoothingPoints {
                    for aPoint in smoothedPoints {
                        drawSquare(center: aPoint, color: MetalColors.blue, width: 2,  orthoMatrix: orthoMatrix)
                    }
                }
            } // for curves
            // Now loop through all the curves and draw outlined squares for the corner points and circles for the smooth points.
            if drawingInfo.showControlPoints {
                
                for curve in curves {
                    let circleRadius: Float = 3
                    for index in 0 ..< curve.points.count {
                        let point = curve.points[index].coord
                        if curve.points[index].pointType == .smooth {
                            drawRing(center: point, color: MetalColors.white, radius: circleRadius, lineThickness: 2)
                            drawRing(center: point, color: MetalColors.blue, radius: circleRadius-2, lineThickness: 3)
                        } else {
                            drawSquare(center: point, color: MetalColors.white, width: (circleRadius + 2) * 2 , orthoMatrix: orthoMatrix, asDiamond: true)
                            drawSquare(
                                center: point,
                                color: MetalColors.darkGreen,
                                width: (circleRadius + 1) * 2,
                                orthoMatrix: orthoMatrix,
                                asDiamond: true)
                        }
                    }
                }
            }
            if drawingInfo.drawingMode == .editingCurve,
               let activeCurveIndex = drawingInfo.activeCurveIndex,
               let activePointIndex = drawingInfo.activePointIndex {
                let curve = curves[activeCurveIndex]
                let point = curve.points[activePointIndex].coord
                drawRing(center: point, color: MetalColors.white, radius: 10, lineThickness: 4)
                drawRing(center: point, color: MetalColors.black, radius: 10, lineThickness: 2)

            }
        }

        func drawCircle(
            center: simd_float2,
            color: SIMD4<Float>,
            radius: Float,
            steps: Int = 24,
            hardness: Float = 1.0
        ) {
            drawWedge(                center: center,
                                      color: color,
                                      radius: radius,
                                      steps: steps,
                                      hardness: hardness
                                      )
        }
        
        func drawWedge(
            center: simd_float2,
            color: SIMD4<Float>,
            radius: Float,
            startAngle: Float = 0,
            endAngle: Float = 360.0,
            steps: Int = 24,
            hardness: Float = 1.0
) {
            let aspect = drawingInfo.imageAspectRatio
            let landscape = aspect > 1
            let adjustment: simd_float2 = landscape ?  simd_float2(1, aspect) : simd_float2(1/aspect, 1)

            let widthPerPixel: Float = scale / Float(max(drawableSize.width, drawableSize.height))

            let startAngleRadians = startAngle.degreesToRadians
            let arcDelta = endAngle.degreesToRadians - startAngleRadians
            let notFullCircle = startAngle != 0.0 || endAngle != 360.0
            
            var vertexes = [Vertex]()
            vertexes.reserveCapacity(steps * 2 + 2)
            
            let radius = 2 * radius
            let loopSteps = notFullCircle ? steps - 1 : steps
            for step in 0 ..< loopSteps {
                let angle: Float = startAngleRadians + Float(step) / Float(steps) * arcDelta
                let angle2 = startAngleRadians + Float((step+1) % steps) / Float(loopSteps) * arcDelta
                
                var deltaX = cos(angle) * widthPerPixel * (radius) * adjustment.x
                var deltaY = sin(angle) * widthPerPixel * (radius) * adjustment.y
                
                let p1 = simd_float2(x: center.x + deltaX, y: center.y + deltaY)
                
                
                deltaX = cos(angle2) * widthPerPixel * (radius) * adjustment.x
                deltaY = sin(angle2) * widthPerPixel * (radius) * adjustment.y
                let p2 = simd_float2(x: center.x + deltaX, y: center.y + deltaY)

                vertexes += [
                    Vertex(position: center, alpha: 1),
                    Vertex(position: p1, alpha: 0),
                    Vertex(position: p2, alpha: 0),
                    Vertex(position: center, alpha: 1),
                    ]
            }
            
            uniforms = Uniforms(
                color: color,
                drawWithTetxure: false,
                orthoMatrix: orthoMatrix,
                hardness: hardness
            )
            
            let verticiesSize = MemoryLayout<Vertex>.stride * vertexes.count
            if maxVerticiesSize < verticiesSize {
                maxVerticiesSize = verticiesSize
                print("maxVerticiesSize = \(maxVerticiesSize). verticies.count = \(vertexes.count)")
            }
            let offset = allocateVerticiesInRing(byteCount: verticiesSize)
            let dst = vertexBuffer.contents().advanced(by: offset)
            dst.copyMemory(from: vertexes, byteCount: verticiesSize)
            encoder.setVertexBuffer(vertexBuffer, offset: offset, index: 0)
            
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: vertexes.count)


        }
    
        
        func drawRing(
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
            lineThickness: Float
            ) {
                
                let aspect = drawingInfo.imageAspectRatio
                let landscape = aspect > 1
                let adjustment: simd_float2 = landscape ?  simd_float2(1, aspect) : simd_float2(1/aspect, 1)

                let widthPerPixel: Float = scale / Float(max(drawableSize.width, drawableSize.height))

                let startAngleRadians = startAngle.degreesToRadians
                let arcDelta = endAngle.degreesToRadians - startAngleRadians
                let notFullCircle = startAngle != 0.0 || endAngle != 360.0
                
                var vertexes = [Vertex]()
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
                    
                    vertexes += [
                        Vertex(position: p1Inside, alpha: 1),
                        Vertex(position: p1Outside, alpha: 1),
                        Vertex(position: p2Inside, alpha: 1),
                        Vertex(position: p2Outside, alpha: 1)
                        ]
                }
                
                uniforms = Uniforms(
                    color: color,
                    drawWithTetxure: false,
                    orthoMatrix: orthoMatrix,
                    hardness: drawingInfo.hardness
                )
                
                let verticiesSize = MemoryLayout<Vertex>.stride * vertexes.count
                if maxVerticiesSize < verticiesSize {
                    maxVerticiesSize = verticiesSize
                    print("maxVerticiesSize = \(maxVerticiesSize). verticies.count = \(vertexes.count)")
                }
                let offset = allocateVerticiesInRing(byteCount: verticiesSize)
                let dst = vertexBuffer.contents().advanced(by: offset)
                dst.copyMemory(from: vertexes, byteCount: verticiesSize)
                encoder.setVertexBuffer(vertexBuffer, offset: offset, index: 0)
                
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
                
                var vertexes: [Vertex] = [
                    Vertex(position: p1, alpha: 1),
                    Vertex(position: p2, alpha: 1),
                    Vertex(position: p3, alpha: 1)
                    ]
                                
                var uniforms: Uniforms = Uniforms(
                    color: color,
                    drawWithTetxure: false,
                    orthoMatrix: orthoMatrix,
                    hardness: drawingInfo.hardness
                )
                
                var verticiesSize = MemoryLayout<Vertex>.stride * vertexes.count

                let offset = allocateVerticiesInRing(byteCount: verticiesSize)
                let dst = vertexBuffer.contents().advanced(by: offset)
                dst.copyMemory(from: vertexes, byteCount: verticiesSize)
                encoder.setVertexBuffer(vertexBuffer, offset: offset, index: 0)

                encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                
                vertexes = [
                    Vertex(position: p1, alpha: 1),
                    Vertex(position: p3, alpha: 1),
                    Vertex(position: p4, alpha: 1)
                    ]

                verticiesSize = MemoryLayout<Vertex>.stride * vertexes.count

                let offset2 = allocateVerticiesInRing(byteCount: verticiesSize)
                let dst2 = vertexBuffer.contents().advanced(by: offset2)
                dst2.copyMemory(from: vertexes, byteCount: verticiesSize)
                encoder.setVertexBuffer(vertexBuffer, offset: offset2, index: 0)
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
                orthoMatrix: orthoMatrix,
                hardness: drawingInfo.hardness
            )
            
            //                encoder.setVertexBytes(verticies, length: MemoryLayout<Vertex>.stride * verticies.count, index: 0)
            
            let verticiesSize = MemoryLayout<Vertex>.stride * verticies.count
            
            let offset = allocateVerticiesInRing(byteCount: verticiesSize)
            let dst = vertexBuffer.contents().advanced(by: offset)
            dst.copyMemory(from: verticies, byteCount: verticiesSize)
            encoder.setVertexBuffer(vertexBuffer, offset: offset, index: 0)
            
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
            
            let verticiesSize = MemoryLayout<Vertex>.stride * 4
            let offset = allocateVerticiesInRing(byteCount: verticiesSize)
            let dst = vertexBuffer.contents().advanced(by: offset)
            dst.copyMemory(from: vertexes, byteCount: verticiesSize)
            encoder.setVertexBuffer(vertexBuffer, offset: offset, index: 0)
            
            uniforms = Uniforms(
                color: color,
                drawWithTetxure: false,
                orthoMatrix: orthoMatrix,
                hardness: drawingInfo.hardness
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

