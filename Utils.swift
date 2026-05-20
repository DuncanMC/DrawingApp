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
