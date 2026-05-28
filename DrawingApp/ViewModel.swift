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
        for (curveIndex, aCurve) in drawingInfo.curves.enumerated() {
            for (pointIndex, aPoint) in aCurve.points.enumerated() {
                result.append((metalPointToView(aPoint.coord), .inControlPoint(curveIndex: curveIndex, pointIndex: pointIndex)))
            }
        }
        return result
    }
    func handleTap(location: CGPoint) {
        if let target = getGestureLocation(touchLocation: location) {
            switch target.gestureLocation {
                case .inControlPoint(let curveIndex, let pointIndex):
                print("Single-tap in \(target.gestureLocation.description)\n")
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
               let _ = drawingInfo.activePointIndex {
                let newlocation = viewPointToMetal(location)
                let newPoint = CatmullRomPoint(
                    coord: newlocation,
                                               pointType: .smooth,
                    hardness: drawingInfo.brushSettings.hardness,
                    pointRadius: drawingInfo.brushSettings.size)
                drawingInfo.curves[activeCurveIndex].points.append(newPoint)
                drawingInfo.activePointIndex = drawingInfo.curves[activeCurveIndex].points.count - 1

            } else {
                print("Single-tap not on a known location.")
                
                let coords = viewPointToMetal(location)
                let point =  CatmullRomPoint(coord: coords, pointType: .corner, hardness: 1.0, pointRadius: 10.0)

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
            
            let deltaX = Float(lastDragLocation.x - value.location.x)
            let deltaY = Float(lastDragLocation.y - value.location.y)

            guard let curveIndex = drawingInfo.activeCurveIndex else {
                print("No active curve")
                return
            }
            guard  distanceSquardBetween(p1: lastDragLocation, p2: value.location) > 900 else {
                print("deltaX = \(deltaX), deltaY = \(deltaY). Exiting")
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
        default:
            break
        }


        }

    func handleDeletePoint() {
        print("In \(#function)")
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
    func matchPoint(_  tapPoint: CGPoint, inPoints points: [GesturePointTuple]) -> GesturePointTuple? {
        let slop: CGFloat = 20
        for (aPoint, location) in points {
            if tapPoint.x > aPoint.x - slop && tapPoint.x < aPoint.x + slop &&
                tapPoint.y > aPoint.y - slop && tapPoint.y < aPoint.y + slop
            {
                    return (aPoint, location)
            }
        }
        return nil
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
    
}
