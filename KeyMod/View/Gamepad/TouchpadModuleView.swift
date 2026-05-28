//
//  TouchpadModuleView.swift
//  KeyMod
//
//  Touchpad module for dynamic gamepad layouts.
//  UIView-backed surface with full multi-touch — matches Android's drawTouchpadModule
//  and TouchPadView gesture handling.
//
//  Features:
//  - 1-finger drag → mouse delta (move)
//  - 1-finger tap → left click (with double-tap suppression)
//  - 1-finger double-tap → double click
//  - 2-finger tap → right click
//  - 2-finger drag → scroll (fractional accumulation)
//  - Touch release on gesture end to reset mouse button state
//
//  L/M/R buttons are separate MOUSE_BUTTON modules in the preset, NOT embedded here.
//

import SwiftUI
import UIKit

// MARK: - SwiftUI Wrapper

struct TouchpadModuleView: View {
    @ObservedObject var mouseManager: MouseManager
    let isEditMode: Bool

    var body: some View {
        TouchpadModuleUIViewRepresentable(
            mouseManager: mouseManager,
            isEditMode: isEditMode
        )
    }
}

// MARK: - UIViewRepresentable Bridge

struct TouchpadModuleUIViewRepresentable: UIViewRepresentable {
    let mouseManager: MouseManager
    let isEditMode: Bool

    func makeUIView(context: Context) -> TouchpadModuleUIView {
        let view = TouchpadModuleUIView()
        view.mouseManager = mouseManager
        view.isEditMode = isEditMode
        view.isUserInteractionEnabled = !isEditMode
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: TouchpadModuleUIView, context: Context) {
        uiView.mouseManager = mouseManager
        uiView.isEditMode = isEditMode
        uiView.isUserInteractionEnabled = !isEditMode
    }
}

// MARK: - UIView Implementation

class TouchpadModuleUIView: UIView {

    weak var mouseManager: MouseManager?
    var isEditMode = false

    // Fractional scroll accumulation (matches Android twoFingerScrollAccumX/Y)
    private var scrollAccumX: Float = 0
    private var scrollAccumY: Float = 0

    // Double-tap suppression (matches Android suppressSingleTapFromDoubleTap)
    private var suppressSingleTapFromDoubleTap = false
    private var doubleTapSuppressUntil: Date?

    // Pending tap tracking
    private var pendingTapLocation: CGPoint?
    private var tapStartTime: Date?
    private var tapTimer: Timer?
    private var isDragging = false
    private var lastTouchLocation: CGPoint?

    // Haptic feedback
    private let hapticManager = HapticFeedbackManager.shared

