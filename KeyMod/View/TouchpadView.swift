//
//  TouchpadView.swift
//  KeyMod
//
//  Created by System on 2025/6/21.
//

import SwiftUI
import UIKit
import Combine

/// Shared state for pointer tip positions shown on the touchpad overlay.
class PointerTipState: ObservableObject {
    @Published var pointerPosition: CGPoint?   // nil = no active pointer
    @Published var isDragging: Bool = false
}

// Custom UIViewRepresentable for multi-touch gesture detection
struct TouchpadView: UIViewRepresentable {
    let mouseManager: MouseManager
    let pointerTipState: PointerTipState
    @ObservedObject private var touchpadSettings = TouchpadSettings.shared

    func makeUIView(context: Context) -> UIView {
        let view = TouchpadUIView()
        view.mouseManager = mouseManager
        view.touchpadSettings = touchpadSettings
        view.pointerTipState = pointerTipState
        view.backgroundColor = UIColor.clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let touchpadView = uiView as? TouchpadUIView {
            touchpadView.updateSettings(touchpadSettings)
        }
    }
}

class TouchpadUIView: UIView {
    var mouseManager: MouseManager?
    var touchpadSettings: TouchpadSettings?
    var pointerTipState: PointerTipState? {
        didSet {
            pointerTipObserver = pointerTipState?.objectWillChange.sink { [weak self] _ in
                self?.updatePointerIndicator()
            }
            updatePointerIndicator()
        }
    }
    private var pointerTipObserver: AnyCancellable?
    private var dragStartPosition: CGPoint?
    private var isDragging = false
    private var tapTimer: Timer?
    private var pendingTapLocation: CGPoint?
    private var tapStartTime: Date?
    private var twoFingerScrollPrevious: CGPoint?
    private let hapticManager = HapticFeedbackManager.shared

    // Pointer tip indicator layers
    private let pointerFillLayer = CALayer()
    private let pointerStrokeLayer = CAShapeLayer()

    // Default values that can be updated from settings
    private var tapDelayThreshold: TimeInterval = 0.15
    private var tapMovementThreshold: CGFloat = 10.0
    private var tapDurationThreshold: TimeInterval = 0.4

    override init(frame: CGRect) {
        super.init(frame: frame)
        loadSettings()
        setupGestures()
        setupPointerIndicator()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        loadSettings()
        setupGestures()
        setupPointerIndicator()
    }

    private func setupPointerIndicator() {
        pointerFillLayer.cornerRadius = 12
        pointerFillLayer.backgroundColor = UIColor.white.withAlphaComponent(0.5).cgColor
        pointerFillLayer.isHidden = true
        pointerFillLayer.zPosition = 1
        layer.addSublayer(pointerFillLayer)

        pointerStrokeLayer.lineWidth = 2
        pointerStrokeLayer.strokeColor = UIColor.blue.cgColor
        pointerStrokeLayer.fillColor = UIColor.clear.cgColor
        pointerStrokeLayer.isHidden = true
        pointerStrokeLayer.zPosition = 2
        layer.addSublayer(pointerStrokeLayer)
    }

    private func updatePointerIndicator() {
        guard let pos = pointerTipState?.pointerPosition else {
            pointerFillLayer.isHidden = true
            pointerStrokeLayer.isHidden = true
            return
        }
        let radius: CGFloat = 12
        let origin = CGPoint(x: pos.x - radius, y: pos.y - radius)
        pointerFillLayer.frame = CGRect(origin: origin, size: CGSize(width: radius * 2, height: radius * 2))
        pointerFillLayer.isHidden = false

        let circlePath = UIBezierPath(ovalIn: CGRect(origin: origin, size: CGSize(width: radius * 2, height: radius * 2)))
        pointerStrokeLayer.path = circlePath.cgPath
        pointerStrokeLayer.isHidden = false
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        loadSettings()
        setupGestures()
        setupPointerIndicator()
    }

    private func loadSettings() {
        tapDurationThreshold = UserDefaults.standard.object(forKey: "tapDurationThreshold") as? TimeInterval ?? 0.4
        tapMovementThreshold = CGFloat(UserDefaults.standard.object(forKey: "tapMovementThreshold") as? Double ?? 10.0)
        tapDelayThreshold = UserDefaults.standard.object(forKey: "tapDelayThreshold") as? TimeInterval ?? 0.15
        print("🔧 Loaded settings - Duration: \(tapDurationThreshold)s, Movement: \(tapMovementThreshold)pts, Delay: \(tapDelayThreshold)s")
    }

