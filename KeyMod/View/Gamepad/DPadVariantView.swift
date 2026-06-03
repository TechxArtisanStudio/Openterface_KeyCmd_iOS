//
//  DPadVariantView.swift
//  KeyMod
//
//  D-pad with 6 visual variants: cross, disc, split, floating, clicky, pivot.
//  All variants produce identical directional key events.
//
//  Touch model: each finger can activate one or two directions.
//  A touch in the overlap region between two adjacent directions (e.g. the
//  diagonal between Up and Right) activates BOTH simultaneously.
//  This allows a single finger to press WA/AS/SD/DW-style combos.
//
//  Matching Android's multi-touch pointer model: pointerId → Set<direction>.
//  dpadPressedSet aggregates all held directions across all fingers.
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

// MARK: - UIKit DPad View

class DPadUIView: UIView {

    var onDirectionPress: ((String) -> Void)?
    var onDirectionRelease: ((String) -> Void)?

    // Track active touches: pointerId → Set of directions.
    // A single finger near the diagonal overlap activates two directions.
    private var activeTouches: [Int: Set<String>] = [:]

    // Direction labels (WASD or custom key names)
    private var directionLabels: [String: String] = [:]

    // Visual appearance
    let variant: DPadVariant
    private let baseRadius: CGFloat
    private let accentColor: UIColor

    // Background layers
    private var backgroundLayer: CALayer?
    private var shapeLayers: [CALayer] = []

    // Direction label layers
    private var labelLayers: [UILabel] = []

