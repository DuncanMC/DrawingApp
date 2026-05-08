//
//  Utils.swift
//  DrawingApp
//
//  Created by Duncan Champney on 5/4/26.
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

