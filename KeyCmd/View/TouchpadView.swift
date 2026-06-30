//
//  TouchpadView.swift
//  KeyMod
//
//  Created by System on 2025/6/21.
//

import SwiftUI
import UIKit

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
    /// When false, disables pad tap/click/drag gestures — pointer movement and two-finger scroll only.
    var padClickDragGesturesEnabled: Bool = true
    /// Callback when pointer movement state changes (true = moving, false = idle)
    var onPointerMoving: ((Bool) -> Void)?

    func makeUIView(context: Context) -> UIView {
        let view = TouchpadUIView()
        view.mouseManager = mouseManager
        view.touchpadSettings = touchpadSettings
        view.pointerTipState = pointerTipState
        view.backgroundColor = UIColor.clear
        view.padClickDragGesturesEnabled = padClickDragGesturesEnabled
        view.onPointerMoving = onPointerMoving
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let touchpadView = uiView as? TouchpadUIView {
            touchpadView.updateSettings(touchpadSettings)
            touchpadView.padClickDragGesturesEnabled = padClickDragGesturesEnabled
        }
    }
}

class TouchpadUIView: UIView {
    var mouseManager: MouseManager?
    var touchpadSettings: TouchpadSettings?
    /// When false, disables pad tap/click/drag gestures — pointer movement and two-finger scroll only.
    var padClickDragGesturesEnabled = true
    /// Fires when pointer movement state changes (true = moving, false = idle)
    var onPointerMoving: ((Bool) -> Void)?
    private var wasPointerMoving = false
    var pointerTipState: PointerTipState?
    private var dragStartPosition: CGPoint?
    private var isDragging = false
    private var tapTimer: Timer?
    private var pendingTapLocation: CGPoint?
    private var tapStartTime: Date?
    private var twoFingerScrollPrevious: CGPoint?

    // Double-tap suppression (matches Android suppressSingleTapFromDoubleTap)
    private var suppressSingleTapFromDoubleTap = false

    // Fractional scroll accumulation (matches Android twoFingerScrollAccumX/Y)
    private var scrollAccumX: Float = 0
    private var scrollAccumY: Float = 0

