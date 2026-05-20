//
//  ViewModel.swift
//  DrawingApp
//
//  Created by Duncan Champney on 5/20/26.
//

import Foundation
import SwiftUI
import Combine

enum DragLocations: CustomStringConvertible {
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

typealias DragPointTuple = (point: CGPoint, dragLocation: DragLocations)

struct ViewModel {
    @ObservedObject var drawingInfo: DrawingInfo
    
    var points: [DragPointTuple]  {
        var result: [DragPointTuple] = []
        for (curveIndex, aCurve) in drawingInfo.curves.enumerated() {
            for (pointIndex, aPoint) in aCurve.points.enumerated() {
                result.append((metalPointToView(aPoint.coord), .inControlPoint(curveIndex: curveIndex, pointIndex: pointIndex)))
            }
        }
        return result
    }
    
    func handleDragging(_ value: DragGesture.Value) {
        guard let lastDragLocation = drawingInfo.lastDragLocation else { return }

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

    func matchPoint(_  tapPoint: CGPoint, inPoints points: [DragPointTuple]) -> DragPointTuple? {
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


    func getGestureLocation(touchLocation: CGPoint) -> DragPointTuple? {
        
        let aspect = drawingInfo.viewportSize.width / drawingInfo.viewportSize.height
        let adjusted = CGPoint(x: touchLocation.x * aspect, y: touchLocation.y)
        //print("Adjusted tap point = \(adjusted)")
        let result = matchPoint(touchLocation, inPoints: points)
        return result

        
    }
    
}
