//
//  ViewModel.swift
//  DrawingApp
//
//  Created by Duncan Champney on 5/20/26.
//

import Foundation
import SwiftUI

enum GestureLocation: CustomStringConvertible {
    case inControlPoint(curveIndex: Int, pointIndex: Int)
    case inTransformHandle(handleType: TransformHandle)
    case outside
    
    var description: String {
        switch self {
            case .inControlPoint(let curveIndex, let pointIndex):
            return "inControlPoint(curveIndex: \(curveIndex), pointIndex: \(pointIndex))"
        case .outside:
            return "outside"
        case .inTransformHandle:
            return "inTransformHandle"
        }
    }
}

typealias GesturePointTuple = (point: CGPoint, gestureLocation: GestureLocation)

struct ViewModel {
    
    init(drawingInfo: DrawingInfo) {
        self.drawingInfo = drawingInfo
    }

    var gridSpacing: Float {
        Float(UserDefaults.standard.double(forKey: UserDefaultsKeys.gridSpacing.rawValue))
    }
    
    var useForceTouch: Bool {
        let value = UserDefaults.standard.bool(forKey: UserDefaultsKeys.useForceTouch.rawValue)
        return value
    }

    @ObservedObject var drawingInfo: DrawingInfo
    
    var curvePoints: [GesturePointTuple]  {
        var result: [GesturePointTuple] = []
        let curvesCount = drawingInfo.curves.count - 1
        
        for (curveIndex, aCurve) in drawingInfo.curves.reversed().enumerated() {
            for (pointIndex, aPoint) in aCurve.points.enumerated() {
                result.append((metalPointToView(aPoint.coord), .inControlPoint(curveIndex: curvesCount - curveIndex, pointIndex: pointIndex)))
            }
        }
        return result
    }
    
    var tranformHandlePoints: [GesturePointTuple] {
        var result: [GesturePointTuple] = []
        guard let transformModeValue = drawingInfo.transformModeValues else { return result }
        result.append( GesturePointTuple(metalPointToView(transformModeValue.rotationPoint), .inTransformHandle(handleType: .rotationCenter)))
        let dragHandles = transformModeValue.dragHandles
        for aHandle in dragHandles {
            result.append( GesturePointTuple(metalPointToView(aHandle.coord), .inTransformHandle(handleType: aHandle.handleType)))
        }
      return result
    }
    
    func brushSizeForEvent(_ event: GestureEvent) -> Float? {
        var brushSize: Float?  = drawingInfo.brushSettings.size
        guard useForceTouch else {
            return drawingInfo.brushSettings.size
        }
        if let pressure = event.pressure {
            if let pencilData = event.pencilData {
                let force = pressure / sin(pencilData.altitudeAngle)
                brushSize = Float(force) * (maxThickness - minThickness) + minThickness
            } else {
                brushSize = Float(pressure) * (maxThickness - minThickness) + minThickness
            }
        }
        return brushSize
    }

    func dragSelectionBy(_ vector: SIMD2<Float>, moveRotationCenter: Bool = true) {
        for aPoint in drawingInfo.selectedPoints {
            let theCurve = drawingInfo.curves[aPoint.curveIndex]
            var thePoint = theCurve.points[aPoint.pointIndex]
            thePoint.coord += vector
            drawingInfo.curves[aPoint.curveIndex].points[aPoint.pointIndex] = thePoint
        }
        if drawingInfo.transformSelection, var transformModeValues = drawingInfo.transformModeValues {
            transformModeValues.topLeft +=  vector
            transformModeValues.topRight +=  vector
            transformModeValues.bottomLeft +=  vector
            transformModeValues.bottomRight +=  vector
            if moveRotationCenter {
                transformModeValues.rotationPoint += vector
            }
            for index in 0 ..< transformModeValues.dragHandles.count {
                transformModeValues.dragHandles[index] = DragHandle(coord: transformModeValues.dragHandles[index].coord + vector, handleType: transformModeValues.dragHandles[index].handleType)
            }
            drawingInfo.transformModeValues = transformModeValues
        }
    }
    
    // MARK: - Gesture recognizer callbacks
    
