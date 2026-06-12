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
    
    var notificationToken: NSObjectProtocol?

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
    var scale: Float = 1.0 {
        didSet {
            metalWidthPerPixel = scale / Float(max(drawingInfo.drawableSize.width, drawingInfo.drawableSize.height))
            drawingInfo.scale = scale
        }
    }
    
    weak var mtkView: MTKView?
    var device: MTLDevice!
    var commandQueue: MTLCommandQueue!
    var pipeline: MTLRenderPipelineState!
    var aspectRatio: Float = 1.0
    

    let drawingInfo: DrawingInfo

    struct Uniforms {
        let color: simd_float4      //Only used when drawing outlines
        let drawWithTetxure: Bool   // Tells shader to draw with texture rather than color
        let orthoMatrix: float4x4
        let hardness: Float
        let scale: Float
        let textureOffset: simd_float2
    }

    var gridSpacing: Float = Float(UserDefaults.standard.double(forKey: UserDefaultsKeys.gridSpacing.rawValue))

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
        gridSpacing = Float(UserDefaults.standard.double(forKey: UserDefaultsKeys.gridSpacing.rawValue))
        if gridSpacing == 0 {
            gridSpacing = 20
        }
        super.init()
        
        notificationToken = NotificationCenter.default
            .addObserver(forName: settingsChangedNotification,
                         object: nil,
                         queue: nil) { notification in
                            let userInfo = notification.userInfo
                            if let change = userInfo?[UserDefaultsKeys.gridSpacing.rawValue] as? Double {
                                self.gridSpacing = Float(change)
                }
        }


        //MARK: Oversampling
        if device.supportsTextureSampleCount(4) {
            sampleCount = 4
        } else if device.supportsTextureSampleCount(2) {
            sampleCount = 2
        }
        commandQueue = device.makeCommandQueue()
        makePipeline()
        loadTexture()
    }
    
    func loadTexture() {
        let bundle = Bundle.main
        guard let url = bundle.url(forResource: "Checkerboard", withExtension: "png"),
        let imageData = try? Data(contentsOf: url) else {
            print("Can't load image data")
            return
        }
        let loader = MTKTextureLoader(device: device)
        do {
            let options: [MTKTextureLoader.Option: Any] = [.origin:MTKTextureLoader.Origin.bottomLeft, .generateMipmaps: true]
            let tex = try loader.newTexture(data: imageData, options: options)
            Task { @MainActor in
                drawingInfo.texture = tex
            }
//            let hasAlpha =
//            tex.pixelFormat == .rgba8Unorm ||
//            tex.pixelFormat == .rgba8Unorm_srgb ||
//            tex.pixelFormat == .bgra8Unorm ||
//            tex.pixelFormat == .bgra8Unorm_srgb ||
//            tex.pixelFormat == .rgba16Float ||
//            tex.pixelFormat == .rgba32Float
            //                    print("[ScopeRenderer] Loaded texture pixel format: \(tex.pixelFormat) | hasAlpha: \(hasAlpha)")
        } catch {
            print("Error loading texture: \(error)")
        }

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


        drawingInfo.drawableSize = size
        aspectRatio = Float(size.width / size.height)
        metalWidthPerPixel = scale / Float(max(size.width, size.height))

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
        
        struct Vertex: CustomStringConvertible {
        let position: SIMD2<Float>
        let alpha: Float
            
            var description: String {
                "\(position.x)\t\(position.y)\t\(alpha)"
            }
        }

        
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
        let textureOffset: simd_float2
        if drawingInfo.marchingAnts {
            let time = Float(CACurrentMediaTime())
            let speed: Float = 10
            let offset = time * speed
            textureOffset = simd_float2(offset, offset)
        } else {
            textureOffset = simd_float2(0, 0)
        }
        
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
        if let texture = drawingInfo.texture {
            encoder.setFragmentTexture(texture, index: 0)
        }

        // Drawing code goes here:
        
        func hardnessForLinehardness(_ lineHardness: Float) -> Float {
            pow(2,(2-lineHardness)) - 1
        }
        
        var uniforms = Uniforms(
            color: MetalColors.black,
            drawWithTetxure: false,
            orthoMatrix: orthoMatrix,
            hardness: hardnessForLinehardness(drawingInfo.brushSettings.lineHardness),
            scale: scale,
            textureOffset: textureOffset
        )

        
        
        if false {
            let limit: Float = 0.9
            drawRing(center: simd_float2(0, 0), color: MetalColors.blue, radius: 280, steps: 120, lineThickness: 6)
            
            drawRing(center: simd_float2(-0.75, -0.75), color: MetalColors.blue, radius: 30, lineThickness: 6)
            drawRing(center: simd_float2(-0.75, -0.75), color: MetalColors.black, radius: 20, lineThickness: 6)
            drawRing(center: simd_float2(-0.75, -0.75), color: MetalColors.blue, radius: 10, lineThickness: 6)
            drawRing(center: simd_float2(-0.75, -0.75), color: MetalColors.black, radius: 2, lineThickness: 4)
            
            drawThickLine(
                p1: simd_float2(-limit,limit * drawingInfo.brushSettings.size),
                p2: simd_float2(limit, -limit * drawingInfo.brushSettings.size),
                color: MetalColors.black,
                thickness: 20,
            )
            
            
            drawSquare(center: simd_float2(0.7, 0.7), color: MetalColors.red, width: 58, orthoMatrix: orthoMatrix)
        }
        
        drawCurves(drawingInfo.curves)
        
        if drawingInfo.showGridLines {
            drawGridLines(even: true, color: MetalColors.pink)
            drawGridLines(even: false, color: MetalColors.black)
        }
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()


        // MARK: - nested drawing functions
        
        func drawGridLines(even: Bool, color: simd_float4) {
//            let gridSpacing: Float  = 20
            let gridAlpha: Float = 1.0
            
            // MARK: - Draw gridlines, if requested
            let yStepSize = drawingInfo.metalPixelSize.y * gridSpacing
            let ySteps = Int(2.0 / yStepSize)
            let xStepSize = drawingInfo.metalPixelSize.x * gridSpacing
            let xSteps = Int(2.0 / xStepSize)
            
            var vertexes = [Vertex]()
            let expectedCapacity = ySteps + xSteps + 4
            vertexes.reserveCapacity(expectedCapacity)
            var y: Float = even ? 0 : yStepSize
            while y <= 1 {
                vertexes += [Vertex(position: simd_float2(-1, y), alpha: gridAlpha),
                             Vertex(position: simd_float2( 1, y), alpha: gridAlpha)]
                y += yStepSize * 2
            }
            y = even ? -yStepSize * 2 : -yStepSize
            while y >= -1 {
                vertexes += [Vertex(position: simd_float2(-1, y), alpha: gridAlpha),
                             Vertex(position: simd_float2( 1, y), alpha: gridAlpha)]
                y -= yStepSize * 2
            }
            var x: Float =  even ? 0 : xStepSize
            while x <= 1 {
                vertexes += [Vertex(position: simd_float2(x, -1), alpha: gridAlpha),
                             Vertex(position: simd_float2(x, 1), alpha: gridAlpha)]
                x += xStepSize * 2
            }
            x = even ? -xStepSize * 2 : -xStepSize
            while x >= -1 {
                vertexes += [Vertex(position: simd_float2(x, -1), alpha: gridAlpha),
                             Vertex(position: simd_float2(x, 1), alpha: gridAlpha)]
                x -= xStepSize * 2
            }
            if vertexes.count > expectedCapacity {
                print("vertexes.count = \(vertexes.count). expectedCapacity = \(expectedCapacity).")
            }
            let verticiesSize = MemoryLayout<Vertex>.stride * vertexes.count
            let offset = allocateVerticiesInRing(byteCount: verticiesSize)
            let dst = vertexBuffer.contents().advanced(by: offset)
            dst.copyMemory(from: vertexes, byteCount: verticiesSize)
            encoder.setVertexBuffer(vertexBuffer, offset: offset, index: 0)
            
            uniforms = Uniforms(
                color: color,
                drawWithTetxure: false,
                orthoMatrix: orthoMatrix,
                hardness: 0,
                scale: scale,
                textureOffset: simd_float2.zero
            )
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: vertexes.count)
        }
        
        func drawOutlinedBoxes(at points: [DragHandle]) {
            for aPoint in points {
                if aPoint.handleType != drawingInfo.transformModeValues?.selectedTransformHandle {
                    drawBox(center: aPoint.coord, color: MetalColors.white, width: 10, lineThickness: 3, orthoMatrix: orthoMatrix)
                    drawBox(center: aPoint.coord, color: MetalColors.black, width: 10, lineThickness: 1, orthoMatrix: orthoMatrix)
                } else {
                    drawBox(center: aPoint.coord, color: MetalColors.blue, width: 10, lineThickness: 3, orthoMatrix: orthoMatrix)
                    drawSquare(center: aPoint.coord, color: MetalColors.red, width: 8, orthoMatrix: orthoMatrix)

                }
            }
        }
        func curveToCatmullRomPoints(_ curve: CatmullRomCurve) -> [SmoothedCurvePoint] {
            var controlPoints = [SmoothedCurvePoint]()
            
            for (index, point) in curve.points.enumerated() {
                // Add each control point to the array of control points.
                controlPoints.append(SmoothedCurvePoint(coord: point.coord, controlPointIndex: index, weight: 0.0))
                
                // Add all corner points twice.
                if point.pointType == .corner {
                    controlPoints.append(SmoothedCurvePoint(coord: point.coord, controlPointIndex: index, weight: 0.0))
                }
            }
            let (resultPoints, _) = smoothPointsInArray(
                // MARK: Granularity setting
                controlPoints, granularity: 8,
                adjustGranularity: true,
                calculateWeights: true,
                makeClosedLoop: curve.isClosedCurve)
            
            var filteredResultPoints: [SmoothedCurvePoint] = []
            var last: SmoothedCurvePoint? = nil
            for point in resultPoints {
                if point != last {
                    filteredResultPoints.append(point)
                }
                last = point
            }
            return filteredResultPoints
        }
        
        func computeRadiusForPoint(_ point: SmoothedCurvePoint, inCurve curve: CatmullRomCurve) -> Float {
            
            guard point.controlPointIndex < curve.points.count
            else { return drawingInfo.brushSettings.size }
            let startingRadius: Float = curve.points[point.controlPointIndex].pointRadius ?? drawingInfo.brushSettings.size

            let endingIndex: Int = (point.controlPointIndex + 1) % curve.points.count
//            < curve.points.count ? point.controlPointIndex + 1 : point.controlPointIndex

            let endingRadius: Float = curve.points[endingIndex].pointRadius ?? drawingInfo.brushSettings.size
            return startingRadius * (1 - point.weight) + (endingRadius * point.weight)
        }
        
        func drawCurves(_ curves: [CatmullRomCurve]) {
            let aspect = drawingInfo.imageAspectRatio
            let landscape = aspect > 1
            let adjustment: simd_float2 = landscape ?  simd_float2(1, 1/aspect) : simd_float2(1*aspect, 1)
            
            func hardnessForCurve(_ curve: CatmullRomCurve) -> Float {
                let lineHardness = curve.hardness ?? drawingInfo.brushSettings.lineHardness
                return hardnessForLinehardness(lineHardness)
            }
            
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
                
                //let radius = drawingInfo.lineThickness * metalWidthPerPixel
                var smoothedPoints: [SmoothedCurvePoint]
                if drawingInfo.smoothCurves == false {
                    smoothedPoints = curve.points.enumerated().map { (index, point) in
                        SmoothedCurvePoint(coord: point.coord, controlPointIndex: index, weight: 0)} // TODO: get index for control points
                    if curve.isClosedCurve {
                        smoothedPoints.append(smoothedPoints.first!)
                    }
                } else {
                    smoothedPoints = curveToCatmullRomPoints(curve)
                }
                
                if smoothedPoints.count == 1  {
                    let point = smoothedPoints[0]
                    let size = curve.points[point.controlPointIndex].pointRadius ?? drawingInfo.brushSettings.size
                    drawCircle(center: point.coord, color: curve.color, radius: size * 0.5, hardness: hardnessForCurve(curve))
                } else {
                    for index in 1 ..< smoothedPoints.count {
                        let first = smoothedPoints[index-1].coord * adjustment
                        let middle = smoothedPoints[index].coord * adjustment
                        
                        let dir1 = normalize(middle - first)
                        let indexToUse = index == 1 ? index - 1 : index
                        let pixelRadius = computeRadiusForPoint(smoothedPoints[indexToUse], inCurve: curve)
                        let radius = pixelRadius * metalWidthPerPixel
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
                            let last = smoothedPoints[(index+1) % smoothedPoints.count].coord * adjustment
                            
                            let adjustedMiddle = middle/adjustment
                            
                            let vectorAB = middle - first
                            let vectorBC = last - middle
                            
                            let crossProduct = vectorAB.x * vectorBC.y - vectorAB.y * vectorBC.x
                            
                            //                        if abs(crossProduct) < 2e-9 {
                            //                            print("Skipping point at index \(index)")
                            //                            continue
                            //                        }
                            
                            let dir2 = normalize(last - middle)
//                            // Get the next point's radius
//                            pixelRadius = computeRadiusForPoint(smoothedPoints[index], inCurve: curve)
//                            radius = pixelRadius * widthPerPixel

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
                            
                            
                            
                            if distanceSquaredBetween(p1: secondLeftOne, p2: secondLeftTwo) < metalWidthPerPixel * metalWidthPerPixel * 0.04 {
                                leftIntersection = midpoint(p1: secondLeftOne, p2: secondLeftTwo)
                            } else {
                                leftIntersection = intersection(line1: firstLeftLine, line2: secondLeftLine) ?? midpoint(p1: secondLeftOne, p2: secondLeftTwo)
                                // If this is a right-hand turn
                                if crossProduct < 0 {
                                    leftVertexes += [
                                        Vertex(position: secondLeftOne, alpha: 0),
                                        Vertex(position: adjustedMiddle, alpha: maxAlpha)
                                    ]
                                    leftIntersection = secondLeftTwo
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

                            if distanceSquaredBetween(p1: secondRightOne, p2: secondRightTwo) < metalWidthPerPixel * metalWidthPerPixel * 0.04 {
                                // don't use the right intersection
                                rightIntersection = midpoint(p1: secondRightOne, p2: secondRightTwo)
                            } else {
                                rightIntersection = intersection(line1: firstRightLine, line2: secondRightLine) ?? midpoint(p1: secondRightOne, p2: secondRightTwo)
                                if crossProduct > 0
                                {
                                    rightVertexes += [
                                        Vertex(position: secondRightOne, alpha: 0),
                                        Vertex(position: adjustedMiddle, alpha: maxAlpha)
                                    ]
                                    rightIntersection = secondRightTwo
                                } else if crossProduct < 0 {
                                    // righthand turn, so right side is inside
                                    let distanceToIntersection = distanceBetween(p1: secondRightOne, p2: rightIntersection)
                                    let distanceFirstToMiddle = distanceBetween(p1: adjustedFirst, p2: adjustedMiddle)
                                    if distanceToIntersection > distanceFirstToMiddle {
                                        rightIntersection = firstRight
                                    }
                                }
                                
                            }
                            
                            //Testing
                            rightIntersections.append(rightIntersection)
                            
                            
                            
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
                    hardness: hardnessForCurve(curve),
                    scale: scale,
                    textureOffset: textureOffset
                )

                if leftVertexes.count >= 3 {
                    // Draw the left side triangle strips
                    let verticiesSize = MemoryLayout<Vertex>.stride * leftVertexes.count
                    let offset = allocateVerticiesInRing(byteCount: verticiesSize)
                    let dst = vertexBuffer.contents().advanced(by: offset)
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
                    hardness: hardnessForCurve(curve),
                    scale: scale,
                    textureOffset: textureOffset
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
                        hardness: 1.0,
                        scale: scale,
                        textureOffset: textureOffset
                    )
                    if !leftLines.isEmpty {
                        
                        let verticiesSize = MemoryLayout<Vertex>.stride * leftLines.count
                        let offset = allocateVerticiesInRing(byteCount: verticiesSize)
                        let dst = vertexBuffer.contents().advanced(by: offset)
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
                            hardness: 1.0,
                            scale: scale,
                            textureOffset: textureOffset
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
                            hardness: 1.0,
                            scale: scale,
                            textureOffset: textureOffset
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
                        drawSquare(center: aPoint.coord, color: MetalColors.white, width: 4,  orthoMatrix: orthoMatrix)
                        drawSquare(center: aPoint.coord, color: MetalColors.blue, width: 2,  orthoMatrix: orthoMatrix)
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
            if drawingInfo.drawingMode == .editingCurve
            {
                // If we have selected points, draw them
                for aSelectedPoint in drawingInfo.selectedPoints {
                    let curve = curves[aSelectedPoint.curveIndex]
                    let point = curve.points[aSelectedPoint.pointIndex].coord
                    drawRing(center: point, color: MetalColors.black, radius: 10, lineThickness: 2, drawWithTexture: true)
                }
                // If we are in transform selection mode, find the bounding box for our selected points.
                if drawingInfo.transformSelection {
                    guard let transformModeValues = drawingInfo.transformModeValues else {
                        return
                    }
                    //Outline the selecion rectangle with "marching ants."
                    drawThickLine(p1: transformModeValues.topLeft,
                                  p2: transformModeValues.topRight,
                                  color: MetalColors.black,
                                  thickness: 1,
                                  drawWithTexture: true)
                    drawThickLine(p1: transformModeValues.bottomLeft,
                                  p2: transformModeValues.bottomRight,
                                  color: MetalColors.black,
                                  thickness: 1,
                                  drawWithTexture: true)
                    drawThickLine(p1: transformModeValues.topLeft,
                                  p2: transformModeValues.bottomLeft,
                                  color: MetalColors.black,
                                  thickness: 1,
                                  drawWithTexture: true)
                    drawThickLine(p1: transformModeValues.topRight,
                                  p2: transformModeValues.bottomRight,
                                  color: MetalColors.black,
                                  thickness: 1,
                                  drawWithTexture: true)
                    
                    // Draw the rotation center as a "target reticle"
                    let centerRadius: Float = 6
                    let hLineWidth = 10  * metalWidthPerPixel / adjustment.x
                    let vLineHeight = 10  * metalWidthPerPixel / adjustment.y
                    let circleWidth = (centerRadius+6) * metalWidthPerPixel / adjustment.x
                    let circleHeight = (centerRadius+6)  * metalWidthPerPixel / adjustment.y
                    //White outlines
                    drawThickLine(
                        p1: simd_float2(transformModeValues.rotationPoint.x - hLineWidth - circleWidth, transformModeValues.rotationPoint.y),
                        p2: simd_float2(transformModeValues.rotationPoint.x - circleWidth, transformModeValues.rotationPoint.y),
                        color: MetalColors.white,
                        thickness: 4)
                    drawThickLine(
                        p1: simd_float2(transformModeValues.rotationPoint.x + hLineWidth + circleWidth, transformModeValues.rotationPoint.y),
                        p2: simd_float2(transformModeValues.rotationPoint.x + circleWidth, transformModeValues.rotationPoint.y),
                        color: MetalColors.white,
                        thickness: 4)

                    drawThickLine(
                        p1: simd_float2(transformModeValues.rotationPoint.x, transformModeValues.rotationPoint.y - vLineHeight - circleHeight),
                        p2: simd_float2(transformModeValues.rotationPoint.x, transformModeValues.rotationPoint.y - circleHeight),
                        color: MetalColors.white,
                        thickness: 4)
                    drawThickLine(
                        p1: simd_float2(transformModeValues.rotationPoint.x, transformModeValues.rotationPoint.y + vLineHeight + circleHeight),
                        p2: simd_float2(transformModeValues.rotationPoint.x, transformModeValues.rotationPoint.y + circleHeight),
                        color: MetalColors.white,
                        thickness: 4)

                    drawRing(
                        center: transformModeValues.rotationPoint,
                        color: MetalColors.white,
                        radius: centerRadius,
                        lineThickness: 3,
                        drawWithTexture: false)
                    
                    //Black drawing
                    
                    drawThickLine(
                        p1: simd_float2(transformModeValues.rotationPoint.x, transformModeValues.rotationPoint.y - vLineHeight - circleHeight),
                        p2: simd_float2(transformModeValues.rotationPoint.x, transformModeValues.rotationPoint.y - circleHeight),
                        color: MetalColors.black,
                        thickness: 2)
                    drawThickLine(
                        p1: simd_float2(transformModeValues.rotationPoint.x, transformModeValues.rotationPoint.y + vLineHeight + circleHeight),
                        p2: simd_float2(transformModeValues.rotationPoint.x, transformModeValues.rotationPoint.y + circleHeight),
                        color: MetalColors.black,
                        thickness: 2)


                    drawRing(
                        center: transformModeValues.rotationPoint,
                        color: MetalColors.black,
                        radius: centerRadius,
                        lineThickness: 1,
                        drawWithTexture: false)
                    drawThickLine(
                        p1: simd_float2(transformModeValues.rotationPoint.x - hLineWidth - circleWidth, transformModeValues.rotationPoint.y),
                        p2: simd_float2(transformModeValues.rotationPoint.x - circleWidth, transformModeValues.rotationPoint.y),
                        color: MetalColors.black,
                        thickness: 2)
                    drawThickLine(
                        p1: simd_float2(transformModeValues.rotationPoint.x + hLineWidth + circleWidth, transformModeValues.rotationPoint.y),
                        p2: simd_float2(transformModeValues.rotationPoint.x + circleWidth, transformModeValues.rotationPoint.y),
                        color: MetalColors.black,
                        thickness: 2)
                    drawSquare(center: transformModeValues.rotationPoint, color: MetalColors.black, width: 2, orthoMatrix: orthoMatrix)


                    // Now draw the corner drag handles
                    let middleX = (transformModeValues.topLeft.x + transformModeValues.bottomRight.x) / 2.0
                    let middleY = (transformModeValues.topLeft.y + transformModeValues.bottomRight.y) / 2.0
                    
                    drawOutlinedBoxes(at: transformModeValues.dragHandles)

                }
            }
        }

        func drawCircle(
            center: simd_float2,
            color: SIMD4<Float>,
            radius: Float,
            steps: Int = 24,
            hardness: Float = 1.0,
            drawWithTexture: Bool = false,
        ) {
            drawWedge(
                center: center,
                color: color,
                radius: radius,
                steps: steps,
                hardness: hardness,
                drawWithTexture: drawWithTexture,
            )
        }
        
        func drawWedge(
            center: simd_float2,
            color: SIMD4<Float>,
            radius: Float,
            startAngle: Float = 0,
            endAngle: Float = 360.0,
            steps: Int = 24,
            hardness: Float = 1.0,
            drawWithTexture: Bool = false,
) {
            let aspect = drawingInfo.imageAspectRatio
            let landscape = aspect > 1
            let adjustment: simd_float2 = landscape ?  simd_float2(1, aspect) : simd_float2(1/aspect, 1)

//            let widthPerPixel: Float = scale / Float(max(drawableSize.width, drawableSize.height))

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
                
                var deltaX = cos(angle) * metalWidthPerPixel * (radius) * adjustment.x
                var deltaY = sin(angle) * metalWidthPerPixel * (radius) * adjustment.y
                
                let p1 = simd_float2(x: center.x + deltaX, y: center.y + deltaY)
                
                
                deltaX = cos(angle2) * metalWidthPerPixel * (radius) * adjustment.x
                deltaY = sin(angle2) * metalWidthPerPixel * (radius) * adjustment.y
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
                drawWithTetxure: drawWithTexture,
                orthoMatrix: orthoMatrix,
                hardness: hardness,
                scale: scale,
                textureOffset: textureOffset
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
            drawWithTexture: Bool = false,
        ) {
            drawArc(
                center: center,
                color: color,
                radius: radius,
                steps: steps,
                lineThickness: lineThickness,
                drawWithTexture: drawWithTexture
            )
        }
        
        func drawArc(
            center: simd_float2,
            color: SIMD4<Float>,
            radius: Float,
            startAngle: Float = 0,
            endAngle: Float = 360.0,
            steps: Int = 24,
            lineThickness: Float,
            drawWithTexture: Bool = false,
            hardness: Float = 0
            ) {
                
                let aspect = drawingInfo.imageAspectRatio
                let landscape = aspect > 1
                let adjustment: simd_float2 = landscape ?  simd_float2(1, aspect) : simd_float2(1/aspect, 1)


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
                    
                    var deltaX = cos(angle) * metalWidthPerPixel * (radius - lineThickness) * adjustment.x
                    var deltaY = sin(angle) * metalWidthPerPixel * (radius - lineThickness) * adjustment.y
                    
                    let p1Inside = simd_float2(x: center.x + deltaX, y: center.y + deltaY)
                    
                    deltaX = cos(angle) * metalWidthPerPixel  * (radius + lineThickness) * adjustment.x
                    deltaY = sin(angle) * metalWidthPerPixel * (radius + lineThickness) * adjustment.y
                    
                    let p1Outside = simd_float2(x: center.x + deltaX, y: center.y + deltaY)
                    
                    deltaX = cos(angle2) * metalWidthPerPixel * (radius - lineThickness) * adjustment.x
                    deltaY = sin(angle2) * metalWidthPerPixel * (radius - lineThickness) * adjustment.y
                    let p2Inside = simd_float2(x: center.x + deltaX, y: center.y + deltaY)
                    
                    deltaX = cos(angle2) * metalWidthPerPixel  * (radius + lineThickness) * adjustment.x
                    deltaY = sin(angle2) * metalWidthPerPixel * (radius + lineThickness) * adjustment.y
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
                    drawWithTetxure: drawWithTexture,
                    orthoMatrix: orthoMatrix,
                    hardness: hardness,
                    scale: scale,
                    textureOffset: textureOffset
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

        struct Endpoints {
            let p1: simd_float2
            let p2: simd_float2
        }

        func drawBox(
            center: simd_float2,
            color: SIMD4<Float>,
            width: Float,
            lineThickness: Float,
            orthoMatrix: float4x4,
            asDiamond: Bool = false) {
                let aspect = drawingInfo.imageAspectRatio
                let landscape = aspect > 1
                let adjustment: simd_float2 = landscape ?  simd_float2(1, 1/aspect) : simd_float2(1*aspect, 1)
                
                let diagonal = simd_float2(x: width / adjustment.x * metalWidthPerPixel, y: width / adjustment.y  * metalWidthPerPixel)
                let bottomLeft = center - diagonal
                let topRight = center + diagonal
                let topLeft = simd_float2(bottomLeft.x, topRight.y)
                let bottomRight = simd_float2(topRight.x, bottomLeft.y)
                let lines = [
                    Endpoints(p1: topLeft, p2: topRight),
                    Endpoints(p1: bottomLeft, p2: bottomRight),
                    Endpoints(p1: topLeft, p2: bottomLeft),
                    Endpoints(p1: topRight, p2: bottomRight),
                ]
                for line in lines {
                    drawThickLine(p1: line.p1, p2: line.p2, color: MetalColors.white, thickness: 4)
                    drawThickLine(p1: line.p1, p2: line.p2, color: MetalColors.black, thickness: 2)
                }
            }

        func drawSquare(
            center: simd_float2,
            color: SIMD4<Float>,
            width: Float,
            orthoMatrix: float4x4,
            asDiamond: Bool = false,
            hardness: Float = 0
        ) {
                
                let aspect = drawingInfo.imageAspectRatio
                let landscape = aspect > 1
                let adjustment: simd_float2 = landscape ?  simd_float2(1, 1/aspect) : simd_float2(1*aspect, 1)

                let width = width
                let center: simd_float2 = simd_float2(x: center.x, y: center.y)
                //let metalWidthPerPixel: Float = scale / Float(max(drawableSize.width, drawableSize.height))
                let yOffset = (metalWidthPerPixel * width) / adjustment.y
                let xOffset = metalWidthPerPixel * width  / adjustment.x
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
                    hardness: hardness,
                    scale: scale,
                    textureOffset: textureOffset
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
            orthoMatrix: float4x4,
            hardness: Float = 0
        ) {
            let thickness = thickness * scale
//            let metalWidthPerPixel: Float = scale / Float(max(drawableSize.width, drawableSize.height))
            
            let tipXOffset = (direction == .left ? -metalWidthPerPixel * thickness / 2 : 0)
            let tipYOffset = (direction == .down ? -metalWidthPerPixel * thickness / 2 : 0)
            
            let point = simd_float2(point.x + (direction == .left ? tipXOffset / 2 : 0), point.y + (direction == .down ? tipYOffset / 2 : 0))
            
            let deltaX = Float(sqrt(2)) / 2 * size * scale * metalWidthPerPixel
            let deltaY = Float(sqrt(2)) / 2 * size * scale * metalWidthPerPixel
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
                hardness: hardness,
                scale: scale,
                textureOffset: textureOffset
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
            thickness: Float,
            drawWithTexture: Bool = false,
            hardness: Float = 0
        ) {
            
            let aspect = drawingInfo.imageAspectRatio
            let landscape = aspect > 1
            let adjustment: simd_float2 = landscape ?  simd_float2(1, 1/aspect) : simd_float2(1*aspect, 1)
            let p1Tweaked = p1  * adjustment
            let p2Tweaked = p2  * adjustment
            
            
             

             
            
            let thickness = thickness * scale / Float(max(drawingInfo.drawableSize.width, drawingInfo.drawableSize.height))
            let dir = normalize(p2Tweaked - p1Tweaked)
            let normal = simd_float2(-dir.y, dir.x) * thickness
            
            
            let v0 = (p1Tweaked + normal) / adjustment
            let v1 = (p1Tweaked - normal) / adjustment
            let v2 = (p2Tweaked + normal) / adjustment
            let v3 = (p2Tweaked - normal) / adjustment
            let vertexes = [
                Vertex(position: v0, alpha: 1),
                Vertex(position: v1, alpha: 1),
                Vertex(position: v2, alpha: 1),
                Vertex(position: v3, alpha: 1),
            ]
            
            let verticiesSize = MemoryLayout<Vertex>.stride * 4
            let offset = allocateVerticiesInRing(byteCount: verticiesSize)
            let dst = vertexBuffer.contents().advanced(by: offset)
            dst.copyMemory(from: vertexes, byteCount: verticiesSize)
            encoder.setVertexBuffer(vertexBuffer, offset: offset, index: 0)
            
            uniforms = Uniforms(
                color: color,
                drawWithTetxure: drawWithTexture,
                orthoMatrix: orthoMatrix,
                hardness: hardness,
                scale: scale,
                textureOffset: textureOffset
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

