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
    case outside
    
    var description: String {
        switch self {
            case .inControlPoint(let curveIndex, let pointIndex):
            return "inControlPoint(curveIndex: \(curveIndex), pointIndex: \(pointIndex))"
        case .outside:
            return "outside"
        }
    }
}

typealias GesturePointTuple = (point: CGPoint, gestureLocation: GestureLocation)

struct ViewModel {
    
    init(drawingInfo: DrawingInfo) {
        self.drawingInfo = drawingInfo
    }

    var useForceTouch: Bool {
        let value = UserDefaults.standard.bool(forKey: UserDefaultsKeys.useForceTouch.rawValue)
        return value
    }

    @ObservedObject var drawingInfo: DrawingInfo
    
    var points: [GesturePointTuple]  {
        var result: [GesturePointTuple] = []
        let curvesCount = drawingInfo.curves.count - 1
        
        for (curveIndex, aCurve) in drawingInfo.curves.reversed().enumerated() {
            for (pointIndex, aPoint) in aCurve.points.enumerated() {
                result.append((metalPointToView(aPoint.coord), .inControlPoint(curveIndex: curvesCount - curveIndex, pointIndex: pointIndex)))
            }
        }
        return result
    }
    func handleTap(location: CGPoint, modifiers: GestureModifierKeys = []) {

        if let target = getGestureLocation(touchLocation: location) {
            switch target.gestureLocation {
            case .inControlPoint(let curveIndex, let pointIndex):
                let tappedPoint = SelectedPoint(curveIndex: curveIndex, pointIndex: pointIndex)
                let toggleSelection = drawingInfo.drawingMode == .editingCurve

                if toggleSelection {
                    if drawingInfo.selectedPoints.contains(tappedPoint) {
                        drawingInfo.selectedPoints.remove(tappedPoint)
                        if drawingInfo.selectedPoints.isEmpty {
                            drawingInfo.drawingMode = .idle
                        }
                    } else {
                        drawingInfo.drawingMode = .editingCurve
                        drawingInfo.selectedPoints.insert(tappedPoint)
                    }
                } else {
                    drawingInfo.drawingMode = .editingCurve
                    drawingInfo.selectedPoints = [tappedPoint]
                }
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
                    pointType: .smooth)

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

//                    let firstPoint =  CatmullRomPoint(coord: coords, pointType: .corner, hardness: 1.0, pointRadius: 10.0)
                    let newCurve = CatmullRomCurve(color: thisCurve.color,
                                                   radius: drawingInfo.brushSettings.size,
                                                   outlineColor: nil,
                                                   points: [firstPoint, newPoint],
                                                   hardness: drawingInfo.brushSettings.hardness)
                    drawingInfo.selectedPoints = [SelectedPoint(curveIndex: drawingInfo.curves.count, pointIndex: 1)]
                    drawingInfo.curves.append(newCurve)
                    drawingInfo.drawingMode = .editingCurve
                }

            } else {
                //print("Single-tap not on a known location.")
                
                let coords = viewPointToMetal(location)
                let point =  CatmullRomPoint(coord: coords, pointType: .smooth)

                let newCurve = CatmullRomCurve(color: drawingInfo.brushSettings.color,
                                               radius: drawingInfo.brushSettings.size,
                                               outlineColor: nil,
                                               points: [point],
                                               hardness: drawingInfo.brushSettings.hardness)
                drawingInfo.selectedPoints = [SelectedPoint(curveIndex: drawingInfo.curves.count, pointIndex: 0)]
                drawingInfo.curves.append(newCurve)
                drawingInfo.drawingMode = .editingCurve

            }
        }
    }
    
    func handleTwoFingerTap(location: CGPoint) {
        if let target = getGestureLocation(touchLocation: location) {
            switch target.gestureLocation {
            case .inControlPoint(let curveIndex, _):
                let curve = drawingInfo.curves[curveIndex]
                drawingInfo.drawingMode = .editingCurve
                var newSelection = Set<SelectedPoint>()
                for pointIndex in 0..<curve.points.count {
                    newSelection.insert(SelectedPoint(curveIndex: curveIndex, pointIndex: pointIndex))
                }
                drawingInfo.selectedPoints = newSelection
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
            print("Double-tap in \(target.gestureLocation.description)")
            let gestureLocation = target.gestureLocation
            switch gestureLocation {
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
    
    func brushSizeForEvent(_ event: GestureEvent) -> Float? {
        var brushSize: Float?  = nil
        guard useForceTouch else { return nil }
        if let pressure = event.pressure {
            if let pencilData = event.pencilData {
                let force = pressure / sin(pencilData.altitudeAngle)
                print("Dragging, force = \(force). altitudeAngle = \(pencilData.altitudeAngle)")
                print("Dragging, trackpad pressure = \(force)")
                brushSize = Float(force) * (maxThickness - minThickness) + minThickness
            } else {
                brushSize = Float(pressure) * (maxThickness - minThickness) + minThickness
            }
        }
        return brushSize
    }
    
    func handlePinchRotateBegan(center: CGPoint) {
        drawingInfo.registerUndo()
        drawingInfo.suppressUndo = true
    }

    func handlePinchRotateChanged(scale: CGFloat, rotation: CGFloat, center: CGPoint) {
        guard !drawingInfo.selectedPoints.isEmpty else { return }

        let cosR = cos(rotation)
        let sinR = sin(rotation)

        for aPoint in drawingInfo.selectedPoints {
            let coord = drawingInfo.curves[aPoint.curveIndex].points[aPoint.pointIndex].coord
            let viewPt = metalPointToView(coord)
            let dx = viewPt.x - center.x
            let dy = viewPt.y - center.y
            let rx = cosR * dx - sinR * dy
            let ry = sinR * dx + cosR * dy
            let sx = rx * scale
            let sy = ry * scale
            let newViewPt = CGPoint(x: sx + center.x, y: sy + center.y)
            drawingInfo.curves[aPoint.curveIndex].points[aPoint.pointIndex].coord = viewPointToMetal(newViewPt)

            if let radius = drawingInfo.curves[aPoint.curveIndex].points[aPoint.pointIndex].pointRadius {
                drawingInfo.curves[aPoint.curveIndex].points[aPoint.pointIndex].pointRadius = radius * Float(scale)
            }
        }
    }

    func handlePinchRotateEnded() {
        drawingInfo.suppressUndo = false
    }

    func handleDragBegan(location: CGPoint, event: GestureEvent) {
        drawingInfo.registerUndo()
        drawingInfo.suppressUndo = true

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
            default:
                break
            }
        } else {
            let coords = viewPointToMetal(location)

            if drawingInfo.drawingMode == .editingCurve,
               drawingInfo.selectedPoints.count == 1 {
                let activeCurveIndex = drawingInfo.selectedPoints.first!.curveIndex
                let activePointIndex = drawingInfo.selectedPoints.first!.pointIndex
                let point = CatmullRomPoint(coord: coords, pointType: .smooth)

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
                                                   hardness: drawingInfo.brushSettings.hardness)
                    drawingInfo.selectedPoints = [SelectedPoint(curveIndex: drawingInfo.curves.count, pointIndex: 1)]
                    drawingInfo.curves.append(newCurve)
                    drawingInfo.drawingMode = .creatingCurve
                    drawingInfo.lastDragLocation = location
                    drawingInfo.isDragging = true
                    return
                }
            }

            let point = CatmullRomPoint(coord: coords, pointType: .smooth, pointRadius: brushSizeForEvent(event))
            let newCurve = CatmullRomCurve(color: drawingInfo.brushSettings.color,
                                           radius: drawingInfo.brushSettings.size,
                                           outlineColor: nil,
                                           points: [point],
                                           hardness: drawingInfo.brushSettings.hardness)
            drawingInfo.selectedPoints = [SelectedPoint(curveIndex: drawingInfo.curves.count, pointIndex: 0)]
            drawingInfo.curves.append(newCurve)
            drawingInfo.drawingMode = .creatingCurve
            drawingInfo.lastDragLocation = location
            drawingInfo.isDragging = true
        }
    }

    func handleDragChanged(location: CGPoint, event: GestureEvent) {
        guard let lastDragLocation = drawingInfo.lastDragLocation else { return }

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
            //MARK: - Force handling
            //MARK: -
        case .idle:
            break
        case .editingCurve:

            let deltaX = -2.0 * Float((lastDragLocation.x - location.x) / drawingInfo.imageSize.width)
            let deltaY = 2.0 * Float((lastDragLocation.y - location.y) / drawingInfo.imageSize.height)

            switch drawingInfo.draggingState {
            case .inControlPoint:
                for aPoint in drawingInfo.selectedPoints {
                    let theCurve = drawingInfo.curves[aPoint.curveIndex]
                    var thePoint = theCurve.points[aPoint.pointIndex]
                    thePoint.coord.x += deltaX
                    thePoint.coord.y += deltaY
                    drawingInfo.curves[aPoint.curveIndex].points[aPoint.pointIndex] = thePoint
                }
                drawingInfo.lastDragLocation = location
            default:
                break
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
                print("pared curve from \(curve.points.count) to \(paredCurve.points.count). \(percentString)% reduction.")
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
        
        //Calculate the distance of each matching point from the tap point
            .map { ($0, distanceSquardBetween(p1: tapPoint, p2: $0.point)) }
        
        // Sort the points closest-to-farthest
            .sorted(by: { $0.1 < $1.1 })
        return matches.first?.0
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


    func getGestureLocation(touchLocation: CGPoint) -> GesturePointTuple? {

        let aspect = drawingInfo.viewportSize.width / drawingInfo.viewportSize.height
        let adjusted = CGPoint(x: touchLocation.x * aspect, y: touchLocation.y)
        //print("Adjusted tap point = \(adjusted)")
        let result = matchPoint(touchLocation, inPoints: points)
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