   func handleTap(location: CGPoint, modifiers: GestureModifierKeys = []) {

        if let target = getGestureLocation(touchLocation: location) {
            switch target.gestureLocation {
            case .inControlPoint(let curveIndex, let pointIndex):
                let tappedPoint = SelectedPoint(curveIndex: curveIndex, pointIndex: pointIndex)

                    if drawingInfo.selectedPoints.contains(tappedPoint) {
                        drawingInfo.selectedPoints.remove(tappedPoint)
                        if drawingInfo.selectedPoints.isEmpty {
                            drawingInfo.drawingMode = .idle
                        }
                    } else {
                        drawingInfo.drawingMode = .editingCurve
                        if modifiers.contains(.shift) {
                            drawingInfo.selectedPoints.insert(tappedPoint)
                        } else {
                            drawingInfo.selectedPoints = [tappedPoint]
                        }
                    }
            case .inTransformHandle:
                break;
            case .outside: break
            }
        } else {
            if drawingInfo.drawingMode == .editingCurve,
               drawingInfo.selectedPoints.count == 1,
               let selectedPoint = drawingInfo.selectedPoints.first {
                
                var thisCurve = drawingInfo.curves[selectedPoint.curveIndex]
                let newlocation = viewPointToMetal(location)
                let newPoint = CatmullRomPoint(
                    coord: newlocation,
                    pointType: .smooth,
                    pointRadius: drawingInfo.brushSettings.size)

                if selectedPoint.pointIndex == thisCurve.points.count - 1 {
                    //append point to end of curve.
                    thisCurve.points.append(newPoint)
                    drawingInfo.selectedPoints = [SelectedPoint(curveIndex: selectedPoint.curveIndex, pointIndex: thisCurve.points.count - 1)]
                    drawingInfo.curves[selectedPoint.curveIndex] = thisCurve
                } else if selectedPoint.pointIndex == 0 {
                    thisCurve.points.insert(newPoint, at: 0)
                    drawingInfo.curves[selectedPoint.curveIndex] = thisCurve
                } else {
                    let coords = thisCurve.points[selectedPoint.pointIndex].coord
                    let firstPoint = thisCurve.points[selectedPoint.pointIndex]

                    let newCurve = CatmullRomCurve(color: thisCurve.color,
                                                   radius: drawingInfo.brushSettings.size,
                                                   outlineColor: nil,
                                                   points: [firstPoint, newPoint],
                                                   hardness:  drawingInfo.brushSettings.lineHardness
                    )
                    drawingInfo.selectedPoints = [SelectedPoint(curveIndex: drawingInfo.curves.count, pointIndex: 1)]
                    drawingInfo.curves.append(newCurve)
                    drawingInfo.drawingMode = .editingCurve
                }

            } else {
                //print("Single-tap not on a known location.")
                
                let coords = viewPointToMetal(location)
                let point =  CatmullRomPoint(coord: coords,
                                             pointType: .smooth,
                                             pointRadius: drawingInfo.brushSettings.size)

                let newCurve = CatmullRomCurve(color: drawingInfo.brushSettings.color,
                                               radius: drawingInfo.brushSettings.size,
                                               outlineColor: nil,
                                               points: [point],
                                               hardness:  drawingInfo.brushSettings.lineHardness
                )
                drawingInfo.selectedPoints = [SelectedPoint(curveIndex: drawingInfo.curves.count, pointIndex: 0)]
                drawingInfo.curves.append(newCurve)
                drawingInfo.drawingMode = .editingCurve

            }
        }
    }
    
    func handleTwoFingerTap(location: CGPoint) {
        if let target = getGestureLocation(touchLocation: location, slopDistance: 40) {
            switch target.gestureLocation {
            case .inControlPoint(let curveIndex, let pointIndex):
                let tappedPoint = SelectedPoint(curveIndex: curveIndex, pointIndex: pointIndex)
                let curve = drawingInfo.curves[curveIndex]
                
                drawingInfo.drawingMode = .editingCurve
                
                //If the point was already selected, deselect it.
                if drawingInfo.selectedPoints.contains(tappedPoint) {
                    drawingInfo.selectedPoints.remove(tappedPoint)
                    if drawingInfo.selectedPoints.isEmpty {
                        drawingInfo.drawingMode = .idle
                    }
                } else {
                    //Insert the point in the list of selected points.
                    drawingInfo.drawingMode = .editingCurve
                    drawingInfo.selectedPoints.insert(tappedPoint)
                }

//                var newSelection = Set<SelectedPoint>()
//                for pointIndex in 0..<curve.points.count {
//                    newSelection.insert(SelectedPoint(curveIndex: curveIndex, pointIndex: pointIndex))
//                }
//                drawingInfo.selectedPoints = newSelection
            case .inTransformHandle:
                print("Two-finger tapped on a transform handle")
            case .outside:
                break
            }
        } else {
            drawingInfo.selectedPoints = []
            drawingInfo.drawingMode = .idle
        }
    }

    func handleDoubleTap(location: CGPoint) {
        if let target = getGestureLocation(touchLocation: location) {
            //print("Double-tap in \(target.gestureLocation.description)")
            let gestureLocation = target.gestureLocation
            switch gestureLocation {
            case .inControlPoint(let curveIndex, let pointIndex):
                var changed = drawingInfo.curves[curveIndex].points[pointIndex]
                changed.pointType = (changed.pointType == .corner) ? .smooth : .corner
                drawingInfo.curves[curveIndex].points[pointIndex] = changed
            case .inTransformHandle(let handleType):
                if handleType != .transformRect && handleType != .rotationCenter && handleType != .outside {
                    if drawingInfo.transformModeValues?.selectedTransformHandle == handleType {
                        print("drawing handle \(drawingInfo.transformModeValues!.selectedTransformHandle!) deselected.")
                        drawingInfo.transformModeValues?.selectedTransformHandle = nil
                    } else {
                        drawingInfo.transformModeValues?.selectedTransformHandle = handleType
                        print("drawing handle \(handleType) selected.")
                    }
                    
                }
            default:
                break
            }
        } else {
            print("double-tap location not found")
        }
    }
        
    func handlePinchRotateBegan(center: CGPoint) {
        drawingInfo.registerUndo()
        drawingInfo.suppressUndo = true
    }

