//
//  GestureEvent.swift
//  DrawingApp
//
//  Created by Duncan Champney on 6/3/26.
//

import Foundation
import CoreGraphics

struct GestureModifierKeys: OptionSet, Sendable {
    let rawValue: UInt
    static let shift   = GestureModifierKeys(rawValue: 1 << 0)
    static let control = GestureModifierKeys(rawValue: 1 << 1)
    static let option  = GestureModifierKeys(rawValue: 1 << 2)
    static let command = GestureModifierKeys(rawValue: 1 << 3)
}

struct PencilData {
    let altitudeAngle: CGFloat
    let azimuthAngle: CGFloat
}

struct GestureEvent {
    let location: CGPoint
    let timestamp: TimeInterval
    let modifierKeys: GestureModifierKeys
    let pressure: CGFloat?
    let pencilData: PencilData?
}

#if os(macOS)
import AppKit
extension GestureModifierKeys {
    init(nsEventFlags: NSEvent.ModifierFlags) {
        var keys = GestureModifierKeys()
        if nsEventFlags.contains(.shift)   { keys.insert(.shift) }
        if nsEventFlags.contains(.control) { keys.insert(.control) }
        if nsEventFlags.contains(.option)  { keys.insert(.option) }
        if nsEventFlags.contains(.command) { keys.insert(.command) }
        self = keys
    }
}
#else
import UIKit
extension GestureModifierKeys {
    init(uiKeyModifierFlags: UIKeyModifierFlags) {
        var keys = GestureModifierKeys()
        if uiKeyModifierFlags.contains(.shift)     { keys.insert(.shift) }
        if uiKeyModifierFlags.contains(.control)   { keys.insert(.control) }
        if uiKeyModifierFlags.contains(.alternate) { keys.insert(.option) }
        if uiKeyModifierFlags.contains(.command)   { keys.insert(.command) }
        self = keys
    }
}
#endif