    init(variant: DPadVariant, baseRadius: CGFloat, directionLabels: [String: String] = [:], isEditMode: Bool = false) {
        self.variant = variant
        self.baseRadius = baseRadius
        self.directionLabels = directionLabels
        self.accentColor = UIColor(red: 0.15, green: 0.15, blue: 0.18, alpha: 1.0)
        super.init(frame: .zero)
        isUserInteractionEnabled = !isEditMode
        isMultipleTouchEnabled = true
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

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

    // MARK: - Label layout

    private var labelFrames: [String: CGRect] = [:]

    private func buildLabelFrames() {
        let half = baseRadius
        let cx = bounds.midX, cy = bounds.midY
        let labelSize = baseRadius * 0.65
        labelFrames = [
            "Up":    CGRect(x: cx - labelSize / 2, y: cy - half * 0.55 - labelSize / 2, width: labelSize, height: labelSize),
            "Down":  CGRect(x: cx - labelSize / 2, y: cy + half * 0.55 - labelSize / 2, width: labelSize, height: labelSize),
            "Left":  CGRect(x: cx - half * 0.55 - labelSize / 2, y: cy - labelSize / 2, width: labelSize, height: labelSize),
            "Right": CGRect(x: cx + half * 0.55 - labelSize / 2, y: cy - labelSize / 2, width: labelSize, height: labelSize)
        ]
    }

    /// Returns direction keys activated by a touch at the given point.
    /// Uses dominant-axis detection: only the direction closest to the touch
    /// is activated. Diagonal touches (roughly equal x and y) activate both
    /// directions for combo movement.
    /// Center dead zone (15% of radius) prevents accidental activation.
    private func directionsForPoint(_ point: CGPoint) -> Set<String> {
        let cx = bounds.midX
        let cy = bounds.midY
        let dx = point.x - cx
        let dy = point.y - cy
        let dist = sqrt(dx * dx + dy * dy)

        // Dead zone at center (15% of radius — larger to prevent accidental activation)
        if dist < baseRadius * 0.15 {
            return []
        }

        // Too far outside the DPad
        if dist > baseRadius * 1.5 {
            return []
        }

        let absDx = abs(dx)
        let absDy = abs(dy)

        // If touch is very close to dead zone edge, require clearer direction
        if dist < baseRadius * 0.3 {
            // Require at least 2:1 ratio to activate a direction
            if absDx > absDy * 2 {
                return [dx > 0 ? "Right" : "Left"]
            } else if absDy > absDx * 2 {
                return [dy > 0 ? "Down" : "Up"]
            }
            return []
        }

        var result: Set<String> = []

        // Dominant axis detection
        if absDy > absDx {
            // Vertical dominates
            result.insert(dy < 0 ? "Up" : "Down")
            // Check if it's a diagonal (within 30% of each other)
            if absDx > absDy * 0.7 {
                result.insert(dx > 0 ? "Right" : "Left")
            }
        } else if absDx > absDy {
            // Horizontal dominates
            result.insert(dx > 0 ? "Right" : "Left")
            // Check if it's a diagonal
            if absDy > absDx * 0.7 {
                result.insert(dy < 0 ? "Up" : "Down")
            }
        } else {
            // Exactly equal — activate both (diagonal)
            result.insert(dy < 0 ? "Up" : "Down")
            result.insert(dx > 0 ? "Right" : "Left")
        }

        return result
    }

    private func angularDistance(_ a: Double, from target: Double) -> Double {
        var diff = abs(a - target)
        if diff > 180 { diff = 360 - diff }
        return diff
    }

    // MARK: - Touch handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        for touch in touches {
            let pointerId = touch.hashValue
            let location = touch.location(in: self)
            let directions = directionsForPoint(location)
            activeTouches[pointerId] = directions
            for dir in directions {
                onDirectionPress?(dir)
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        for touch in touches {
            let pointerId = touch.hashValue
            let location = touch.location(in: self)
            let newDirections = directionsForPoint(location)
            let oldDirections = activeTouches[pointerId] ?? []

            // Release directions no longer in zone
            for dir in oldDirections where !newDirections.contains(dir) {
                onDirectionRelease?(dir)
            }
            // Press new directions now in zone
            for dir in newDirections where !oldDirections.contains(dir) {
                onDirectionPress?(dir)
            }

            activeTouches[pointerId] = newDirections
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        for touch in touches {
            let pointerId = touch.hashValue
            if let directions = activeTouches.removeValue(forKey: pointerId) {
                for dir in directions {
                    onDirectionRelease?(dir)
                }
            }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        for touch in touches {
            let pointerId = touch.hashValue
            if let directions = activeTouches.removeValue(forKey: pointerId) {
                for dir in directions {
                    onDirectionRelease?(dir)
                }
            }
        }
    }

    // MARK: - Layout & drawing

    override func layoutSubviews() {
        super.layoutSubviews()
        buildLabelFrames()
        buildBackground()
        buildLabels()
    }

    private func buildBackground() {
        backgroundLayer?.removeFromSuperlayer()
        shapeLayers.forEach { $0.removeFromSuperlayer() }
        backgroundLayer = nil
        shapeLayers = []

        let barHalf = baseRadius * 0.36
        let cornerRadius: CGFloat = 8

        switch variant {
        case .cross:
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

            let borderLayer = CAShapeLayer()
            borderLayer.path = UIBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1)).cgPath
            borderLayer.strokeColor = UIColor.gray.withAlphaComponent(0.4).cgColor
            borderLayer.fillColor = nil
            borderLayer.lineWidth = 2
            layer.addSublayer(borderLayer)
            shapeLayers.append(borderLayer)

        case .split:
            break

        case .floating:
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

            let hub = CAShapeLayer()
            let hs = min(barHalf * 0.95, baseRadius * 0.22)
            hub.path = UIBezierPath(
                ovalIn: CGRect(x: (bounds.width - hs) / 2, y: (bounds.height - hs) / 2,
                               width: hs, height: hs)
            ).cgPath
            hub.fillColor = UIColor(red: 0.18, green: 0.18, blue: 0.21, alpha: 1.0).cgColor
            layer.addSublayer(hub)
            shapeLayers.append(hub)

        case .clicky:
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

            let hub = CAShapeLayer()
            let hs = min(barHalf * 0.95, baseRadius * 0.22)
            hub.path = UIBezierPath(
                ovalIn: CGRect(x: (bounds.width - hs) / 2, y: (bounds.height - hs) / 2,
                               width: hs, height: hs)
            ).cgPath
            hub.fillColor = UIColor(red: 0.18, green: 0.18, blue: 0.21, alpha: 1.0).cgColor
            layer.addSublayer(hub)
            shapeLayers.append(hub)

            let rim = CAShapeLayer()
            rim.path = UIBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), cornerRadius: 12).cgPath
            rim.strokeColor = UIColor.gray.withAlphaComponent(0.6).cgColor
            rim.fillColor = nil
            rim.lineWidth = 3
            layer.addSublayer(rim)
            shapeLayers.append(rim)

        case .pivot:
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

            let hub = CAShapeLayer()
            let hs = min(barHalf * 0.95, baseRadius * 0.22)
            hub.path = UIBezierPath(
                ovalIn: CGRect(x: (bounds.width - hs) / 2, y: (bounds.height - hs) / 2,
                               width: hs, height: hs)
            ).cgPath
            hub.fillColor = UIColor(red: 0.15, green: 0.15, blue: 0.18, alpha: 1.0).cgColor
            layer.addSublayer(hub)
            shapeLayers.append(hub)

            let hubBorder = CAShapeLayer()
            hubBorder.path = UIBezierPath(
                ovalIn: CGRect(x: (bounds.width - hs) / 2, y: (bounds.height - hs) / 2,
                               width: hs, height: hs).insetBy(dx: -1, dy: -1)
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

        let defaultIcons = ["Up": "▲", "Down": "▼", "Left": "◀", "Right": "▶"]
        let directions = ["Up", "Down", "Left", "Right"]

        for direction in directions {
            guard let frame = labelFrames[direction] else { continue }
            let label = UILabel()
            let labelText = directionLabels[direction] ?? defaultIcons[direction] ?? ""
            label.text = labelText
            label.accessibilityLabel = direction
            label.font = directionLabels[direction] != nil
                ? UIFont.systemFont(ofSize: 20, weight: .bold)
                : UIFont.systemFont(ofSize: 18, weight: .bold)
            label.textAlignment = .center
            label.textColor = UIColor.gray.withAlphaComponent(0.7)
            label.frame = frame
            label.isUserInteractionEnabled = false
            addSubview(label)
            labelLayers.append(label)
        }
    }

    func setPressedDirections(_ directions: Set<String>) {
        for label in labelLayers {
            let dir = label.accessibilityLabel ?? ""
            let isPressed = directions.contains(dir)
            label.textColor = isPressed ? .white : UIColor.gray.withAlphaComponent(0.7)
        }
    }
}

// MARK: - UIViewRepresentable wrapper

struct DPadViewRepresentable: UIViewRepresentable {
    let variant: DPadVariant
    let baseRadius: CGFloat
    let directionLabels: [String: String]
    let isEditMode: Bool
    @ObservedObject var buttonState: DPadButtonState
    var onDirection: ((String) -> Void)?
    var onDirectionUp: ((String) -> Void)?

    func makeUIView(context: Context) -> DPadUIView {
        let view = DPadUIView(
            variant: variant,
            baseRadius: baseRadius,
            directionLabels: directionLabels,
            isEditMode: isEditMode
        )
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
        uiView.isUserInteractionEnabled = !isEditMode
    }
}

// MARK: - DPadVariantView (dispatcher)

struct DPadVariantView: View {
    var variant: DPadVariant = .cross
    let baseRadius: CGFloat
    var directionLabels: [String: String] = [:]
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
                directionLabels: directionLabels,
                isEditMode: isEditMode,
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