    // rotation in radians
    func handlePinchRotateChanged(scale: CGFloat, rotation: CGFloat, center: CGPoint) {
        
        func transformPoint(_ point: simd_float2) -> simd_float2 {
            let viewPt = metalPointToView(point)
            let dx = viewPt.x - center.x
            let dy = viewPt.y - center.y
            let rx = cosR * dx - sinR * dy
            let ry = sinR * dx + cosR * dy
            let sx = rx * scale
            let sy = ry * scale
            let newViewPt = CGPoint(x: sx + center.x, y: sy + center.y)
            return viewPointToMetal(newViewPt)
        }
        
        //TODO: Put this test back
//        guard !drawingInfo.transformSelection && !drawingInfo.selectedPoints.isEmpty else { return }

        guard !drawingInfo.selectedPoints.isEmpty else { return }

        let cosR = cos(rotation)
        let sinR = sin(rotation)
        for aPoint in drawingInfo.selectedPoints {
            let coord = drawingInfo.curves[aPoint.curveIndex].points[aPoint.pointIndex].coord
            drawingInfo.curves[aPoint.curveIndex].points[aPoint.pointIndex].coord =  transformPoint(coord)

            if let radius = drawingInfo.curves[aPoint.curveIndex].points[aPoint.pointIndex].pointRadius {
                drawingInfo.curves[aPoint.curveIndex].points[aPoint.pointIndex].pointRadius = radius * Float(scale)
            }
            
        }
        if drawingInfo.transformSelection,
            var transformModeValues = drawingInfo.transformModeValues {
            transformModeValues.topLeft = transformPoint(transformModeValues.topLeft)
            transformModeValues.topRight = transformPoint(transformModeValues.topRight)
            transformModeValues.bottomLeft = transformPoint(transformModeValues.bottomLeft)
            transformModeValues.bottomRight = transformPoint(transformModeValues.bottomRight)
            transformModeValues.rotationPoint = transformPoint(transformModeValues.rotationPoint)
            for index in 0 ..< transformModeValues.dragHandles.count {
                transformModeValues.dragHandles[index] = DragHandle(coord: transformPoint(transformModeValues.dragHandles[index].coord), handleType: transformModeValues.dragHandles[index].handleType)
            }
            drawingInfo.transformModeValues = transformModeValues
        }

    }

    func handlePinchRotateEnded() {
        drawingInfo.suppressUndo = false
    }

    func handleDragBegan(location: CGPoint, event: GestureEvent) {
        drawingInfo.registerUndo()
        drawingInfo.suppressUndo = true

        if event.modifierKeys.contains(GestureModifierKeys.shift) {
            print("Shift drag begun")
        }
        if let target = getGestureLocation(touchLocation: location) {
            drawingInfo.drawingMode = .editingCurve
            switch target.gestureLocation {
            case .inControlPoint(let curveIndex, let pointIndex):
                drawingInfo.isDragging = true
                drawingInfo.lastDragLocation = location
                drawingInfo.draggingState = target.gestureLocation
                let newPoint = SelectedPoint(curveIndex: curveIndex, pointIndex: pointIndex)
                if event.modifierKeys.contains(GestureModifierKeys.shift) {
                    drawingInfo.selectedPoints.insert(newPoint)
                } else if !drawingInfo.selectedPoints.contains(newPoint) {
                    drawingInfo.selectedPoints = [newPoint]
                }
            case .inTransformHandle(let handleType):
                    drawingInfo.isDragging = true
                    drawingInfo.lastDragLocation = location
                    drawingInfo.draggingState = target.gestureLocation

            default:
                break
            }
        } else {
            let coords = viewPointToMetal(location)

            if drawingInfo.drawingMode == .editingCurve,
               drawingInfo.selectedPoints.count == 1 {
                let activeCurveIndex = drawingInfo.selectedPoints.first!.curveIndex
                let activePointIndex = drawingInfo.selectedPoints.first!.pointIndex
                let point = CatmullRomPoint(coord: coords,
                                            pointType: .smooth,
                                            pointRadius: drawingInfo.brushSettings.size
                )

                switch activePointIndex {
                case 0:
                    drawingInfo.curves[activeCurveIndex].points.reverse()
                    fallthrough
                case drawingInfo.curves[activeCurveIndex].points.count - 1:
                    drawingInfo.drawingMode = .creatingCurve
                    drawingInfo.curves[activeCurveIndex].points.append(point)
                    drawingInfo.selectedPoints = [SelectedPoint(curveIndex: activeCurveIndex, pointIndex: drawingInfo.curves[activeCurveIndex].points.count - 1)]
                    drawingInfo.isDragging = true
                    drawingInfo.lastDragLocation = location
                    return
                default:
                    let activePoint = drawingInfo.curves[activeCurveIndex].points[activePointIndex]
                    let newCurve = CatmullRomCurve(color: drawingInfo.brushSettings.color,
                                                   radius: drawingInfo.brushSettings.size,
                                                   outlineColor: nil,
                                                   points: [activePoint, point],
                                                   hardness:  drawingInfo.brushSettings.lineHardness
                    )
                    drawingInfo.selectedPoints = [SelectedPoint(curveIndex: drawingInfo.curves.count, pointIndex: 1)]
                    drawingInfo.curves.append(newCurve)
                    drawingInfo.drawingMode = .creatingCurve
                    drawingInfo.lastDragLocation = location
                    drawingInfo.isDragging = true
                    return
                }
            }

            let point = CatmullRomPoint(coord: coords,
                                        pointType: .smooth,
                                        pointRadius: brushSizeForEvent(event))
            let newCurve = CatmullRomCurve(color: drawingInfo.brushSettings.color,
                                           radius: drawingInfo.brushSettings.size,
                                           outlineColor: nil,
                                           points: [point],
                                           hardness:  drawingInfo.brushSettings.lineHardness
            )
            drawingInfo.selectedPoints = [SelectedPoint(curveIndex: drawingInfo.curves.count, pointIndex: 0)]
            drawingInfo.curves.append(newCurve)
            drawingInfo.drawingMode = .creatingCurve
            drawingInfo.lastDragLocation = location
            drawingInfo.isDragging = true
        }
    }

