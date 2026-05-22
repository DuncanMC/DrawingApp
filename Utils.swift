//
//  Utils.swift
//  DrawingApp
//
//  Created by Duncan Champney on 5/4/26.
//  Copyright (c) 2026 Duncan Champney. All rights reserved.
//

import Foundation
import SwiftUI

public extension Color {
    func components() -> [Double] {
        var colorComponents: [CGFloat] = [1, 1, 1, 1]
        
        #if os(macOS)
        if let backgroundColor = NSColor(self).cgColor.components {
            colorComponents =  backgroundColor
        }
        #else
        if let backgroundColor = UIColor(self).cgColor.components {
            colorComponents =  backgroundColor
        }
        
        #endif
        return colorComponents.map{ Double($0) }
    }
}

extension Float {
    var degreesToRadians: Float {
        return self * .pi / 180
    }
}

// MARK: - Types and methods for managing lines and points in Metal coordinate space

struct LineEquation {
    let slope: Float
    let yIntercept: Float
    let isVeritical: Bool
    let pointsAreTheSame: Bool
}


extension simd_float2 {
    static let zero = simd_float2(0,0)
    
    var x: Float {
        get { return self[0] }
        set { self[0] = newValue }
    }
    
    var y: Float {
        get { return self[1] }
        set { self[1] = newValue }
    }
}

extension simd_float3 {
    static let zero = simd_float2(0,0)
    
    var x: Float {
        get { return self[0] }
        set { self[0] = newValue }
    }
    
    var y: Float {
        get { return self[1] }
        set { self[1] = newValue }
    }
    
    var z: Float {
        get { return self[2] }
        set { self[2] = newValue }
    }
}


func equationForLine(from startPoint: simd_float2, to endPoint: simd_float2) -> (LineEquation) {
    
    if startPoint == endPoint {
        return (LineEquation(slope: 0, yIntercept: 0, isVeritical: false, pointsAreTheSame: true))
    } else if startPoint[0] == endPoint[0] {
        return (LineEquation(slope: Float.infinity, yIntercept: startPoint[0], isVeritical: true, pointsAreTheSame: false))
    } else {
        let slope = (endPoint[1] - startPoint[1]) / (endPoint[0] - startPoint[0])
        let intercept = startPoint[1] - slope * startPoint[0]
        return (LineEquation(slope: slope,
                             yIntercept: intercept,
                             isVeritical: false,
                             pointsAreTheSame: false))
    }
}
    
func intersection(line1: LineEquation, line2: LineEquation) -> simd_float2? {
    if line1.slope == line2.slope || line1.isVeritical && line2.isVeritical {
        return nil
    } else {
        if line1.isVeritical {
            //result x is line1 yIntercept
            //Solve for Y using line2 equation
            let x = line1.yIntercept
            let m = line2.slope
            let b = line2.yIntercept
            return simd_float2( x, m * x + b)
        } else if line2.isVeritical {
            //result x is line2 yIntercept
            //Solve for Y using line1 equation
            let x = line2.yIntercept
            let b = line1.yIntercept
            let m = line1.slope
            return simd_float2(x, m * x + b)
        } else {
            let x = (line1.yIntercept - line2.yIntercept) / (line2.slope - line1.slope)
            return simd_float2(
                x,
                line1.slope * x + line1.yIntercept
            )
        }
    }
}
// MARK: -

extension FloatingPoint {
  /// Allows mapping between reverse ranges, which are illegal to construct (e.g. `10..<0`).
  func interpolated(
    fromLowerBound: Self,
    fromUpperBound: Self,
    toLowerBound: Self,
    toUpperBound: Self) -> Self
  {
    let positionInRange = (self - fromLowerBound) / (fromUpperBound - fromLowerBound)
    return (positionInRange * (toUpperBound - toLowerBound)) + toLowerBound
  }

  func interpolated(from: ClosedRange<Self>, to: ClosedRange<Self>) -> Self {
    interpolated(
      fromLowerBound: from.lowerBound,
      fromUpperBound: from.upperBound,
      toLowerBound: to.lowerBound,
      toUpperBound: to.upperBound)
  }
}

public func distanceBetween(p1:  CGPoint, p2: CGPoint) -> CGFloat {
    let deltaX = p1.x - p2.x
    let deltaY = p1.y - p2.y
    return sqrt(deltaX * deltaX + deltaY * deltaY)
}


public func distanceBetween(p1:  SIMD2<Float>, p2: SIMD2<Float>) -> Float {
    let deltaX = p1.x - p2.x
    let deltaY = p1.y - p2.y
    return sqrt(deltaX * deltaX + deltaY * deltaY)
}
 
func remap(sourceMin: Float, sourceMax: Float, destMin: Float, destMax: Float, t: Float) -> Float {
    let f = (t - sourceMin) / (sourceMax - sourceMin)
    return simd_mix(destMin, destMax, f)
}

public func midpoint(p1:  SIMD2<Float>, p2: SIMD2<Float>) -> SIMD2<Float> {
    return SIMD2<Float>(x: (p1.x + p2.x)/2, y: (p1.y + p2.y)/2)
}