    func updateSettings(_ settings: TouchpadSettings) {
        tapDurationThreshold = settings.tapDurationThreshold
        tapMovementThreshold = CGFloat(settings.tapMovementThreshold)
        tapDelayThreshold = settings.tapDelayThreshold
        print("🔧 Updated settings - Duration: \(tapDurationThreshold)s, Movement: \(tapMovementThreshold)pts, Delay: \(tapDelayThreshold)s")
    }

    private func setupGestures() {
        print("🎯 Setting up gestures...")

        // Two-finger tap gesture for right click
        let twoFingerTap = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerTap))
        twoFingerTap.numberOfTouchesRequired = 2
        twoFingerTap.numberOfTapsRequired = 1
        addGestureRecognizer(twoFingerTap)
        print("✅ Added two-finger tap gesture")

        // Long press gesture for drag mode toggle
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.5 // 500ms for long press
        longPress.numberOfTouchesRequired = 1
        addGestureRecognizer(longPress)
        print("✅ Added long press gesture")

        // Double tap gesture for double click (changed from triple tap)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTap.numberOfTouchesRequired = 1
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        print("✅ Added double tap gesture")

        // Pan gesture for mouse movement
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.minimumNumberOfTouches = 1
        panGesture.maximumNumberOfTouches = 1
        addGestureRecognizer(panGesture)
        print("✅ Added pan gesture")

        // Two-finger pan gesture for scrolling
        let twoFingerPan = UIPanGestureRecognizer(target: self, action: #selector(handleTwoFingerPan(_:)))
        twoFingerPan.minimumNumberOfTouches = 2
        twoFingerPan.maximumNumberOfTouches = 2
        addGestureRecognizer(twoFingerPan)
        print("✅ Added two-finger pan gesture for scrolling")

        // Enable multiple touches
        isMultipleTouchEnabled = true
        print("✅ Enabled multiple touches")
        print("🎯 Gesture setup complete")
    }

    @objc private func handleTwoFingerTap() {
        print("Two-finger tap detected - performing right click")
        hapticManager.triggerButtonPress()
        mouseManager?.handleRightClick()
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            print("Long press detected - toggling drag mode")
            hapticManager.triggerMediumFeedback()
            mouseManager?.handleDragModeToggle()
        }
    }

    @objc private func handleDoubleTap() {
        print("Double tap detected - performing double click")
        cancelPendingTap() // Cancel any pending single tap
        mouseManager?.handleDoubleClick()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: self)

        switch gesture.state {
        case .began:
            print("🔥 handlePan began - cancelling pending tap, starting drag")
            cancelPendingTap() // Cancel any pending tap when drag starts
            dragStartPosition = location
            isDragging = true
            pointerTipState?.pointerPosition = location
            pointerTipState?.isDragging = true
            mouseManager?.handleDragChanged(currentPosition: location)
        case .changed:
            if isDragging {
                pointerTipState?.pointerPosition = location
                mouseManager?.handleDragChanged(currentPosition: location)
            }
        case .ended, .cancelled:
            print("🔥 handlePan ended/cancelled - stopping drag")
            isDragging = false
            dragStartPosition = nil
            pointerTipState?.pointerPosition = nil
            pointerTipState?.isDragging = false
            mouseManager?.handleDragEnded()
        default:
            break
        }
    }

    @objc private func handleTwoFingerPan(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: self)

        switch gesture.state {
        case .began:
            print("🖱️ Two-finger scroll began")
            cancelPendingTap() // Cancel any pending tap when scroll starts
            twoFingerScrollPrevious = location
        case .changed:
            guard let previousLocation = twoFingerScrollPrevious else { return }

            let deltaX = location.x - previousLocation.x
            let deltaY = location.y - previousLocation.y

            // Apply configurable scroll sensitivity (default 1.0x, range 0.2x-2.0x)
            let sensitivity = touchpadSettings?.scrollSensitivity ?? 1.0
            let scrollDeltaX = Int(deltaX / 3.0 * sensitivity)
            let scrollDeltaY = Int(-deltaY / 3.0 * sensitivity)

            // Only send scroll if there's meaningful movement
            if abs(scrollDeltaX) > 0 || abs(scrollDeltaY) > 0 {
                print("🖱️ Two-finger scroll - deltaX: \(scrollDeltaX), deltaY: \(scrollDeltaY)")
                mouseManager?.handleScroll(deltaX: scrollDeltaX, deltaY: scrollDeltaY)
            }

            twoFingerScrollPrevious = location
        case .ended, .cancelled:
            print("🖱️ Two-finger scroll ended")
            twoFingerScrollPrevious = nil
        default:
            break
        }
    }

    // Override touch methods for better tap detection
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)

        print("🟢 touchesBegan - touches.count: \(touches.count), allTouches: \(event?.allTouches?.count ?? 0)")

        guard let touch = touches.first else {
            print("❌ touchesBegan - no first touch")
            return
        }
        let location = touch.location(in: self)

        // Check if it's a single finger touch
        if touches.count == 1 && event?.allTouches?.count == 1 {
            tapStartTime = Date()
            pendingTapLocation = location
            print("✅ touchesBegan - single finger detected at \(location), starting tap detection")
        } else {
            print("⚠️ touchesBegan - multi-finger touch detected, ignoring tap")
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)

        print("🔄 touchesMoved - touches.count: \(touches.count), allTouches: \(event?.allTouches?.count ?? 0)")

        // If there's movement during a potential tap, check if it exceeds threshold
        if let startLocation = pendingTapLocation,
           let touch = touches.first,
           touches.count == 1 && event?.allTouches?.count == 1 {
            let currentLocation = touch.location(in: self)
            let distance = sqrt(pow(currentLocation.x - startLocation.x, 2) +
                              pow(currentLocation.y - startLocation.y, 2))

            print("📏 touchesMoved - distance moved: \(distance), threshold: \(tapMovementThreshold)")

            // If movement exceeds threshold, cancel pending tap
            if distance > tapMovementThreshold {
                print("❌ touchesMoved - movement exceeds threshold, cancelling tap")
                cancelPendingTap()
            }
        } else if pendingTapLocation != nil {
            print("⚠️ touchesMoved - conditions not met for tap tracking")
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)

        print("🔴 touchesEnded - touches.count: \(touches.count), allTouches: \(event?.allTouches?.count ?? 0)")

        guard let touch = touches.first,
              let startTime = tapStartTime,
              let tapLocation = pendingTapLocation else {
            print("❌ touchesEnded - missing required data (touch/startTime/tapLocation)")
            return
        }

        let currentLocation = touch.location(in: self)
        let tapDuration = Date().timeIntervalSince(startTime)

        print("⏱️ touchesEnded - tap duration: \(tapDuration)s, max allowed: \(tapDurationThreshold)s")

        // Check if it's a valid single tap
        if touches.count == 1 &&
           event?.allTouches?.count == 1 &&
           tapDuration < tapDurationThreshold { // Increased to allow slightly slower taps

            let distance = sqrt(pow(currentLocation.x - tapLocation.x, 2) +
                              pow(currentLocation.y - tapLocation.y, 2))

            print("📏 touchesEnded - total distance moved: \(distance), threshold: \(tapMovementThreshold)")

            // If finger didn't move much, schedule a delayed tap
            if distance <= tapMovementThreshold {
                print("✅ touchesEnded - valid tap detected, scheduling pending tap")
                schedulePendingTap()
            } else {
                print("❌ touchesEnded - movement too large for tap")
            }
        } else {
            print("❌ touchesEnded - invalid tap conditions (multi-finger: \(touches.count != 1), duration too long: \(tapDuration >= tapDurationThreshold))")
        }

        // Clean up
        tapStartTime = nil
        pendingTapLocation = nil
        print("🧹 touchesEnded - cleaned up tap tracking variables")
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        print("🚫 touchesCancelled - cleaning up")
        cancelPendingTap()
        tapStartTime = nil
        pendingTapLocation = nil
    }

    private func schedulePendingTap() {
        // Cancel any existing timer
        tapTimer?.invalidate()

        print("⏰ schedulePendingTap - scheduling tap with \(tapDelayThreshold)s delay")

        // Schedule a delayed tap to check if a drag gesture follows
        tapTimer = Timer.scheduledTimer(withTimeInterval: tapDelayThreshold, repeats: false) { [weak self] _ in
            print("⏰ Timer fired - executing pending tap")
            self?.executePendingTap()
        }
    }

    private func executePendingTap() {
        print("🎯 executePendingTap - isDragging: \(isDragging)")

        // Only execute if we're not currently dragging
        if !isDragging {
            print("✅ Single tap confirmed - performing click")
            mouseManager?.handleClick()
        } else {
            print("❌ Drag in progress - cancelling click")
        }
        tapTimer = nil
    }

    private func cancelPendingTap() {
        if tapTimer != nil {
            print("🚫 cancelPendingTap - cancelling pending tap timer")
        }
        tapTimer?.invalidate()
        tapTimer = nil
    }
}