    func handleDragChanged(location: CGPoint, event: GestureEvent) {
        guard let lastDragLocation = drawingInfo.lastDragLocation else { return }

        if event.modifierKeys.contains(GestureModifierKeys.shift) {
            print("Shift drag in progress")
        }

        switch drawingInfo.drawingMode {

        case .creatingCurve:

            guard drawingInfo.selectedPoints.count == 1 else {
                print("No active curve")
                return
            }
            let selectedPoint = drawingInfo.selectedPoints.first!
            let curveIndex = selectedPoint.curveIndex
            guard distanceSquardBetween(p1: lastDragLocation, p2: location) > 9 else {
                return
            }

            let newlocation = viewPointToMetal(location)
            let brushSize = brushSizeForEvent( event)

            let newPoint = CatmullRomPoint(
                coord: newlocation,
                pointType: .smooth,
                pointRadius: brushSize)
            drawingInfo.curves[curveIndex].points.append(newPoint)
            drawingInfo.lastDragLocation = location
        case .idle:
            break
        case .editingCurve:

            let deltaX = -2.0 * Float((lastDragLocation.x - location.x) / drawingInfo.imageSize.width)
            let deltaY = 2.0 * Float((lastDragLocation.y - location.y) / drawingInfo.imageSize.height)
            let vector = SIMD2<Float>(deltaX, deltaY)

            switch drawingInfo.draggingState {
            case .inControlPoint:
                dragSelectionBy(vector)
                drawingInfo.lastDragLocation = location
            case .inTransformHandle(let handleType):
                switch handleType {
                case .transformRect:
                    let rotationCenter = metalPointToView(drawingInfo.transformModeValues!.rotationPoint)
                    dragSelectionBy(vector, moveRotationCenter: pointIsInTransformRect(rotationCenter))
                    drawingInfo.lastDragLocation = location

                case .rotationCenter:

                    guard var transformModeValues = drawingInfo.transformModeValues else { return }
                    let newRotationCenter = transformModeValues.rotationPoint + vector
                    let transformRectCenter = transformModeValues.transformRectCenter
                    let pointsToCheck = [transformRectCenter] + transformModeValues.dragHandles.map { $0.coord }
                    var pointToUse: simd_float2? = nil
                    for aPoint in pointsToCheck {
                        if distanceBetween(p1: newRotationCenter, p2: aPoint) < drawingInfo.metalWidthPerPixel * 30 {
                            pointToUse = aPoint
                        }
                    }
                    transformModeValues.rotationPoint = pointToUse ?? newRotationCenter
                    drawingInfo.transformModeValues = transformModeValues
                    drawingInfo.lastDragLocation = location
                case .outside:
                    guard let transformModeValues = drawingInfo.transformModeValues else { return }
                    let rotationCenter = metalPointToView(transformModeValues.rotationPoint)
                    let oldAngle = atan2(Double(rotationCenter.y - lastDragLocation.y), Double(rotationCenter.x - lastDragLocation.x))
                    let newAngle = atan2(Double(rotationCenter.y - location.y), Double(rotationCenter.x - location.x))
                    let angleDelta = CGFloat(newAngle - oldAngle)
                    handlePinchRotateChanged(scale: 1.0, rotation: angleDelta, center: rotationCenter)
                    drawingInfo.lastDragLocation = location
                case .topLeft, .topMiddle, .topRight, .middleLeft, .middleRight, .bottomLeft, .bottomMiddle, .bottomRight:
                    adjustSelection(by: vector, forHandleType: handleType)
                    drawingInfo.lastDragLocation = location
                default:
                    break
                }
            default:
                break
            }
        }
    }
    