    private let hapticManager = HapticFeedbackManager.shared

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
        // Removed: no pointer indicator circles on touchpad
    }

    private func updatePointerIndicator() {
        // Removed: no pointer indicator circles on touchpad
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
        LogManager.shared.log("Loaded settings - Duration: \(tapDurationThreshold)s, Movement: \(tapMovementThreshold)pts, Delay: \(tapDelayThreshold)s", category: "Touchpad")
    }

    func updateSettings(_ settings: TouchpadSettings) {
        tapDurationThreshold = settings.tapDurationThreshold
        tapMovementThreshold = CGFloat(settings.tapMovementThreshold)
        tapDelayThreshold = settings.tapDelayThreshold
        LogManager.shared.log("Updated settings - Duration: \(tapDurationThreshold)s, Movement: \(tapMovementThreshold)pts, Delay: \(tapDelayThreshold)s", category: "Touchpad")
    }

    private func setupGestures() {
        LogManager.shared.log("Setting up gestures...", category: "Touchpad")

        // Two-finger tap gesture for right click
        let twoFingerTap = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerTap))
        twoFingerTap.numberOfTouchesRequired = 2
        twoFingerTap.numberOfTapsRequired = 1
        addGestureRecognizer(twoFingerTap)
        LogManager.shared.log("Added two-finger tap gesture", category: "Touchpad", level: .success)

        // Long press gesture for drag mode toggle
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.5 // 500ms for long press
        longPress.numberOfTouchesRequired = 1
        addGestureRecognizer(longPress)
        LogManager.shared.log("Added long press gesture", category: "Touchpad", level: .success)

        // Double tap gesture for double click (changed from triple tap)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTap.numberOfTouchesRequired = 1
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        LogManager.shared.log("Added double tap gesture", category: "Touchpad", level: .success)

        // Pan gesture for mouse movement
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.minimumNumberOfTouches = 1
        panGesture.maximumNumberOfTouches = 1
        addGestureRecognizer(panGesture)
        LogManager.shared.log("Added pan gesture", category: "Touchpad", level: .success)

        // Two-finger pan gesture for scrolling
        let twoFingerPan = UIPanGestureRecognizer(target: self, action: #selector(handleTwoFingerPan(_:)))
        twoFingerPan.minimumNumberOfTouches = 2
        twoFingerPan.maximumNumberOfTouches = 2
        addGestureRecognizer(twoFingerPan)
        LogManager.shared.log("Added two-finger pan gesture for scrolling", category: "Touchpad", level: .success)

        // Enable multiple touches
        isMultipleTouchEnabled = true
        LogManager.shared.log("Enabled multiple touches", category: "Touchpad", level: .success)
        LogManager.shared.log("Gesture setup complete", category: "Touchpad")
    }

    @objc private func handleTwoFingerTap() {
        print("Two-finger tap detected - performing right click")
        hapticManager.triggerButtonPress()
        mouseManager?.handleRightClick()
    }

    // Tracks whether a long-press just toggled drag mode, to prevent pan's
    // .ended from immediately releasing the button via sendTouchRelease().
    private var longPressJustFired = false

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began && padClickDragGesturesEnabled {
            print("Long press detected - toggling drag mode")
            hapticManager.triggerMediumFeedback()
            longPressJustFired = true
            mouseManager?.handleDragModeToggle()
        }
    }

    @objc private func handleDoubleTap() {
        print("Double tap detected - performing double click")
        cancelPendingTap() // Cancel any pending single tap
        suppressSingleTapFromDoubleTap = true // Prevent stray single-tap after double-tap
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
            onPointerMoving?(true)
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
            onPointerMoving?(false)
            mouseManager?.handleDragEnded()
            // Don't release buttons if long-press just toggled drag mode
            // or if currently in select (drag) mode — user must tap to cancel.
            if longPressJustFired {
                longPressJustFired = false
            } else if !(mouseManager?.isSelectMode ?? false) {
                sendTouchRelease()
            }
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
            scrollAccumX = 0
            scrollAccumY = 0
        case .changed:
            guard let previousLocation = twoFingerScrollPrevious else { return }

            let deltaX = location.x - previousLocation.x
            let deltaY = location.y - previousLocation.y

            // Apply configurable scroll sensitivity and accumulate fractional values
            // Matches Android TouchPadView: accum += (delta / 3) * sensitivity
            let sensitivity = Float(touchpadSettings?.scrollSensitivity ?? 1.0)
            scrollAccumX += Float(deltaX / 3.0) * sensitivity
            scrollAccumY += Float(-deltaY / 3.0) * sensitivity

            // Extract integer portions
            let scrollX = Int(scrollAccumX)
            let scrollY = Int(scrollAccumY)

            // Subtract flushed portions from accumulators
            if scrollX != 0 {
                scrollAccumX -= Float(scrollX)
            }
            if scrollY != 0 {
                scrollAccumY -= Float(scrollY)
            }

            // Only send scroll if there's meaningful movement
            if scrollX != 0 || scrollY != 0 {
                print("🖱️ Two-finger scroll - deltaX: \(scrollX), deltaY: \(scrollY)")
                mouseManager?.handleScroll(deltaX: scrollX, deltaY: scrollY)
            }

            twoFingerScrollPrevious = location
        case .ended, .cancelled:
            print("🖱️ Two-finger scroll ended")
            twoFingerScrollPrevious = nil
            scrollAccumX = 0
            scrollAccumY = 0
        default:
            break
        }
    }

    /// Send a touch-release event to reset mouse button state on the host.
    /// Matches Android's listener.onTouchRelease() on ACTION_UP/ACTION_CANCEL.
    private func sendTouchRelease() {
        // Send all-zeros mouse report to release any held buttons
        let packet = Keymod.buildMouseRel(buttons: 0x00, dx: 0, dy: 0, wheel: 0)
        mouseManager?.bleManager.sendTouchData(data: packet)
    }

    // Override touch methods for better tap detection
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)

        LogManager.shared.log("touchesBegan - touches.count: \(touches.count), allTouches: \(event?.allTouches?.count ?? 0)", category: "Touchpad")

        guard let touch = touches.first else {
            LogManager.shared.log("touchesBegan - no first touch", category: "Touchpad", level: .warning)
            return
        }
        let location = touch.location(in: self)

        // Check if it's a single finger touch
        if touches.count == 1 && event?.allTouches?.count == 1 {
            if padClickDragGesturesEnabled {
                tapStartTime = Date()
                pendingTapLocation = location
            }
            LogManager.shared.log("touchesBegan - single finger detected at \(location), starting tap detection", category: "Touchpad", level: .success)
        } else {
            LogManager.shared.log("touchesBegan - multi-finger touch detected, ignoring tap", category: "Touchpad")
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)

        LogManager.shared.log("touchesMoved - touches.count: \(touches.count), allTouches: \(event?.allTouches?.count ?? 0)", category: "Touchpad")

        // If there's movement during a potential tap, check if it exceeds threshold
        if let startLocation = pendingTapLocation,
           let touch = touches.first,
           touches.count == 1 && event?.allTouches?.count == 1 {
            let currentLocation = touch.location(in: self)
            let distance = sqrt(pow(currentLocation.x - startLocation.x, 2) +
                              pow(currentLocation.y - startLocation.y, 2))

            LogManager.shared.log("touchesMoved - distance moved: \(distance), threshold: \(tapMovementThreshold)", category: "Touchpad")

            // If movement exceeds threshold, cancel pending tap
            if distance > tapMovementThreshold {
                LogManager.shared.log("touchesMoved - movement exceeds threshold, cancelling tap", category: "Touchpad", level: .warning)
                cancelPendingTap()
            }
        } else if pendingTapLocation != nil {
            LogManager.shared.log("touchesMoved - conditions not met for tap tracking", category: "Touchpad")
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)

        LogManager.shared.log("touchesEnded - touches.count: \(touches.count), allTouches: \(event?.allTouches?.count ?? 0)", category: "Touchpad")

        guard let touch = touches.first,
              let startTime = tapStartTime,
              let tapLocation = pendingTapLocation else {
            LogManager.shared.log("touchesEnded - missing required data (touch/startTime/tapLocation)", category: "Touchpad", level: .warning)
            sendTouchRelease()
            return
        }

        let currentLocation = touch.location(in: self)
        let tapDuration = Date().timeIntervalSince(startTime)

        LogManager.shared.log("touchesEnded - tap duration: \(tapDuration)s, max allowed: \(tapDurationThreshold)s", category: "Touchpad")

        // Check if it's a valid single tap
        if padClickDragGesturesEnabled &&
           touches.count == 1 &&
           event?.allTouches?.count == 1 &&
           tapDuration < tapDurationThreshold {

            let distance = sqrt(pow(currentLocation.x - tapLocation.x, 2) +
                              pow(currentLocation.y - tapLocation.y, 2))

            LogManager.shared.log("touchesEnded - total distance moved: \(distance), threshold: \(tapMovementThreshold)", category: "Touchpad")

            // If finger didn't move much, schedule a delayed tap
            if distance <= tapMovementThreshold {
                LogManager.shared.log("touchesEnded - valid tap detected, scheduling pending tap", category: "Touchpad", level: .success)
                schedulePendingTap()
            } else {
                LogManager.shared.log("touchesEnded - movement too large for tap", category: "Touchpad", level: .warning)
            }
        } else {
            LogManager.shared.log("touchesEnded - invalid tap conditions (multi-finger: \(touches.count != 1), duration too long: \(tapDuration >= tapDurationThreshold))", category: "Touchpad", level: .warning)
        }

        // Clean up
        tapStartTime = nil
        pendingTapLocation = nil
        sendTouchRelease()
        LogManager.shared.log("touchesEnded - cleaned up tap tracking variables", category: "Touchpad")
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        LogManager.shared.log("touchesCancelled - cleaning up", category: "Touchpad", level: .warning)
        cancelPendingTap()
        tapStartTime = nil
        pendingTapLocation = nil
        sendTouchRelease()
    }

    private func schedulePendingTap() {
        // Cancel any existing timer
        tapTimer?.invalidate()

        print("⏰ schedulePendingTap - scheduling tap with \(tapDelayThreshold)s delay")

        // Schedule a delayed tap to check if a drag gesture follows
        tapTimer = Timer.scheduledTimer(withTimeInterval: tapDelayThreshold, repeats: false) { [weak self] _ in
            print("⏰ Timer fired - executing pending tap")
            guard let self = self else { return }
            // Check double-tap suppression (matches Android suppressSingleTapFromDoubleTap)
            if self.suppressSingleTapFromDoubleTap {
                self.suppressSingleTapFromDoubleTap = false
                LogManager.shared.log("Pending tap suppressed due to double-tap", category: "Touchpad", level: .warning)
            } else {
                self.executePendingTap()
            }
        }
    }

    private func executePendingTap() {
        LogManager.shared.log("executePendingTap - isDragging: \(isDragging), isSelectMode: \(mouseManager?.isSelectMode ?? false)", category: "Touchpad")

        // In drag mode, single tap exits drag mode instead of sending click
        if mouseManager?.isSelectMode == true {
            LogManager.shared.log("Single tap in drag mode — exiting drag mode", category: "Touchpad")
            mouseManager?.handleDragModeToggle()
            tapTimer = nil
            return
        }

        // Only execute if we're not currently dragging
        if !isDragging {
            LogManager.shared.log("Single tap confirmed - performing click", category: "Touchpad", level: .success)
            mouseManager?.handleClick()
        } else {
            LogManager.shared.log("Drag in progress - cancelling click", category: "Touchpad", level: .warning)
        }
        tapTimer = nil
    }

    private func cancelPendingTap() {
        if tapTimer != nil {
            LogManager.shared.log("cancelPendingTap - cancelling pending tap timer", category: "Touchpad", level: .warning)
        }
        tapTimer?.invalidate()
        tapTimer = nil
    }
}
