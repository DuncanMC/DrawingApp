//
//  CodableColor.swift
//  DrawingApp
//
//  Created by Duncan Champney on 5/4/26.
//  Copyright (c) 2026 Duncan Champney. All rights reserved.
//

import SwiftUI


// MARK: - Codable support for Color
struct CodableColor: Codable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat
    
    init(color: Color) {
        #if os(iOS)
        let uiColor = UIColor(color)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.red = r
        self.green = g
        self.blue = b
        self.alpha = a
        #elseif os(macOS)
        let nsColor = NSColor(color)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        nsColor.usingColorSpace(.deviceRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.red = r
        self.green = g
        self.blue = b
        self.alpha = a
        #else
        self.red = 1
        self.green = 1
        self.blue = 1
        self.alpha = 1
        #endif
    }
    
    func toColor() -> Color {
        Color(.sRGB, red: Double(red), green: Double(green), blue: Double(blue), opacity: Double(alpha))
    }
}