    func adjustSelection(by vector: SIMD2<Float>, forHandleType handleType:  TransformHandle ) {
        
        // xxx
        guard var transformModeValues = drawingInfo.transformModeValues else { return }
        let distanceToCenter = distanceBetween(p1: transformModeValues.rotationPoint, p2: transformModeValues.transformRectCenter)
        let rotationPointWasInCenter = distanceToCenter < metalWidthPerPixel


        // Basis vectors of the bounding parallelogram in metal space
        let u = transformModeValues.topRight - transformModeValues.topLeft
        let v = transformModeValues.bottomLeft - transformModeValues.topLeft
        let det = u.x * v.y - v.x * u.y
        guard abs(det) > 1e-6 else { return }
        let invDet = 1.0 / det

        let anchor: simd_float2
        let scaleLocalX: Bool
        let scaleLocalY: Bool

        let midBottom = (transformModeValues.bottomLeft + transformModeValues.bottomRight) * 0.5
        let midTop = (transformModeValues.topLeft + transformModeValues.topRight) * 0.5
        let midLeft = (transformModeValues.topLeft + transformModeValues.bottomLeft) * 0.5
        let midRight = (transformModeValues.topRight + transformModeValues.bottomRight) * 0.5

        switch handleType {
        case .topLeft:
            anchor = transformModeValues.bottomRight; scaleLocalX = true; scaleLocalY = true
        case .topRight:
            anchor = transformModeValues.bottomLeft; scaleLocalX = true; scaleLocalY = true
        case .bottomLeft:
            anchor = transformModeValues.topRight; scaleLocalX = true; scaleLocalY = true
        case .bottomRight:
            anchor = transformModeValues.topLeft; scaleLocalX = true; scaleLocalY = true
        case .topMiddle:
            anchor = midBottom; scaleLocalX = false; scaleLocalY = true
        case .bottomMiddle:
            anchor = midTop; scaleLocalX = false; scaleLocalY = true
        case .middleLeft:
            anchor = midRight; scaleLocalX = true; scaleLocalY = false
        case .middleRight:
            anchor = midLeft; scaleLocalX = true; scaleLocalY = false
        default:
            return
        }

        // Decompose offset into (u, v) basis using the matrix inverse
        func decompose(_ offset: simd_float2) -> (s: Float, t: Float) {
            let s = (offset.x * v.y - offset.y * v.x) * invDet
            let t = (offset.y * u.x - offset.x * u.y) * invDet
            return (s, t)
        }

        guard let handleIndex = transformModeValues.dragHandles.firstIndex(where: { $0.handleType == handleType }) else { return }
        let handleLocal = decompose(transformModeValues.dragHandles[handleIndex].coord - anchor)
        let vectorLocal = decompose(vector)

        let sx: Float = scaleLocalX && abs(handleLocal.s) > 1e-6 ? (handleLocal.s + vectorLocal.s) / handleLocal.s : 1.0
        let sy: Float = scaleLocalY && abs(handleLocal.t) > 1e-6 ? (handleLocal.t + vectorLocal.t) / handleLocal.t : 1.0

        func scalePoint(_ pt: simd_float2) -> simd_float2 {
            let local = decompose(pt - anchor)
            return anchor + (local.s * sx) * u + (local.t * sy) * v
        }

        for aPoint in drawingInfo.selectedPoints {
            let coord = drawingInfo.curves[aPoint.curveIndex].points[aPoint.pointIndex].coord
            drawingInfo.curves[aPoint.curveIndex].points[aPoint.pointIndex].coord = scalePoint(coord)
        }

        transformModeValues.topLeft = scalePoint(transformModeValues.topLeft)
        transformModeValues.topRight = scalePoint(transformModeValues.topRight)
        transformModeValues.bottomLeft = scalePoint(transformModeValues.bottomLeft)
        transformModeValues.bottomRight = scalePoint(transformModeValues.bottomRight)

        for index in 0 ..< transformModeValues.dragHandles.count {
            let handle = transformModeValues.dragHandles[index]
            transformModeValues.dragHandles[index] = DragHandle(coord: scalePoint(handle.coord), handleType: handle.handleType)
        }

        // If the rotation point was in the center of the transform rect when we started,
        // keep it in the center of the transform rect
        if rotationPointWasInCenter {
            transformModeValues.rotationPoint = transformModeValues.transformRectCenter
        }
        drawingInfo.transformModeValues = transformModeValues

    }
    func handlePlusOrMinusKey(_ keyPress: KeyPress) {
        
        let shift = keyPress.modifiers.contains(.shift)
        let changeSign: Float = (keyPress.key == .plus || keyPress.key == .equals) ? 1.0 : -1.0
        let pixelChange: Float = changeSign * (shift ? 20.0 : 2.0)

        if drawingInfo.transformSelection,
            let transformModeValues = drawingInfo.transformModeValues {
            
            let selectionWidth  = max( abs(transformModeValues.topRight.x - transformModeValues.topLeft.x) / drawingInfo.metalPixelSize.x,
                                       abs(transformModeValues.topRight.y - transformModeValues.topLeft.y) / drawingInfo.metalPixelSize.y)
            let newWidth = selectionWidth + pixelChange
            let scaleChange = CGFloat(newWidth/selectionWidth)
            
            if let transformHandle = transformModeValues.selectedTransformHandle {
                let scalingPoint: simd_float2 = switch transformHandle {
                case .topLeft:
                    transformModeValues.bottomRight
                case .topMiddle:
                    transformModeValues.bottomMiddle
                case .topRight:
                    transformModeValues.bottomLeft
                case .middleLeft:
                    transformModeValues.middleRight
                case .middleRight:
                    transformModeValues.middleLeft
                case .bottomLeft:
                    transformModeValues.topRight
                case .bottomMiddle:
                    transformModeValues.topMiddle
                case .bottomRight:
                    transformModeValues.topLeft
                default:
                    transformModeValues.transformRectCenter
                }
                Task { @MainActor in
                    handlePinchRotateChanged(scale: scaleChange, rotation: .zero, center: metalPointToView(scalingPoint))
                }
            } else {
                //Scale everything around the rotationPoint
                Task { @MainActor in
                    handlePinchRotateChanged(scale: scaleChange, rotation: .zero, center: metalPointToView(transformModeValues.rotationPoint))
                }
            }
        } else {
            if let selectedPointsInfo = drawingInfo.selectedPointsInfo {
                let selectionWidth  = max(abs(selectedPointsInfo.size.x / drawingInfo.metalPixelSize.x), abs(selectedPointsInfo.size.y / drawingInfo.metalPixelSize.y))
                let newWidth = selectionWidth + pixelChange
                let scaleChange = CGFloat(newWidth/selectionWidth)

                Task { @MainActor in
                    handlePinchRotateChanged(scale: scaleChange, rotation: .zero, center: metalPointToView(selectedPointsInfo.center))
                }
            }

        }
    }
    
