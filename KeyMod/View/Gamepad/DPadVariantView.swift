//
//  DPadVariantView.swift
//  KeyMod
//
//  D-pad with 6 visual variants: cross, disc, split, floating, clicky, pivot.
//  All variants produce identical directional key events.
//
//  Touch model: entire DPad is a single UIView that tracks all touches via
//  UITouch.hashValue and determines direction zones based on touch location.
//  This matches Android's per-pointerID zone detection — multiple fingers can
//  press different directions simultaneously, and dragging between zones releases
//  the old direction and presses the new one.
//

import SwiftUI
import UIKit

// MARK: - Shared state for D-pad direction tracking

class DPadButtonState: ObservableObject {
    @Published var pressedDirections: Set<String> = []

    private let hapticManager = HapticFeedbackManager.shared

    func press(_ direction: String) {
        if !pressedDirections.contains(direction) {
            pressedDirections.insert(direction)
            hapticManager.triggerButtonPress()
        }
    }

    func release(_ direction: String) {
        pressedDirections.remove(direction)
    }
}

// MARK: - Direction zone detection

struct DPadTouchZone {
    let direction: String
    let frame: CGRect

    func contains(_ point: CGPoint) -> Bool { frame.contains(point) }
}

// MARK: - UIKit DPad View

class DPadUIView: UIView {

    var onDirectionPress: ((String) -> Void)?
    var onDirectionRelease: ((String) -> Void)?

    // Track active touches: UITouch.hashValue → direction
    private var activeTouches: [Int: String] = [:]

    // Direction zones (set during layout)
    private var zones: [DPadTouchZone] = []

    // Visual appearance
    let variant: DPadVariant
    private let baseRadius: CGFloat
    private let accentColor: UIColor

    // Background layers
    private var backgroundLayer: CALayer?
    private var shapeLayers: [CALayer] = []

    // Direction label layers
    private var labelLayers: [UILabel] = []

