//
//  GestureCapturingView.swift
//  DrawingApp
//
//  Created by Duncan Champney on 6/3/26.
//

import Foundation

#if os(iOS)
import UIKit

class GestureCapturingView: UIView {
    var eventRecognizers: [GestureRecognizer] = []

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let gestureEvent = makeGestureEvent(touch: touch)
        for r in eventRecognizers { r.touchBegan(gestureEvent) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let gestureEvent = makeGestureEvent(touch: touch)
        for r in eventRecognizers { r.touchMoved(gestureEvent) }
        cancelInactiveIfNeeded()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let gestureEvent = makeGestureEvent(touch: touch)
        for r in eventRecognizers { r.touchEnded(gestureEvent) }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let gestureEvent = makeGestureEvent(touch: touch)
        for r in eventRecognizers { r.touchCancelled(gestureEvent) }
    }

    private func makeGestureEvent(touch: UITouch) -> GestureEvent {
        let location = touch.location(in: self)
        let isPencil = touch.type == .pencil
        let pressure: CGFloat? = isPencil && touch.maximumPossibleForce > 0
            ? touch.force / touch.maximumPossibleForce
            : nil
        let pencil: PencilData? = isPencil ? PencilData(
            altitudeAngle: touch.altitudeAngle,
            azimuthAngle: touch.azimuthAngle(in: self)
        ) : nil
        return GestureEvent(
            location: location,
            timestamp: touch.timestamp,
            modifierKeys: [],
            pressure: pressure,
            pencilData: pencil
        )
    }

    private func cancelInactiveIfNeeded() {
        let anyActive = eventRecognizers.contains { $0.isActive }
        if anyActive {
            for r in eventRecognizers where !r.isActive {
                r.reset()
            }
        }
    }
}

#else
import AppKit

class GestureCapturingView: NSView {
    var eventRecognizers: [GestureRecognizer] = []

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return super.hitTest(point) != nil ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        let gestureEvent = makeGestureEvent(event: event)
        for r in eventRecognizers { r.touchBegan(gestureEvent) }
    }

    override func mouseDragged(with event: NSEvent) {
        let gestureEvent = makeGestureEvent(event: event)
        for r in eventRecognizers { r.touchMoved(gestureEvent) }
        cancelInactiveIfNeeded()
    }

    override func mouseUp(with event: NSEvent) {
        let gestureEvent = makeGestureEvent(event: event)
        for r in eventRecognizers { r.touchEnded(gestureEvent) }
    }

    private func makeGestureEvent(event: NSEvent) -> GestureEvent {
        let location = convert(event.locationInWindow, from: nil)
        let modifiers = GestureModifierKeys(nsEventFlags: event.modifierFlags)
        let pressure: CGFloat? = event.subtype == .tabletPoint || event.pressure > 0
            ? CGFloat(event.pressure)
            : nil
        return GestureEvent(
            location: location,
            timestamp: event.timestamp,
            modifierKeys: modifiers,
            pressure: pressure,
            pencilData: nil
        )
    }

    private func cancelInactiveIfNeeded() {
        let anyActive = eventRecognizers.contains { $0.isActive }
        if anyActive {
            for r in eventRecognizers where !r.isActive {
                r.reset()
            }
        }
    }
}
#endif