    func handleArrowKey(_ keyPress: KeyPress) {
        let  metalWidthPerPixel = drawingInfo.scale / Float(max(drawingInfo.drawableSize.width, drawingInfo.drawableSize.height))


        let shift = keyPress.modifiers.contains(.shift)
        var vector: SIMD2<Float>
        switch keyPress.key {
        case .leftArrow:
            vector = .init(x: -drawingInfo.metalPixelSize.x, y: 0)
        case .rightArrow:
            vector = .init(x: drawingInfo.metalPixelSize.x, y: 0)
        case .upArrow:
            vector = .init(x: 0, y: drawingInfo.metalPixelSize.y)
        case .downArrow:
            vector = .init(x: 0, y: -drawingInfo  .metalPixelSize.y)
        default:
            return
            
        }
        if shift {
            vector *= 10
        }
        if let transformHandle = drawingInfo.transformModeValues?.selectedTransformHandle {
            // ignore left an right arrow for bottomMiddle and topMiddle
            if (keyPress.key == .leftArrow || keyPress.key == .rightArrow ) &&
                (transformHandle == .bottomMiddle || transformHandle == .topMiddle) {
                return
            }
                
            // Ignore up and down arrow for middleLeft and middleRight
            if (keyPress.key == .upArrow || keyPress.key == .downArrow) &&
                (transformHandle == .middleLeft || transformHandle == .middleRight) {
                return
            }
            
            Task { @MainActor in
                adjustSelection(by: vector, forHandleType: transformHandle)
                let  metalWidthPerPixel = drawingInfo.scale / Float(max(drawingInfo.drawableSize.width, drawingInfo.drawableSize.height))

                if let rotationPoint = drawingInfo.transformModeValues?.rotationPoint,
                let transformRectCenter = drawingInfo.transformModeValues?.transformRectCenter {
                    let distanceToCenter = distanceBetween(p1: rotationPoint, p2: transformRectCenter)
                }
            }
        } else {
            Task { @MainActor in
                dragSelectionBy(vector)
            }
        }
    }
    
    func handleDragEnded() {
        defer {
            drawingInfo.suppressUndo = false
        }
        if drawingInfo.drawingMode == .creatingCurve {
            let activeCurveIndex = drawingInfo.selectedPoints.first!.curveIndex
            drawingInfo.drawingMode = .editingCurve
            let curvePointsCount = drawingInfo.curves[activeCurveIndex].points.count
            if curvePointsCount == 1 {
                drawingInfo.selectedPoints = [SelectedPoint(curveIndex: activeCurveIndex, pointIndex: 0)]
            } else {
                drawingInfo.selectedPoints = []
                let curve = drawingInfo.curves[activeCurveIndex]
                let paredCurve = parePoints(curve, autoTerminate: true, maxError: 0.01)
                let startingPointCount = curve.points.count
                let paredCurvePointCount = paredCurve.points.count
                let percent = Float(startingPointCount - paredCurvePointCount) / Float(startingPointCount) * 100
                let percentString = String(format: "%.1f", percent)
                print("pared curve from \(curve.points.count) to \(paredCurve.points.count) points. \(percentString)% reduction.")
                drawingInfo.curves[activeCurveIndex] = paredCurve
            }
        }
        drawingInfo.isDragging = false
        drawingInfo.lastDragLocation = nil
    }

    func handleDeletePoint() {
        drawingInfo.deletePoints()
    }
    func matchPoint(_  tapPoint: CGPoint, inPoints points: [GesturePointTuple], slopDistance: CGFloat = 20) -> GesturePointTuple? {
        let matches = points
        // find all the points that are inside the "slop distance"
            .filter {
                tapPoint.x > $0.point.x - slopDistance && tapPoint.x < $0.point.x + slopDistance &&
                tapPoint.y > $0.point.y - slopDistance && tapPoint.y < $0.point.y + slopDistance
            }
        
        //If the rotation center is in the list, return that.
        if let rotationCenter = matches.first( where: { point in
            if case .inTransformHandle(handleType: .rotationCenter) = point.gestureLocation {
                return true
            }
            return false
        }) {
            return rotationCenter
        }
        return matches
            //Calculate the distance of each matching point from the tap point
            .map { ($0, distanceSquardBetween(p1: tapPoint, p2: $0.point)) }
            //Sort the points closest-to-furthest
            .sorted(by: { $0.1 < $1.1 })
            .first?.0
    }

    func metalPointToView(_ metalPoint: SIMD2<Float>) -> CGPoint {
        return CGPoint(
            x: CGFloat(metalPoint.x.interpolated(from: -1...1, to: 0...Float(drawingInfo.viewportSize.width))),
            y: drawingInfo.viewportSize.height - CGFloat(metalPoint.y.interpolated(from: -1...1, to: 0...Float(drawingInfo.viewportSize.height))))
    }