    init(variant: DPadVariant, baseRadius: CGFloat) {
        self.variant = variant
        self.baseRadius = baseRadius
        self.accentColor = UIColor(red: 0.15, green: 0.15, blue: 0.18, alpha: 1.0)
        super.init(frame: .zero)
        isUserInteractionEnabled = true
        isMultipleTouchEnabled = true
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Zone layout

    private func buildZones() {
        zones = []
        let btnSize = zoneButtonSize()

        switch variant {
        case .cross, .floating, .clicky, .pivot:
            // Cross layout: 4 directional buttons
            let upFrame = CGRect(
                x: (bounds.width - btnSize.width) / 2,
                y: 0,
                width: btnSize.width,
                height: btnSize.height
            )
            let downFrame = CGRect(
                x: (bounds.width - btnSize.width) / 2,
                y: bounds.height - btnSize.height,
                width: btnSize.width,
                height: btnSize.height
            )
            let leftFrame = CGRect(
                x: 0,
                y: (bounds.height - btnSize.height) / 2,
                width: btnSize.width,
                height: btnSize.height
            )
            let rightFrame = CGRect(
                x: bounds.width - btnSize.width,
                y: (bounds.height - btnSize.height) / 2,
                width: btnSize.width,
                height: btnSize.height
            )
            zones = [
                DPadTouchZone(direction: "Up", frame: upFrame),
                DPadTouchZone(direction: "Down", frame: downFrame),
                DPadTouchZone(direction: "Left", frame: leftFrame),
                DPadTouchZone(direction: "Right", frame: rightFrame)
            ]

        case .disc:
            // Disc layout: larger buttons
            let discBtnSize = baseRadius * 0.67
            let discBtnRect = CGRect(x: 0, y: 0, width: discBtnSize, height: discBtnSize)
            let upFrame = CGRect(
                x: (bounds.width - discBtnSize) / 2,
                y: 0,
                width: discBtnSize,
                height: discBtnSize
            )
            let downFrame = CGRect(
                x: (bounds.width - discBtnSize) / 2,
                y: bounds.height - discBtnSize,
                width: discBtnSize,
                height: discBtnSize
            )
            let leftFrame = CGRect(
                x: 0,
                y: (bounds.height - discBtnSize) / 2,
                width: discBtnSize,
                height: discBtnSize
            )
            let rightFrame = CGRect(
                x: bounds.width - discBtnSize,
                y: (bounds.height - discBtnSize) / 2,
                width: discBtnSize,
                height: discBtnSize
            )
            zones = [
                DPadTouchZone(direction: "Up", frame: upFrame),
                DPadTouchZone(direction: "Down", frame: downFrame),
                DPadTouchZone(direction: "Left", frame: leftFrame),
                DPadTouchZone(direction: "Right", frame: rightFrame)
            ]

        case .split:
            let gap = baseRadius * 0.08
            let upW = baseRadius * 0.8
            let upH = baseRadius * 0.67
            let sideW = baseRadius * 0.67
            let sideH = baseRadius * 0.8
            zones = [
                DPadTouchZone(direction: "Up", frame: CGRect(
                    x: (bounds.width - upW) / 2, y: 0, width: upW, height: upH)),
                DPadTouchZone(direction: "Down", frame: CGRect(
                    x: (bounds.width - upW) / 2, y: bounds.height - upH, width: upW, height: upH)),
                DPadTouchZone(direction: "Left", frame: CGRect(
                    x: 0, y: (bounds.height - sideH) / 2, width: sideW, height: sideH)),
                DPadTouchZone(direction: "Right", frame: CGRect(
                    x: bounds.width - sideW, y: (bounds.height - sideH) / 2, width: sideW, height: sideH))
            ]
        }
    }

    private func zoneButtonSize() -> CGSize {
        switch variant {
        case .cross:
            let btnSize = baseRadius * 0.5
            return CGSize(width: btnSize, height: btnSize)
        case .disc:
            let btnSize = baseRadius * 0.67
            return CGSize(width: btnSize, height: btnSize)
        case .split:
            let upW = baseRadius * 0.8
            let upH = baseRadius * 0.67
            return CGSize(width: upW, height: upH)
        case .floating:
            let btnSize = baseRadius * 0.5
            return CGSize(width: btnSize, height: btnSize)
        case .clicky:
            let btnSize = baseRadius * 0.5
            return CGSize(width: btnSize, height: btnSize)
        case .pivot:
            let btnSize = baseRadius * 0.5
            return CGSize(width: btnSize, height: btnSize)
        }
    }

    private func zoneForPoint(_ point: CGPoint) -> String? {
        for zone in zones where zone.contains(point) {
            return zone.direction
        }
        return nil
    }

    // MARK: - Touch handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        for touch in touches {
            let pointerId = touch.hashValue
            let location = touch.location(in: self)
            if let direction = zoneForPoint(location) {
                activeTouches[pointerId] = direction
                onDirectionPress?(direction)
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        for touch in touches {
            let pointerId = touch.hashValue
            let location = touch.location(in: self)
            let newDirection = zoneForPoint(location)
            let oldDirection = activeTouches[pointerId]

            if newDirection != oldDirection {
                // Release old direction
                if let old = oldDirection {
                    activeTouches[pointerId] = nil
                    onDirectionRelease?(old)
                }
                // Press new direction
                if let new = newDirection {
                    activeTouches[pointerId] = new
                    onDirectionPress?(new)
                }
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        for touch in touches {
            let pointerId = touch.hashValue
            if let direction = activeTouches.removeValue(forKey: pointerId) {
                onDirectionRelease?(direction)
            }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        for touch in touches {
            let pointerId = touch.hashValue
            if let direction = activeTouches.removeValue(forKey: pointerId) {
                onDirectionRelease?(direction)
            }
        }
    }

    // MARK: - Layout & drawing

    override func layoutSubviews() {
        super.layoutSubviews()
        buildZones()
        buildBackground()
        buildLabels()
    }

    private func buildBackground() {
        // Remove old layers
        backgroundLayer?.removeFromSuperlayer()
        shapeLayers.forEach { $0.removeFromSuperlayer() }
        backgroundLayer = nil
        shapeLayers = []

        let barHalf = baseRadius * 0.36
        let cornerRadius: CGFloat = 8

        switch variant {
        case .cross:
            // Vertical bar
            let vBar = CAShapeLayer()
            vBar.path = UIBezierPath(
                roundedRect: CGRect(x: (bounds.width - barHalf * 2) / 2, y: 0,
                                    width: barHalf * 2, height: bounds.height),
                cornerRadius: cornerRadius
            ).cgPath
            vBar.fillColor = UIColor(red: 0.22, green: 0.22, blue: 0.25, alpha: 1.0).cgColor
            layer.addSublayer(vBar)
            shapeLayers.append(vBar)

            // Horizontal bar
            let hBar = CAShapeLayer()
            hBar.path = UIBezierPath(
                roundedRect: CGRect(x: 0, y: (bounds.height - barHalf * 2) / 2,
                                    width: bounds.width, height: barHalf * 2),
                cornerRadius: cornerRadius
            ).cgPath
            hBar.fillColor = UIColor(red: 0.22, green: 0.22, blue: 0.25, alpha: 1.0).cgColor
            layer.addSublayer(hBar)
            shapeLayers.append(hBar)

            // Hub
            let hubSize = min(barHalf * 0.95, baseRadius * 0.22)
            let hub = CAShapeLayer()
            hub.path = UIBezierPath(
                ovalIn: CGRect(x: (bounds.width - hubSize) / 2,
                               y: (bounds.height - hubSize) / 2,
                               width: hubSize, height: hubSize)
            ).cgPath
            hub.fillColor = UIColor(red: 0.18, green: 0.18, blue: 0.21, alpha: 1.0).cgColor
            layer.addSublayer(hub)
            shapeLayers.append(hub)

        case .disc:
            let discLayer = CAGradientLayer()
            discLayer.colors = [
                UIColor(red: 0.25, green: 0.25, blue: 0.28, alpha: 1.0).cgColor,
                UIColor(red: 0.15, green: 0.15, blue: 0.18, alpha: 1.0).cgColor
            ]
            discLayer.startPoint = CGPoint(x: 0.5, y: 0)
            discLayer.endPoint = CGPoint(x: 0.5, y: 1)
            discLayer.frame = bounds
            discLayer.cornerRadius = bounds.width / 2
            layer.addSublayer(discLayer)
            backgroundLayer = discLayer
            shapeLayers.append(discLayer)

            // Border
            let borderLayer = CAShapeLayer()
            borderLayer.path = UIBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1)).cgPath
            borderLayer.strokeColor = UIColor.gray.withAlphaComponent(0.4).cgColor
            borderLayer.fillColor = nil
            borderLayer.lineWidth = 2
            layer.addSublayer(borderLayer)
            shapeLayers.append(borderLayer)

        case .split:
            // No background for split variant
            break

        case .floating:
            // Same as cross
            let vBar = CAShapeLayer()
            vBar.path = UIBezierPath(
                roundedRect: CGRect(x: (bounds.width - barHalf * 2) / 2, y: 0,
                                    width: barHalf * 2, height: bounds.height),
                cornerRadius: cornerRadius
            ).cgPath
            vBar.fillColor = UIColor(red: 0.22, green: 0.22, blue: 0.25, alpha: 1.0).cgColor
            layer.addSublayer(vBar)
            shapeLayers.append(vBar)

            let hBar = CAShapeLayer()
            hBar.path = UIBezierPath(
                roundedRect: CGRect(x: 0, y: (bounds.height - barHalf * 2) / 2,
                                    width: bounds.width, height: barHalf * 2),
                cornerRadius: cornerRadius
            ).cgPath
            hBar.fillColor = UIColor(red: 0.22, green: 0.22, blue: 0.25, alpha: 1.0).cgColor
            layer.addSublayer(hBar)
            shapeLayers.append(hBar)

            let hubSize = min(barHalf * 0.95, baseRadius * 0.22)
            let hub = CAShapeLayer()
            hub.path = UIBezierPath(
                ovalIn: CGRect(x: (bounds.width - hubSize) / 2,
                               y: (bounds.height - hubSize) / 2,
                               width: hubSize, height: hubSize)
            ).cgPath
            hub.fillColor = UIColor(red: 0.18, green: 0.18, blue: 0.21, alpha: 1.0).cgColor
            layer.addSublayer(hub)
            shapeLayers.append(hub)

        case .clicky:
            // Same as cross with thicker rim
            let vBar = CAShapeLayer()
            vBar.path = UIBezierPath(
                roundedRect: CGRect(x: (bounds.width - barHalf * 2) / 2, y: 0,
                                    width: barHalf * 2, height: bounds.height),
                cornerRadius: cornerRadius
            ).cgPath
            vBar.fillColor = UIColor(red: 0.22, green: 0.22, blue: 0.25, alpha: 1.0).cgColor
            layer.addSublayer(vBar)
            shapeLayers.append(vBar)

            let hBar = CAShapeLayer()
            hBar.path = UIBezierPath(
                roundedRect: CGRect(x: 0, y: (bounds.height - barHalf * 2) / 2,
                                    width: bounds.width, height: barHalf * 2),
                cornerRadius: cornerRadius
            ).cgPath
            hBar.fillColor = UIColor(red: 0.22, green: 0.22, blue: 0.25, alpha: 1.0).cgColor
            layer.addSublayer(hBar)
            shapeLayers.append(hBar)

            let hubSize = min(barHalf * 0.95, baseRadius * 0.22)
            let hub = CAShapeLayer()
            hub.path = UIBezierPath(
                ovalIn: CGRect(x: (bounds.width - hubSize) / 2,
                               y: (bounds.height - hubSize) / 2,
                               width: hubSize, height: hubSize)
            ).cgPath
            hub.fillColor = UIColor(red: 0.18, green: 0.18, blue: 0.21, alpha: 1.0).cgColor
            layer.addSublayer(hub)
            shapeLayers.append(hub)

            // Rim
            let rimLayer = CAShapeLayer()
            rimLayer.path = UIBezierPath(
                roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5),
                cornerRadius: 12
            ).cgPath
            rimLayer.strokeColor = UIColor.gray.withAlphaComponent(0.6).cgColor
            rimLayer.fillColor = nil
            rimLayer.lineWidth = 3
            layer.addSublayer(rimLayer)
            shapeLayers.append(rimLayer)

        case .pivot:
            // Capsule bars
            let vCapsule = CAShapeLayer()
            vCapsule.path = UIBezierPath(
                roundedRect: CGRect(x: (bounds.width - barHalf * 2) / 2, y: 0,
                                    width: barHalf * 2, height: bounds.height),
                cornerRadius: barHalf
            ).cgPath
            vCapsule.fillColor = UIColor.black.withAlphaComponent(0.7).cgColor
            layer.addSublayer(vCapsule)
            shapeLayers.append(vCapsule)

            let hCapsule = CAShapeLayer()
            hCapsule.path = UIBezierPath(
                roundedRect: CGRect(x: 0, y: (bounds.height - barHalf * 2) / 2,
                                    width: bounds.width, height: barHalf * 2),
                cornerRadius: barHalf
            ).cgPath
            hCapsule.fillColor = UIColor.black.withAlphaComponent(0.7).cgColor
            layer.addSublayer(hCapsule)
            shapeLayers.append(hCapsule)

            // Hub
            let hubSize = min(barHalf * 0.95, baseRadius * 0.22)
            let hub = CAShapeLayer()
            hub.path = UIBezierPath(
                ovalIn: CGRect(x: (bounds.width - hubSize) / 2,
                               y: (bounds.height - hubSize) / 2,
                               width: hubSize, height: hubSize)
            ).cgPath
            hub.fillColor = UIColor(red: 0.15, green: 0.15, blue: 0.18, alpha: 1.0).cgColor
            layer.addSublayer(hub)
            shapeLayers.append(hub)

            // Hub border
            let hubBorder = CAShapeLayer()
            hubBorder.path = UIBezierPath(
                ovalIn: CGRect(x: (bounds.width - hubSize) / 2,
                               y: (bounds.height - hubSize) / 2,
                               width: hubSize, height: hubSize).insetBy(dx: -1, dy: -1)
            ).cgPath
            hubBorder.strokeColor = UIColor.gray.withAlphaComponent(0.5).cgColor
            hubBorder.fillColor = nil
            hubBorder.lineWidth = 2
            layer.addSublayer(hubBorder)
            shapeLayers.append(hubBorder)
        }
    }

    private func buildLabels() {
        labelLayers.forEach { $0.removeFromSuperview() }
        labelLayers = []

        let iconNames = ["Up": "arrowtriangle.up.fill", "Down": "arrowtriangle.down.fill",
                         "Left": "arrowtriangle.left.fill", "Right": "arrowtriangle.right.fill"]

        for zone in zones {
            let label = UILabel()
            label.text = iconNames[zone.direction]
            label.font = UIFont.systemFont(ofSize: 16, weight: .bold)
            label.textAlignment = .center
            label.textColor = UIColor.gray.withAlphaComponent(0.7)
            label.frame = zone.frame
            label.isUserInteractionEnabled = false
            addSubview(label)
            labelLayers.append(label)
        }
    }

    // MARK: - Visual feedback for pressed directions

    func setPressedDirections(_ directions: Set<String>) {
        for (index, label) in labelLayers.enumerated() {
            if index < zones.count {
                let zone = zones[index]
                let isPressed = directions.contains(zone.direction)
                label.textColor = isPressed ? .white : UIColor.gray.withAlphaComponent(0.7)
                label.backgroundColor = isPressed
                    ? UIColor.blue.withAlphaComponent(0.5)
                    : UIColor.black.withAlphaComponent(0.3)
                label.layer.cornerRadius = 6
                label.clipsToBounds = true
            }
        }
    }
}

// MARK: - UIViewRepresentable wrapper

struct DPadViewRepresentable: UIViewRepresentable {
    let variant: DPadVariant
    let baseRadius: CGFloat
    @ObservedObject var buttonState: DPadButtonState
    var onDirection: ((String) -> Void)?
    var onDirectionUp: ((String) -> Void)?

