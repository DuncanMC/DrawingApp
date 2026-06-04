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
