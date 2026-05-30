//
//  ViewModel.swift
//  DrawingApp
//
//  Created by Duncan Champney on 5/20/26.
//

import Foundation
import SwiftUI
import Combine

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
    func handleTap(location: CGPoint) {
        if let target = getGestureLocation(touchLocation: location) {
            switch target.gestureLocation {
                case .inControlPoint(let curveIndex, let pointIndex):
                //print("Single-tap in \(target.gestureLocation.description)\n")
                if drawingInfo.drawingMode == .editingCurve &&
                    drawingInfo.activeCurveIndex == curveIndex &&
                    drawingInfo.activePointIndex == pointIndex {
                    drawingInfo.drawingMode = .idle
                    drawingInfo.activeCurveIndex = nil
                    drawingInfo.activePointIndex = nil
                } else {
                    drawingInfo.drawingMode = .editingCurve
                    drawingInfo.activeCurveIndex = curveIndex
                    drawingInfo.activePointIndex = pointIndex
                }
            case .outside: break
            }
        } else {
            if drawingInfo.drawingMode == .editingCurve,
               let activeCurveIndex = drawingInfo.activeCurveIndex,
               let pointIndex = drawingInfo.activePointIndex {
                
                var thisCurve = drawingInfo.curves[activeCurveIndex]
                let newlocation = viewPointToMetal(location)
                let newPoint = CatmullRomPoint(
                    coord: newlocation,
                                               pointType: .smooth,
                    hardness: drawingInfo.brushSettings.hardness,
                    pointRadius: drawingInfo.brushSettings.size)

                if pointIndex == thisCurve.points.count - 1 {
                    //append point to end of curve.
                    thisCurve.points.append(newPoint)
                    drawingInfo.activePointIndex = thisCurve.points.count - 1
                    drawingInfo.curves[activeCurveIndex] = thisCurve
                } else if pointIndex == 0 {
                    thisCurve.points.insert(newPoint, at: 0)
                    drawingInfo.curves[activeCurveIndex] = thisCurve
                } else
                {
                    let coords = thisCurve.points[pointIndex].coord
                    let firstPoint = thisCurve.points[pointIndex]

//                    let firstPoint =  CatmullRomPoint(coord: coords, pointType: .corner, hardness: 1.0, pointRadius: 10.0)
                    let newCurve = CatmullRomCurve(color: thisCurve.color,
                                                   radius: drawingInfo.brushSettings.size,
                                                   outlineColor: nil,
                                                   points: [firstPoint, newPoint])
                    drawingInfo.activeCurveIndex = drawingInfo.curves.count
                    drawingInfo.curves.append(newCurve)
                    drawingInfo.drawingMode = .editingCurve
                    drawingInfo.activePointIndex = 1
                }

            } else {
                print("Single-tap not on a known location.")
                
                let coords = viewPointToMetal(location)
                let point =  CatmullRomPoint(coord: coords, pointType: .smooth, hardness: 1.0, pointRadius: 10.0)

                let newCurve = CatmullRomCurve(color: drawingInfo.brushSettings.color,
                                               radius: drawingInfo.brushSettings.size,
                                               outlineColor: nil,
                                               points: [point])
                drawingInfo.activeCurveIndex = drawingInfo.curves.count
                drawingInfo.curves.append(newCurve)
                drawingInfo.drawingMode = .editingCurve
                drawingInfo.activePointIndex = 0

            }
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

    func handleDragging(_ value: DragGesture.Value) {
        guard let lastDragLocation = drawingInfo.lastDragLocation else { return }

        switch drawingInfo.drawingMode {
            
        case .creatingCurve:
            
            guard let curveIndex = drawingInfo.activeCurveIndex else {
                print("No active curve")
                return
            }
            guard  distanceSquardBetween(p1: lastDragLocation, p2: value.location) > 9 else {
                //print("deltaX = \(deltaX), deltaY = \(deltaY). Exiting")
                return
            }
            
            let newlocation = viewPointToMetal(value.location)
            let newPoint = CatmullRomPoint(
                coord: newlocation,
                pointType: .smooth,
                hardness: drawingInfo.brushSettings.hardness,
                pointRadius: drawingInfo.brushSettings.size)
            drawingInfo.curves[curveIndex].points.append(newPoint)
            drawingInfo.lastDragLocation = value.location
        case .idle:
            break
        case .editingCurve:
            
            let deltaX = -2.0 * Float((lastDragLocation.x - value.location.x) / drawingInfo.imageSize.width)
            let deltaY = 2.0 * Float((lastDragLocation.y - value.location.y) / drawingInfo.imageSize.height)
            
            switch drawingInfo.draggingState {
            case .inControlPoint(let curveIndex, let pointIndex):
                let theCurve = drawingInfo.curves[curveIndex]
                var thePoint = theCurve.points[pointIndex]
                thePoint.coord.x += deltaX
                thePoint.coord.y += deltaY
                drawingInfo.curves[curveIndex].points[pointIndex] = thePoint
                drawingInfo.lastDragLocation = value.location
                
            default:
                break
            }
        }


        }

    func handleDeletePoint() {
        guard let curveIndex = drawingInfo.activeCurveIndex,
        var pointIndex = drawingInfo.activePointIndex else { return }
        var curve = drawingInfo.curves[curveIndex]
        curve.points.remove(at: pointIndex)
        pointIndex -= 1
        if pointIndex >= 0 {
            drawingInfo.activePointIndex = pointIndex
        }
        if curve.points.isEmpty {
            drawingInfo.curves.remove(at: curveIndex)
            drawingInfo.activeCurveIndex = nil
        } else {
            drawingInfo.curves[curveIndex] = curve
        }
        
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
            result.points = keptIndices.map { curve.points[$0] }
            return result
        }
    }

    // MARK: Auto-terminate mode

    public func parePointsAuto(
        _ curve: CatmullRomCurve,
        granularity: Int,
        maxError: Float
    ) -> CatmullRomCurve {
        let referenceControlPoints = catmullRomControlPoints(for: curve)
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
        result.points = bestIndices.map { curve.points[$0] }
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

    private func directedHausdorff(from a: [simd_float2], to b: [simd_float2]) -> Float {
        guard !a.isEmpty, b.count >= 2 else { return .infinity }

        var maxDist: Float = 0
        for p in a {
            var minDist: Float = .infinity
            for i in 0..<(b.count - 1) {
                minDist = min(minDist, pointToSegmentDistance(p, b[i], b[i + 1]))
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
    private func catmullRomControlPoints(for curve: CatmullRomCurve) -> [simd_float2] {
        var result = [simd_float2]()
        for (index, point) in curve.points.enumerated() {
            result.append(point.coord)
            if index == 0 || index == curve.points.count - 1 || point.pointType == .corner {
                result.append(point.coord)
            }
        }
        return result
    }
}