    func viewPointToMetal(_ point: CGPoint) -> SIMD2<Float> {
        let x = Float(point.x).interpolated(from: 0.0...Float(drawingInfo.viewportSize.width), to: -1...1)
        let y = 0 - Float(point.y).interpolated(from: 0.0...Float(drawingInfo.viewportSize.height), to: -1...1)
        return SIMD2<Float> (
            x: x,
            y: y)
    }


    // Returns true if point p is inside the convex quadrilateral defined by vertices a, b, c, d (in order).
    func pointInQuad(_ p: CGPoint, a: CGPoint, b: CGPoint, c: CGPoint, d: CGPoint) -> Bool {
        func cross(_ origin: CGPoint, _ v1: CGPoint, _ v2: CGPoint) -> CGFloat {
            (v1.x - origin.x) * (v2.y - origin.y) - (v1.y - origin.y) * (v2.x - origin.x)
        }
        let c0 = cross(a, b, p)
        let c1 = cross(b, c, p)
        let c2 = cross(c, d, p)
        let c3 = cross(d, a, p)
        return (c0 >= 0 && c1 >= 0 && c2 >= 0 && c3 >= 0) ||
               (c0 <= 0 && c1 <= 0 && c2 <= 0 && c3 <= 0)
    }

    func pointIsInTransformRect(_ point: CGPoint) -> Bool {
        
        guard let tmv = drawingInfo.transformModeValues  else { return false }
            let a = metalPointToView(tmv.topLeft)
            let b = metalPointToView(tmv.topRight)
            let c = metalPointToView(tmv.bottomRight)
            let d = metalPointToView(tmv.bottomLeft)
            return pointInQuad(point, a: a, b: b, c: c, d: d)
    }
    
    func getGestureLocation(touchLocation: CGPoint, slopDistance: CGFloat = 20) -> GesturePointTuple? {

        var result: GesturePointTuple?
        if drawingInfo.transformSelection {
            result = matchPoint(touchLocation, inPoints: tranformHandlePoints, slopDistance: slopDistance)
            if let result,
               case .inTransformHandle(let handleType) = result.gestureLocation
            {
                //print("Gesture \(handleType.rawValue)")
            }
            else {
                if pointIsInTransformRect(touchLocation) {
                    result = GesturePointTuple(touchLocation, .inTransformHandle(handleType: .transformRect))
                    //print("Gesture .\(result!.gestureLocation), .transformRect")
                } else {
                    result = GesturePointTuple(touchLocation, .inTransformHandle(handleType: .outside))
                }
            }
        } else {
            result = matchPoint(touchLocation, inPoints: curvePoints, slopDistance: slopDistance)
            if let result {
                //print("Gesture \(result.gestureLocation)")
            }
        }
        return result
    }

    // MARK: - Point Reduction (Ramer–Douglas–Peucker)

    /// Reduces the number of control points in a curve using the Ramer–Douglas–Peucker algorithm.
    ///
    /// - Parameters:
    ///   - curve: The input curve to simplify.
    ///   - autoTerminate: If `true`, iteratively searches for the largest epsilon that keeps
    ///     the smoothed-curve error below `maxError`. If `false`, uses the provided `epsilon`.
    ///   - epsilon: The RDP distance threshold. Used when `autoTerminate` is `false`.
    ///     Defaults to `nil`, which uses `0.01`.
    ///   - granularity: The granularity passed to `smoothPointsInArray` when measuring error
    ///     in auto-terminate mode.
    ///   - maxError: The maximum allowed Hausdorff distance between the original and reduced
    ///     smoothed curves. Used when `autoTerminate` is `true`.
    public func parePoints(
        _ curve: CatmullRomCurve,
        autoTerminate: Bool,
        epsilon: Float? = nil,
        granularity: Int = 8,
        maxError: Float = 0.005
    ) -> CatmullRomCurve {
        guard curve.points.count > 2 else { return curve }

        if autoTerminate {
            return parePointsAuto(curve, granularity: granularity, maxError: maxError)
        } else {
            let eps = epsilon ?? 0.01
            let keptIndices = rdpReduce(curve.points, epsilon: eps)
            var result = curve
            result.points = redistributeRadii(
                originalPoints: curve.points,
                keptIndices: keptIndices,
                defaultRadius: drawingInfo.brushSettings.size
            )
            return result
        }
    }

    // MARK: Auto-terminate mode

