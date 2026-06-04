//
//  GestureRecognizer.swift
//  DrawingApp
//
//  Created by Duncan Champney on 6/3/26.
//

import Foundation
import CoreGraphics

// MARK: - Protocol

protocol GestureRecognizer: AnyObject {
    func touchBegan(_ event: GestureEvent)
    func touchMoved(_ event: GestureEvent)
    func touchEnded(_ event: GestureEvent)
    func touchCancelled(_ event: GestureEvent)
    func reset()
    var isActive: Bool { get }
}

// MARK: - TapRecognizer

class TapRecognizer: GestureRecognizer {
    var onTap: ((CGPoint, GestureEvent) -> Void)?
    var onDoubleTap: ((CGPoint, GestureEvent) -> Void)?

    var movementThreshold: CGFloat = 20
    var tapDurationLimit: TimeInterval = 0.3
    var doubleTapWindow: TimeInterval = 0.25

    private var touchDownLocation: CGPoint?
    private var touchDownTime: TimeInterval?
    private var exceeded = false
    private var pendingTap: (location: CGPoint, event: GestureEvent)?
    private var doubleTapTimer: Timer?

    var isActive: Bool { false }

    func touchBegan(_ event: GestureEvent) {
        touchDownLocation = event.location
        touchDownTime = event.timestamp
        exceeded = false
    }

    func touchMoved(_ event: GestureEvent) {
        guard !exceeded, let start = touchDownLocation else { return }
        let dx = event.location.x - start.x
        let dy = event.location.y - start.y
        if dx * dx + dy * dy > movementThreshold * movementThreshold {
            exceeded = true
        }
    }

    func touchEnded(_ event: GestureEvent) {
        guard !exceeded,
              let downTime = touchDownTime,
              event.timestamp - downTime < tapDurationLimit else {
            clearTouchState()
            return
        }

        if let _ = pendingTap {
            doubleTapTimer?.invalidate()
            doubleTapTimer = nil
            pendingTap = nil
            onDoubleTap?(event.location, event)
        } else if onDoubleTap != nil {
            pendingTap = (event.location, event)
            doubleTapTimer = Timer.scheduledTimer(withTimeInterval: doubleTapWindow, repeats: false) { [weak self] _ in
                guard let self, let pending = self.pendingTap else { return }
                self.pendingTap = nil
                self.onTap?(pending.location, pending.event)
            }
        } else {
            onTap?(event.location, event)
        }

        clearTouchState()
    }

    func touchCancelled(_ event: GestureEvent) {
        reset()
    }

    func reset() {
        clearTouchState()
        doubleTapTimer?.invalidate()
        doubleTapTimer = nil
        pendingTap = nil
    }

    private func clearTouchState() {
        touchDownLocation = nil
        touchDownTime = nil
        exceeded = false
    }
}

// MARK: - TwoFingerTapRecognizer

class TwoFingerTapRecognizer: GestureRecognizer {
    var onTwoFingerTap: ((CGPoint, GestureEvent) -> Void)?

    var movementThreshold: CGFloat = 20
    var tapDurationLimit: TimeInterval = 0.5

    private var startLocation: CGPoint?
    private var startSecondLocation: CGPoint?
    private var twoFingersDownTime: TimeInterval?
    private var exceeded = false
    private var tracking = false

    var isActive: Bool { tracking }

    func touchBegan(_ event: GestureEvent) {
        if event.touchCount >= 2 && !tracking {
            tracking = true
            startLocation = event.location
            startSecondLocation = event.secondTouchLocation
            twoFingersDownTime = event.timestamp
            exceeded = false
        }
    }

    func touchMoved(_ event: GestureEvent) {
        guard tracking, !exceeded else { return }
        if let start = startLocation {
            let dx = event.location.x - start.x
            let dy = event.location.y - start.y
            if dx * dx + dy * dy > movementThreshold * movementThreshold {
                exceeded = true
                return
            }
        }
        if let startSecond = startSecondLocation, let currentSecond = event.secondTouchLocation {
            let dx = currentSecond.x - startSecond.x
            let dy = currentSecond.y - startSecond.y
            if dx * dx + dy * dy > movementThreshold * movementThreshold {
                exceeded = true
            }
        }
    }

    func touchEnded(_ event: GestureEvent) {
        guard tracking else { return }
        if event.touchCount == 0 {
            if !exceeded,
               let downTime = twoFingersDownTime,
               event.timestamp - downTime < tapDurationLimit {
                onTwoFingerTap?(startLocation ?? event.location, event)
            }
            reset()
        }
    }

    func touchCancelled(_ event: GestureEvent) {
        reset()
    }

