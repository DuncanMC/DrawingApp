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
    private var trackedTouches: [UITouch] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isMultipleTouchEnabled = true
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if trackedTouches.count < 2 {
                trackedTouches.append(touch)
            }
        }
        guard let primaryTouch = trackedTouches.first else { return }
        let gestureEvent = makeGestureEvent(primaryTouch: primaryTouch)
        for r in eventRecognizers { r.touchBegan(gestureEvent) }
        cancelInactiveIfNeeded()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let primaryTouch = trackedTouches.first else { return }
        let gestureEvent = makeGestureEvent(primaryTouch: primaryTouch)
        for r in eventRecognizers { r.touchMoved(gestureEvent) }
        cancelInactiveIfNeeded()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let primaryTouch = trackedTouches.first else { return }
        let gestureEvent = makeGestureEvent(primaryTouch: primaryTouch, removingTouches: touches)
        trackedTouches.removeAll { touches.contains($0) }
        for r in eventRecognizers { r.touchEnded(gestureEvent) }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let primaryTouch = trackedTouches.first else { return }
        let gestureEvent = makeGestureEvent(primaryTouch: primaryTouch, removingTouches: touches)
        trackedTouches.removeAll { touches.contains($0) }
        for r in eventRecognizers { r.touchCancelled(gestureEvent) }
    }

    private func makeGestureEvent(primaryTouch: UITouch, removingTouches: Set<UITouch>? = nil) -> GestureEvent {
        let location = primaryTouch.location(in: self)
        let isPencil = primaryTouch.type == .pencil
        let pressure: CGFloat? = isPencil && primaryTouch.maximumPossibleForce > 0
            ? primaryTouch.force / primaryTouch.maximumPossibleForce
            : nil
        let pencil: PencilData? = isPencil ? PencilData(
            altitudeAngle: primaryTouch.altitudeAngle,
            azimuthAngle: primaryTouch.azimuthAngle(in: self)
        ) : nil
        let secondLoc = trackedTouches.count >= 2 ? trackedTouches[1].location(in: self) : nil
        var remainingCount = trackedTouches.count
        if let removing = removingTouches {
            remainingCount -= trackedTouches.filter { removing.contains($0) }.count
        }
        return GestureEvent(
            location: location,
            timestamp: primaryTouch.timestamp,
            modifierKeys: [],
            pressure: pressure,
            pencilData: pencil,
            touchCount: removingTouches != nil ? remainingCount : trackedTouches.count,
            secondTouchLocation: secondLoc
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
    private var forceTouchPressure: CGFloat?

    var onPinchRotateBegan: ((CGPoint) -> Void)?
    var onPinchRotateChanged: ((CGFloat, CGFloat, CGPoint) -> Void)?
    var onPinchRotateEnded: (() -> Void)?

    private var isMagnifying = false
    private var isRotating = false

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return super.hitTest(point) != nil ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        forceTouchPressure = nil
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
        forceTouchPressure = nil
    }

    override func pressureChange(with event: NSEvent) {
        forceTouchPressure = CGFloat(event.pressure)
    }

    override func magnify(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        switch event.phase {
        case .began:
            isMagnifying = true
            if !isRotating { onPinchRotateBegan?(location) }
        case .changed:
            let scale = 1.0 + CGFloat(event.magnification)
            onPinchRotateChanged?(scale, 0, location)
        case .ended:
            isMagnifying = false
            if !isRotating { onPinchRotateEnded?() }
        default: break
        }
    }

    override func rotate(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        switch event.phase {
        case .began:
            isRotating = true
            if !isMagnifying { onPinchRotateBegan?(location) }
        case .changed:
            let rotation = -CGFloat(event.rotation) * .pi / 180.0
            onPinchRotateChanged?(1.0, rotation, location)
        case .ended:
            isRotating = false
            if !isMagnifying { onPinchRotateEnded?() }
        default: break
        }
    }

    private func makeGestureEvent(event: NSEvent) -> GestureEvent {
        let location = convert(event.locationInWindow, from: nil)
        let modifiers = GestureModifierKeys(nsEventFlags: event.modifierFlags)
        let pressure: CGFloat?
        if event.subtype == .tabletPoint {
            pressure = CGFloat(event.pressure)
        } else {
            pressure = forceTouchPressure
        }
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