    // Thresholds
    private let tapDurationThreshold: TimeInterval = 0.35
    private let tapMovementThreshold: CGFloat = 8.0
    private let tapDelayThreshold: TimeInterval = 0.15

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupAppearance()
        setupGestures()
        isMultipleTouchEnabled = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupAppearance()
        setupGestures()
        isMultipleTouchEnabled = true
    }

    static let settingsButtonExclusionSize: CGFloat = 28

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let inset = Self.settingsButtonExclusionSize
        let settingsRect = CGRect(
            x: bounds.width - inset,
            y: 0,
            width: inset,
            height: inset
        )
        if settingsRect.contains(point) {
            return nil  // let SwiftUI handle it
        }
        return super.hitTest(point, with: event)
    }

    // MARK: - Appearance

    private func setupAppearance() {
        // Gradient background matching Android surface colors
        let gradientLayer = CAGradientLayer()
        gradientLayer.colors = [
            UIColor(red: 0.93, green: 0.94, blue: 0.96, alpha: 1.0).cgColor,
            UIColor(red: 0.85, green: 0.86, blue: 0.89, alpha: 1.0).cgColor
        ]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        gradientLayer.frame = bounds
        gradientLayer.cornerRadius = 10
        layer.insertSublayer(gradientLayer, at: 0)

        // Dot grid pattern (Android's gloss dots)
        let dotLayer = CAShapeLayer()
        let dotRadius: CGFloat = 0.65
        let spacing: CGFloat = 16
        let path = CGMutablePath()
        var x: CGFloat = spacing
        while x < bounds.width - 8 {
            var y: CGFloat = spacing
            while y < bounds.height - 8 {
                path.addEllipse(in: CGRect(x: x, y: y, width: dotRadius * 2, height: dotRadius * 2))
                y += spacing
            }
            x += spacing
        }
        dotLayer.path = path
        dotLayer.fillColor = UIColor.black.withAlphaComponent(0.08).cgColor
        layer.insertSublayer(dotLayer, at: 1)

        // Label
        let label = UILabel()
        label.text = "Touchpad"
        label.font = UIFont.systemFont(ofSize: 11, weight: .medium)
        label.textColor = UIColor(red: 0.36, green: 0.38, blue: 0.41, alpha: 1.0)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        // Border
        layer.borderColor = UIColor(red: 0.65, green: 0.68, blue: 0.72, alpha: 1.0).cgColor
        layer.borderWidth = 1
        layer.cornerRadius = 10
        layer.masksToBounds = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Update gradient layer frame on resize
        if let gradientLayer = layer.sublayers?.first as? CAGradientLayer {
            gradientLayer.frame = bounds
        }
    }

    // MARK: - Gesture Setup

    private func setupGestures() {
        // Two-finger tap for right click
        let twoFingerTap = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerTap))
        twoFingerTap.numberOfTouchesRequired = 2
        twoFingerTap.numberOfTapsRequired = 1
        addGestureRecognizer(twoFingerTap)

        // Double tap for double click
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTap.numberOfTouchesRequired = 1
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)

        // Single-finger pan for mouse movement
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.minimumNumberOfTouches = 1
        panGesture.maximumNumberOfTouches = 1
        addGestureRecognizer(panGesture)

        // Two-finger pan for scrolling
        let twoFingerPan = UIPanGestureRecognizer(target: self, action: #selector(handleTwoFingerPan(_:)))
        twoFingerPan.minimumNumberOfTouches = 2
        twoFingerPan.maximumNumberOfTouches = 2
        addGestureRecognizer(twoFingerPan)
    }

    // MARK: - Gesture Handlers

    @objc private func handleTwoFingerTap() {
        guard !isEditMode else { return }
        hapticManager.triggerButtonPress()
        mouseManager?.handleRightClick()
    }

    @objc private func handleDoubleTap() {
        guard !isEditMode else { return }
        cancelPendingTap()
        suppressSingleTapFromDoubleTap = true
        doubleTapSuppressUntil = Date().addingTimeInterval(0.3)
        hapticManager.triggerButtonPress()
        mouseManager?.handleDoubleClick()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard !isEditMode else { return }
        let location = gesture.location(in: self)

        switch gesture.state {
        case .began:
            cancelPendingTap()
            isDragging = true
            lastTouchLocation = location
            hapticManager.triggerButtonPress()
            // Send initial drag event
            mouseManager?.handleDragChanged(currentPosition: CGPoint(x: 100, y: 100))

        case .changed:
            guard let last = lastTouchLocation else { return }
            let dx = location.x - last.x
            let dy = location.y - last.y
            lastTouchLocation = location

            let basePosition = CGPoint(x: 100, y: 100)
            let currentPosition = CGPoint(x: basePosition.x + dx, y: basePosition.y + dy)
            mouseManager?.previousPosition = basePosition
            mouseManager?.handleDragChanged(currentPosition: currentPosition)

        case .ended, .cancelled:
            isDragging = false
            lastTouchLocation = nil
            mouseManager?.handleDragEnded()
            sendTouchRelease()

        default:
            break
        }
    }

    @objc private func handleTwoFingerPan(_ gesture: UIPanGestureRecognizer) {
        guard !isEditMode else { return }
        let location = gesture.location(in: self)

        switch gesture.state {
        case .began:
            cancelPendingTap()
            twoFingerScrollPrevious = location
            scrollAccumX = 0
            scrollAccumY = 0

        case .changed:
            guard let previousLocation = twoFingerScrollPrevious else { return }
            let deltaX = location.x - previousLocation.x
            let deltaY = location.y - previousLocation.y
            twoFingerScrollPrevious = location

            // Matches Android TouchPadView: accum += (delta / 3) * sensitivity
            let sensitivity: Float = 1.0
            scrollAccumX += Float(deltaX / 3.0) * sensitivity
            scrollAccumY += Float(-deltaY / 3.0) * sensitivity

            let scrollX = Int(scrollAccumX)
            let scrollY = Int(scrollAccumY)

            if scrollX != 0 { scrollAccumX -= Float(scrollX) }
            if scrollY != 0 { scrollAccumY -= Float(scrollY) }

            if scrollX != 0 || scrollY != 0 {
                mouseManager?.handleScroll(deltaX: scrollX, deltaY: scrollY)
            }

        case .ended, .cancelled:
            twoFingerScrollPrevious = nil
            scrollAccumX = 0
            scrollAccumY = 0

        default:
            break
        }
    }

    // Two-finger scroll previous location (stored here to avoid @State)
    private var twoFingerScrollPrevious: CGPoint?

    // MARK: - Touch Event Overrides (for tap detection)

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        // Only track single-finger taps
        if touches.count == 1 && event?.allTouches?.count == 1 {
            tapStartTime = Date()
            pendingTapLocation = location
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)

        // Cancel pending tap if movement exceeds threshold
        if let startLocation = pendingTapLocation,
           let touch = touches.first,
           touches.count == 1 && event?.allTouches?.count == 1 {
            let currentLocation = touch.location(in: self)
            let distance = sqrt(pow(currentLocation.x - startLocation.x, 2) +
                              pow(currentLocation.y - startLocation.y, 2))
            if distance > tapMovementThreshold {
                cancelPendingTap()
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        guard let touch = touches.first,
              let startTime = tapStartTime,
              let tapLocation = pendingTapLocation else {
            sendTouchRelease()
            return
        }

        let currentLocation = touch.location(in: self)
        let tapDuration = Date().timeIntervalSince(startTime)

        // Valid single tap: single finger, short duration, minimal movement
        if touches.count == 1 &&
           event?.allTouches?.count == 1 &&
           tapDuration < tapDurationThreshold {
            let distance = sqrt(pow(currentLocation.x - tapLocation.x, 2) +
                              pow(currentLocation.y - tapLocation.y, 2))
            if distance <= tapMovementThreshold {
                schedulePendingTap()
            }
        }

        tapStartTime = nil
        pendingTapLocation = nil
        sendTouchRelease()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        cancelPendingTap()
        tapStartTime = nil
        pendingTapLocation = nil
        sendTouchRelease()
    }

    // MARK: - Pending Tap Logic

    private func schedulePendingTap() {
        tapTimer?.invalidate()
        tapTimer = Timer.scheduledTimer(withTimeInterval: tapDelayThreshold, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            // Check double-tap suppression (matches Android suppressSingleTapFromDoubleTap)
            if self.suppressSingleTapFromDoubleTap {
                self.suppressSingleTapFromDoubleTap = false
                return
            }
            // Also check time-based suppression window
            if let suppressUntil = self.doubleTapSuppressUntil, Date() < suppressUntil {
                return
            }
            self.executePendingTap()
        }
    }

    private func executePendingTap() {
        guard !isDragging else { return }
        hapticManager.triggerButtonPress()
        mouseManager?.handleClick()
    }

    private func cancelPendingTap() {
        tapTimer?.invalidate()
        tapTimer = nil
    }

    // MARK: - Touch Release

    /// Send a touch-release event to reset mouse button state on the host.
    /// Matches Android's listener.onTouchRelease() on ACTION_UP/ACTION_CANCEL.
    private func sendTouchRelease() {
        let packet = Keymod.buildMouseRel(buttons: 0x00, dx: 0, dy: 0, wheel: 0)
        mouseManager?.bleManager.sendTouchData(data: packet)
    }
}