    func makeUIView(context: Context) -> DPadUIView {
        let view = DPadUIView(variant: variant, baseRadius: baseRadius)
        view.onDirectionPress = { [weak buttonState] dir in
            buttonState?.press(dir)
            onDirection?(dir)
        }
        view.onDirectionRelease = { [weak buttonState] dir in
            buttonState?.release(dir)
            onDirectionUp?(dir)
        }
        return view
    }

    func updateUIView(_ uiView: DPadUIView, context: Context) {
        uiView.setPressedDirections(buttonState.pressedDirections)
    }
}

// MARK: - DPadVariantView (dispatcher)

struct DPadVariantView: View {
    var variant: DPadVariant = .cross
    let baseRadius: CGFloat
    var onDirection: ((String) -> Void)?
    var onDirectionUp: ((String) -> Void)?
    var onLongPress: ((String) -> Void)?
    let isEditMode: Bool
    let isKeyMappingMode: Bool

    @StateObject private var buttonState = DPadButtonState()

    var body: some View {
        Group {
            DPadViewRepresentable(
                variant: variant,
                baseRadius: baseRadius,
                buttonState: buttonState,
                onDirection: onDirection,
                onDirectionUp: onDirectionUp
            )
        }
        .frame(width: baseRadius * 2, height: baseRadius * 2)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isEditMode ? Color.orange : Color.clear, lineWidth: 3)
        )
    }
}

// MARK: - Legacy SwiftUI components (kept for reference, not used)

// These are the old SwiftUI-based direction buttons that used
// simultaneousGesture. They are kept here in case they are needed
// for other purposes, but the DPadVariantView now uses the UIKit-based
// DPadUIView for proper multi-touch support.