    func reset() {
        startLocation = nil
        startSecondLocation = nil
        twoFingersDownTime = nil
        exceeded = false
        tracking = false
    }
}

// MARK: - PinchRotateRecognizer

class PinchRotateRecognizer: GestureRecognizer {
    var onPinchRotateBegan: ((CGPoint) -> Void)?
    var onPinchRotateChanged: ((CGFloat, CGFloat, CGPoint) -> Void)?
    var onPinchRotateEnded: (() -> Void)?

    var distanceThreshold: CGFloat = 10
    var rotationThreshold: CGFloat = 0.1

    private var initialDistance: CGFloat?
    private var initialAngle: CGFloat?
    private var lastDistance: CGFloat?
    private var lastAngle: CGFloat?
    private var tracking = false
    private var gestureActive = false

    var isActive: Bool { tracking }

    func touchBegan(_ event: GestureEvent) {
        if event.touchCount >= 2, let second = event.secondTouchLocation, !tracking {
            tracking = true
            gestureActive = false
            let dist = hypot(event.location.x - second.x, event.location.y - second.y)
            let angle = atan2(second.y - event.location.y, second.x - event.location.x)
            initialDistance = dist
            initialAngle = angle
            lastDistance = dist
            lastAngle = angle
        }
    }

    func touchMoved(_ event: GestureEvent) {
        guard tracking,
              let second = event.secondTouchLocation,
              let initDist = initialDistance,
              let initAngle = initialAngle else { return }

        let currentDist = hypot(event.location.x - second.x, event.location.y - second.y)
        let currentAngle = atan2(second.y - event.location.y, second.x - event.location.x)
        let center = CGPoint(x: (event.location.x + second.x) / 2,
                             y: (event.location.y + second.y) / 2)

        if !gestureActive {
            let distDelta = abs(currentDist - initDist)
            let angleDelta = abs(normalizeAngle(currentAngle - initAngle))
            if distDelta > distanceThreshold || angleDelta > rotationThreshold {
                gestureActive = true
                lastDistance = currentDist
                lastAngle = currentAngle
                onPinchRotateBegan?(center)
            }
        }

        if gestureActive {
            let prevDist = lastDistance ?? initDist
            let scaleIncrement = prevDist > 0 ? currentDist / prevDist : 1.0
            let rotationIncrement = normalizeAngle(currentAngle - (lastAngle ?? initAngle))
            lastDistance = currentDist
            lastAngle = currentAngle
            onPinchRotateChanged?(scaleIncrement, rotationIncrement, center)
        }
    }

    func touchEnded(_ event: GestureEvent) {
        if gestureActive {
            onPinchRotateEnded?()
        }
        if event.touchCount < 2 {
            reset()
        }
    }

    func touchCancelled(_ event: GestureEvent) {
        if gestureActive {
            onPinchRotateEnded?()
        }
        reset()
    }

    func reset() {
        initialDistance = nil
        initialAngle = nil
        lastDistance = nil
        lastAngle = nil
        tracking = false
        gestureActive = false
    }

    private func normalizeAngle(_ angle: CGFloat) -> CGFloat {
        var a = angle
        while a > .pi { a -= 2 * .pi }
        while a < -.pi { a += 2 * .pi }
        return a
    }
}

// MARK: - DragRecognizer

class DragRecognizer: GestureRecognizer {
    var onDragBegan: ((CGPoint, GestureEvent) -> Void)?
    var onDragChanged: ((CGPoint, GestureEvent) -> Void)?
    var onDragEnded: ((CGPoint, GestureEvent) -> Void)?

    var movementThreshold: CGFloat = 15

    private var startLocation: CGPoint?
    private var startEvent: GestureEvent?
    private(set) var isDragging = false

    var isActive: Bool { isDragging }

    func touchBegan(_ event: GestureEvent) {
        startLocation = event.location
        startEvent = event
        isDragging = false
    }

    func touchMoved(_ event: GestureEvent) {
        guard let start = startLocation else { return }
        if !isDragging {
            let dx = event.location.x - start.x
            let dy = event.location.y - start.y
            if dx * dx + dy * dy > movementThreshold * movementThreshold {
                isDragging = true
                onDragBegan?(start, startEvent ?? event)
            }
        }
        if isDragging {
            onDragChanged?(event.location, event)
        }
    }

    func touchEnded(_ event: GestureEvent) {
        if isDragging {
            onDragEnded?(event.location, event)
        }
        isDragging = false
        startLocation = nil
        startEvent = nil
    }

    func touchCancelled(_ event: GestureEvent) {
        if isDragging {
            onDragEnded?(event.location, event)
        }
        reset()
    }

    func reset() {
        startLocation = nil
        startEvent = nil
        isDragging = false
    }
}