    public func parePointsAuto(
        _ curve: CatmullRomCurve,
        granularity: Int,
        maxError: Float
    ) -> CatmullRomCurve {
        let referenceControlPoints: [SmoothedCurvePoint] = catmullRomControlPoints(for: curve)
        let (referenceSmoothed, _) = smoothPointsInArray(
            referenceControlPoints, granularity: granularity, adjustGranularity: false
        )

        let coords = curve.points.map { $0.coord }
        var lo: Float = 0
        var hi = boundingBoxDiagonal(coords)
        var bestIndices = Array(0..<curve.points.count)

        for _ in 0..<20 {
            let mid = (lo + hi) / 2
            let candidateIndices = rdpReduce(curve.points, epsilon: mid)

            if candidateIndices.count < 2 {
                hi = mid
                continue
            }

            var candidateCurve = curve
            candidateCurve.points = candidateIndices.map { curve.points[$0] }
            let candidateControlPoints = catmullRomControlPoints(for: candidateCurve)
            let (candidateSmoothed, _) = smoothPointsInArray(
                candidateControlPoints, granularity: granularity, adjustGranularity: false
            )

            let error = directedHausdorff(from: referenceSmoothed, to: candidateSmoothed)

            if error <= maxError {
                bestIndices = candidateIndices
                lo = mid
            } else {
                hi = mid
            }
        }

        var result = curve
        result.points = redistributeRadii(
            originalPoints: curve.points,
            keptIndices: bestIndices,
            defaultRadius: drawingInfo.brushSettings.size
        )
        return result
    }

    // MARK: Radius redistribution

    private func redistributeRadii(
        originalPoints: [CatmullRomPoint],
        keptIndices: [Int],
        defaultRadius: Float
    ) -> [CatmullRomPoint] {
        var result = keptIndices.map { originalPoints[$0] }
        let keptSet = Set(keptIndices)

        for i in 0..<originalPoints.count {
            guard !keptSet.contains(i) else { continue }
            guard let removedRadius = originalPoints[i].pointRadius else { continue }

            if let leftResultIndex = keptIndices.lastIndex(where: { $0 < i }) {
                let currentRadius = result[leftResultIndex].pointRadius ?? defaultRadius
                result[leftResultIndex].pointRadius = currentRadius * 2.0 / 3.0 + removedRadius / 3.0
            }

            if let rightResultIndex = keptIndices.firstIndex(where: { $0 > i }) {
                let currentRadius = result[rightResultIndex].pointRadius ?? defaultRadius
                result[rightResultIndex].pointRadius = currentRadius * 2.0 / 3.0 + removedRadius / 3.0
            }
        }

        return result
    }

    // MARK: RDP core

    private func rdpReduce(_ points: [CatmullRomPoint], epsilon: Float) -> [Int] {
        guard points.count > 2 else {
            return Array(0..<points.count)
        }

        let coords = points.map { $0.coord }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true

        for (i, point) in points.enumerated() {
            if point.pointType == .corner { keep[i] = true }
        }

        let anchors = keep.enumerated().compactMap { $0.element ? $0.offset : nil }
        for i in 0..<(anchors.count - 1) {
            rdpRecurse(coords: coords, epsilon: epsilon,
                       start: anchors[i], end: anchors[i + 1], keep: &keep)
        }

        return keep.enumerated().compactMap { $0.element ? $0.offset : nil }
    }

    private func rdpRecurse(
        coords: [simd_float2], epsilon: Float,
        start: Int, end: Int, keep: inout [Bool]
    ) {
        guard end - start > 1 else { return }

        var maxDist: Float = 0
        var maxIndex = start

        for i in (start + 1)..<end {
            let dist = pointToSegmentDistance(coords[i], coords[start], coords[end])
            if dist > maxDist {
                maxDist = dist
                maxIndex = i
            }
        }

        if maxDist > epsilon {
            keep[maxIndex] = true
            rdpRecurse(coords: coords, epsilon: epsilon, start: start, end: maxIndex, keep: &keep)
            rdpRecurse(coords: coords, epsilon: epsilon, start: maxIndex, end: end, keep: &keep)
        }
    }

    // MARK: Geometry helpers

    private func pointToSegmentDistance(
        _ point: simd_float2, _ segA: simd_float2, _ segB: simd_float2
    ) -> Float {
        let ab = segB - segA
        let lengthSq = simd_dot(ab, ab)

        if lengthSq < 1e-12 {
            return simd_distance(point, segA)
        }

        let t = simd_clamp(simd_dot(point - segA, ab) / lengthSq, 0, 1)
        let projection = segA + t * ab
        return simd_distance(point, projection)
    }

    private func directedHausdorff(from a: [SmoothedCurvePoint], to b: [SmoothedCurvePoint]) -> Float {
        guard !a.isEmpty, b.count >= 2 else { return .infinity }

        var maxDist: Float = 0
        for p in a {
            var minDist: Float = .infinity
            for i in 0..<(b.count - 1) {
                minDist = min(minDist, pointToSegmentDistance(p.coord, b[i].coord, b[i + 1].coord))
            }
            maxDist = max(maxDist, minDist)
        }
        return maxDist
    }

    private func boundingBoxDiagonal(_ points: [simd_float2]) -> Float {
        guard let first = points.first else { return 0 }
        var lo = first, hi = first
        for p in points {
            lo = simd_min(lo, p)
            hi = simd_max(hi, p)
        }
        return simd_distance(lo, hi)
    }

    /// Prepares control points for Catmull-Rom smoothing, matching the renderer's convention
    /// of duplicating the first, last, and corner points.
    private func catmullRomControlPoints(for curve: CatmullRomCurve) -> [SmoothedCurvePoint] {
        var result = [SmoothedCurvePoint]()
        for (index, point) in curve.points.enumerated() {
            let smoothedPoint = SmoothedCurvePoint(coord: point.coord, controlPointIndex: index, weight: 0)
            result.append(smoothedPoint)
            if  point.pointType == .corner {
                result.append(smoothedPoint)
            }
        }
        return result
    }
}
