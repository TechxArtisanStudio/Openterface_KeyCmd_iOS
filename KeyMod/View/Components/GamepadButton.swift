//
//  GamepadButton.swift
//  KeyMod
//
//  Multi-touch buttons with retro metallic styling matching Android.
//  Each button tracks its own touches via UITouch.hashValue (pointerID),
//  supporting multi-finger presses across the canvas.
//
//  Face styles: A/B/X/Y get distinct pastel colors (matching Android);
//  generic labels get muted cool tones. Custom module accent blends in.
//  Visual layers: drop shadow → gradient body → rim stroke → gloss highlight.
//

import SwiftUI
import UIKit

// MARK: - Face Style Colors (matches Android GamepadView.FaceStyle)

struct FaceStyle {
    let body: UIColor
    let rim: UIColor
    let label: UIColor
    let highlight: UIColor   // pressed accent ring

    static func forLabel(_ label: String) -> FaceStyle {
        let t = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = t.lowercased()

        switch lower {
        case "a": return Self.aStyle
        case "b": return Self.bStyle
        case "x": return Self.xStyle
        case "y": return Self.yStyle
        case "k", "kb", "kill": return FaceStyle(
            body: UIColor(red: 0.42, green: 0.50, blue: 0.58, alpha: 1),
            rim: UIColor(red: 0.25, green: 0.31, blue: 0.38, alpha: 1),
            label: .white,
            highlight: UIColor(red: 0.20, green: 0.60, blue: 0.80, alpha: 1))
        case "s", "start", "select": return FaceStyle(
            body: UIColor(red: 0.42, green: 0.50, blue: 0.58, alpha: 1),
            rim: UIColor(red: 0.25, green: 0.31, blue: 0.38, alpha: 1),
            label: .white,
            highlight: UIColor(red: 0.30, green: 0.60, blue: 0.40, alpha: 1))
        case "h", "hs": return FaceStyle(
            body: UIColor(red: 0.52, green: 0.48, blue: 0.55, alpha: 1),
            rim: UIColor(red: 0.32, green: 0.29, blue: 0.35, alpha: 1),
            label: .white,
            highlight: UIColor(red: 0.60, green: 0.30, blue: 0.60, alpha: 1))
        case "p": return FaceStyle(
            body: UIColor(red: 0.50, green: 0.47, blue: 0.53, alpha: 1),
            rim: UIColor(red: 0.30, green: 0.27, blue: 0.33, alpha: 1),
            label: .white,
            highlight: UIColor(red: 0.70, green: 0.30, blue: 0.30, alpha: 1))
        case "d": return FaceStyle(
            body: UIColor(red: 0.45, green: 0.55, blue: 0.65, alpha: 1),
            rim: UIColor(red: 0.27, green: 0.34, blue: 0.41, alpha: 1),
            label: .white,
            highlight: UIColor(red: 0.25, green: 0.55, blue: 0.85, alpha: 1))
        case "rc", "rec", "record": return FaceStyle(
            body: UIColor(red: 0.58, green: 0.45, blue: 0.45, alpha: 1),
            rim: UIColor(red: 0.36, green: 0.27, blue: 0.27, alpha: 1),
            label: .white,
            highlight: UIColor(red: 0.85, green: 0.25, blue: 0.25, alpha: 1))
        default:
            // Hash-based cycle through muted cool tones (matches Android FACE_EXTRA_CYCLE)
            let h = abs(t.hashValue) % 4
            let extras: [FaceStyle] = [
                FaceStyle(
                    body: UIColor(red: 0.36, green: 0.42, blue: 0.47, alpha: 1),
                    rim: UIColor(red: 0.23, green: 0.27, blue: 0.31, alpha: 1),
                    label: .white,
                    highlight: .systemTeal),
                FaceStyle(
                    body: UIColor(red: 0.42, green: 0.36, blue: 0.43, alpha: 1),
                    rim: UIColor(red: 0.27, green: 0.24, blue: 0.29, alpha: 1),
                    label: .white,
                    highlight: .systemPurple),
                FaceStyle(
                    body: UIColor(red: 0.36, green: 0.41, blue: 0.40, alpha: 1),
                    rim: UIColor(red: 0.23, green: 0.27, blue: 0.26, alpha: 1),
                    label: .white,
                    highlight: .systemGreen),
                FaceStyle(
                    body: UIColor(red: 0.41, green: 0.38, blue: 0.46, alpha: 1),
                    rim: UIColor(red: 0.27, green: 0.24, blue: 0.30, alpha: 1),
                    label: .white,
                    highlight: .systemIndigo),
            ]
            return extras[h]
        }
    }

    // Xbox face buttons
    private static let aStyle = FaceStyle(
        body: UIColor(red: 0.65, green: 0.89, blue: 0.71, alpha: 1),
        rim: UIColor(red: 0.37, green: 0.71, blue: 0.48, alpha: 1),
        label: UIColor(red: 0.12, green: 0.30, blue: 0.17, alpha: 1),
        highlight: UIColor(red: 0.20, green: 0.70, blue: 0.35, alpha: 1))
    private static let bStyle = FaceStyle(
        body: UIColor(red: 0.97, green: 0.70, blue: 0.71, alpha: 1),
        rim: UIColor(red: 0.85, green: 0.44, blue: 0.47, alpha: 1),
        label: UIColor(red: 0.35, green: 0.11, blue: 0.13, alpha: 1),
        highlight: UIColor(red: 0.90, green: 0.30, blue: 0.30, alpha: 1))
    private static let xStyle = FaceStyle(
        body: UIColor(red: 0.66, green: 0.80, blue: 0.92, alpha: 1),
        rim: UIColor(red: 0.31, green: 0.53, blue: 0.78, alpha: 1),
        label: UIColor(red: 0.08, green: 0.18, blue: 0.31, alpha: 1),
        highlight: UIColor(red: 0.25, green: 0.55, blue: 0.90, alpha: 1))
    private static let yStyle = FaceStyle(
        body: UIColor(red: 0.97, green: 0.91, blue: 0.62, alpha: 1),
        rim: UIColor(red: 0.79, green: 0.65, blue: 0.25, alpha: 1),
        label: UIColor(red: 0.30, green: 0.23, blue: 0.02, alpha: 1),
        highlight: UIColor(red: 0.95, green: 0.75, blue: 0.15, alpha: 1))
}

// MARK: - Shared button appearance renderer

private class ButtonAppearance {
    let shadowLayer: CALayer
    let bodyGradient: CAGradientLayer
    let glossLayer: CAGradientLayer
    let rimLayer: CAShapeLayer
    let accentRingLayer: CAShapeLayer
    let labelLayer: UILabel

    let cornerRadiusNorm: Double
    private var currentStyle: FaceStyle?
    private var isPressedState = false
    private var customAccent: UIColor?

    init(cornerRadiusNorm: Double = 1.0, label: String, customAccent: UIColor? = nil) {
        self.cornerRadiusNorm = cornerRadiusNorm
        self.customAccent = customAccent

        // Shadow layer
        shadowLayer = CALayer()
        shadowLayer.shadowOpacity = 0.25
        shadowLayer.shadowOffset = CGSize(width: 0, height: 2)
        shadowLayer.shadowRadius = 4

        // Body gradient
        bodyGradient = CAGradientLayer()
        bodyGradient.startPoint = CGPoint(x: 0.5, y: 0)
        bodyGradient.endPoint = CGPoint(x: 0.5, y: 1)

        // Gloss (top-left specular highlight)
        glossLayer = CAGradientLayer()
        glossLayer.type = .radial
        glossLayer.startPoint = CGPoint(x: 0.3, y: 0.3)
        glossLayer.endPoint = CGPoint(x: 0.5, y: 0.5)

        // Rim stroke
        rimLayer = CAShapeLayer()
        rimLayer.fillColor = nil
        rimLayer.lineWidth = 1.5

        // Accent ring (visible when pressed)
        accentRingLayer = CAShapeLayer()
        accentRingLayer.fillColor = nil
        accentRingLayer.lineWidth = 2.5
        accentRingLayer.opacity = 0

        // Label
        labelLayer = UILabel()
        labelLayer.textAlignment = .center
        labelLayer.isUserInteractionEnabled = false

        currentStyle = FaceStyle.forLabel(label)
        if let accent = customAccent {
            currentStyle = blendStyleWithAccent(currentStyle!, accent: accent)
        }
    }

    func addToLayer(_ parent: CALayer, labelSuperview: UIView) {
        parent.insertSublayer(shadowLayer, at: 0)
        parent.insertSublayer(bodyGradient, at: 1)
        parent.insertSublayer(rimLayer, at: 2)
        parent.insertSublayer(glossLayer, at: 3)
        parent.insertSublayer(accentRingLayer, at: 4)
        labelSuperview.addSubview(labelLayer)
    }

    func layout(in bounds: CGRect) {
        let radius = min(bounds.width, bounds.height) / 2 * CGFloat(cornerRadiusNorm)
        let path = UIBezierPath(roundedRect: bounds, cornerRadius: radius).cgPath

        // Shadow
        shadowLayer.frame = bounds
        shadowLayer.shadowPath = path
        shadowLayer.cornerRadius = radius

        // Body gradient
        bodyGradient.frame = bounds
        bodyGradient.cornerRadius = radius

        // Gloss
        glossLayer.frame = bounds
        glossLayer.cornerRadius = radius

        // Rim
        rimLayer.frame = bounds
        rimLayer.path = path
        rimLayer.cornerRadius = radius

        // Accent ring (slightly larger)
        let insetBounds = bounds.insetBy(dx: -1.5, dy: -1.5)
        let ringRadius = min(insetBounds.width, insetBounds.height) / 2 * CGFloat(cornerRadiusNorm)
        let ringPath = UIBezierPath(roundedRect: insetBounds, cornerRadius: max(ringRadius, radius)).cgPath
        accentRingLayer.frame = insetBounds
        accentRingLayer.path = ringPath
        accentRingLayer.cornerRadius = max(ringRadius, radius)

        // Label
        labelLayer.frame = bounds
        labelLayer.font = UIFont.systemFont(ofSize: min(bounds.width, bounds.height) * 0.35, weight: .bold)
    }

    func updateAppearance(pressed: Bool, style: FaceStyle? = nil, customAccent: UIColor? = nil) {
        var activeStyle = style ?? self.currentStyle ?? FaceStyle.forLabel(labelLayer.text ?? "")
        if let accent = customAccent ?? self.customAccent {
            activeStyle = blendStyleWithAccent(activeStyle, accent: accent)
        }

        let darker = darken(activeStyle.body, factor: pressed ? 0.88 : 1.0)
        let darkerRim = darken(activeStyle.rim, factor: pressed ? 0.92 : 1.0)

        bodyGradient.colors = [
            lighten(darker, amount: 0.06).cgColor,
            darkerRim.cgColor
        ]

        rimLayer.strokeColor = UIColor.black.withAlphaComponent(pressed ? 0.25 : 0.18).cgColor

        glossLayer.colors = [
            UIColor.white.withAlphaComponent(0.15).cgColor,
            UIColor.white.withAlphaComponent(0.0).cgColor
        ]

        // Accent ring on press
        let ringColor = activeStyle.highlight.withAlphaComponent(0.7)
        accentRingLayer.strokeColor = ringColor.cgColor
        accentRingLayer.opacity = pressed ? 0.85 : 0

        labelLayer.textColor = activeStyle.label
    }

    private func blendStyleWithAccent(_ style: FaceStyle, accent: UIColor) -> FaceStyle {
        let blendedBody = blend(style.body, with: accent, fraction: 0.45)
        let blendedRim = blend(style.rim, with: accent, fraction: 0.5)
        return FaceStyle(
            body: blendedBody,
            rim: blendedRim,
            label: isLightColor(blendedBody) ? UIColor(red: 0.10, green: 0.11, blue: 0.13, alpha: 1) : .white,
            highlight: accent)
    }

    // MARK: - Color helpers

    private func darken(_ color: UIColor, factor: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: r * factor, green: g * factor, blue: b * factor, alpha: a)
    }

    private func lighten(_ color: UIColor, amount: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(
            red: min(1, r + amount),
            green: min(1, g + amount),
            blue: min(1, b + amount),
            alpha: a)
    }

    private func blend(_ c1: UIColor, with c2: UIColor, fraction: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        c1.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        c2.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(
            red: r1 * (1 - fraction) + r2 * fraction,
            green: g1 * (1 - fraction) + g2 * fraction,
            blue: b1 * (1 - fraction) + b2 * fraction,
            alpha: (a1 + a2) / 2)
    }

    private func isLightColor(_ color: UIColor) -> Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: nil)
        return r * 0.299 + g * 0.587 + b * 0.114 > 0.6
    }
}

// MARK: - Base shared button view

class GamepadButtonViewBase: UIView {
    private var appearance: ButtonAppearance!
    private var customAccent: UIColor?

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onDrag: ((CGSize) -> Void)?

    var isPressed: Bool = false {
        didSet { appearance.updateAppearance(pressed: isPressed, customAccent: customAccent) }
    }

    var cornerRadiusNorm: Double {
        appearance.cornerRadiusNorm
    }

    var label: String {
        get { appearance.labelLayer.text ?? "" }
        set {
            appearance.labelLayer.text = newValue
            appearance.updateAppearance(pressed: isPressed, customAccent: customAccent)
        }
    }

    init(cornerRadiusNorm: Double, label: String, customAccent: UIColor? = nil) {
        self.customAccent = customAccent
        super.init(frame: .zero)
        isUserInteractionEnabled = true
        isMultipleTouchEnabled = true
        backgroundColor = .clear

        appearance = ButtonAppearance(cornerRadiusNorm: cornerRadiusNorm, label: label, customAccent: customAccent)
        appearance.addToLayer(layer, labelSuperview: self)
        appearance.labelLayer.text = label
    }

    // Settings button exclusion zone: top-right corner, ~28pt square
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

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        appearance.layout(in: bounds)
        appearance.updateAppearance(pressed: isPressed, customAccent: customAccent)
    }

    func setCustomAccent(_ accent: UIColor?) {
        customAccent = accent
        appearance.updateAppearance(pressed: isPressed, customAccent: accent)
    }
}

// MARK: - Simple Button (press/release only)

class MultiTouchButtonView: GamepadButtonViewBase {
    private var activePointerIds: Set<Int> = []

    override init(cornerRadiusNorm: Double, label: String, customAccent: UIColor? = nil) {
        super.init(cornerRadiusNorm: cornerRadiusNorm, label: label, customAccent: customAccent)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        for touch in touches {
            let pointerId = touch.hashValue
            let location = touch.location(in: self)
            guard bounds.contains(location) else { continue }
            activePointerIds.insert(pointerId)
            if activePointerIds.count == 1 {
                isPressed = true
                onPress?()
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        for touch in touches {
            let pointerId = touch.hashValue
            let location = touch.location(in: self)
            if !bounds.contains(location) {
                activePointerIds.remove(pointerId)
            }
        }
        let wasPressed = isPressed
        isPressed = !activePointerIds.isEmpty
        if wasPressed && !isPressed {
            onRelease?()
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        for touch in touches {
            activePointerIds.remove(touch.hashValue)
        }
        let wasPressed = isPressed
        isPressed = !activePointerIds.isEmpty
        if wasPressed {
            onRelease?()
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        for touch in touches {
            activePointerIds.remove(touch.hashValue)
        }
        let wasPressed = isPressed
        isPressed = !activePointerIds.isEmpty
        if wasPressed {
            onRelease?()
        }
    }
}

// MARK: - Drag-Tracking Button (for gesture lock modules)

class DragTrackingButtonView: GamepadButtonViewBase {
    private var activePointerIds: Set<Int> = []
    private var initialTouchLocation: CGPoint?

    override init(cornerRadiusNorm: Double, label: String, customAccent: UIColor? = nil) {
        super.init(cornerRadiusNorm: cornerRadiusNorm, label: label, customAccent: customAccent)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        for touch in touches {
            let pointerId = touch.hashValue
            let location = touch.location(in: self)
            guard bounds.contains(location) else { continue }
            activePointerIds.insert(pointerId)
            if initialTouchLocation == nil {
                initialTouchLocation = location
            }
            if activePointerIds.count == 1 {
                isPressed = true
                onPress?()
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        for touch in touches {
            let pointerId = touch.hashValue
            let location = touch.location(in: self)
            if !bounds.contains(location) {
                activePointerIds.remove(pointerId)
            }
        }
        if let initial = initialTouchLocation, let latestTouch = touches.first {
            let currentLocation = latestTouch.location(in: self)
            let translation = CGSize(
                width: currentLocation.x - initial.x,
                height: currentLocation.y - initial.y
            )
            onDrag?(translation)
        }
        let wasPressed = isPressed
        isPressed = !activePointerIds.isEmpty
        if wasPressed && !isPressed {
            onRelease?()
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        for touch in touches {
            activePointerIds.remove(touch.hashValue)
        }
        let wasPressed = isPressed
        if let initial = initialTouchLocation, let touch = touches.first {
            let location = touch.location(in: self)
            let translation = CGSize(
                width: location.x - initial.x,
                height: location.y - initial.y
            )
            onDrag?(translation)
        }
        isPressed = !activePointerIds.isEmpty
        if wasPressed {
            onRelease?()
        }
        if activePointerIds.isEmpty {
            initialTouchLocation = nil
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        for touch in touches {
            activePointerIds.remove(touch.hashValue)
        }
        let wasPressed = isPressed
        isPressed = !activePointerIds.isEmpty
        if wasPressed {
            onRelease?()
        }
        if activePointerIds.isEmpty {
            initialTouchLocation = nil
        }
    }
}

// MARK: - UIViewRepresentable: Simple Button

struct MultiTouchButton: UIViewRepresentable {
    let label: String
    let normalColor: UIColor
    let pressedColor: UIColor
    let cornerRadiusNorm: Double
    let borderColor: UIColor
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    init(
        label: String,
        normalColor: UIColor = .systemBlue,
        pressedColor: UIColor = .systemGray,
        cornerRadiusNorm: Double = 1.0,
        borderColor: UIColor = .clear,
        onPress: (() -> Void)? = nil,
        onRelease: (() -> Void)? = nil
    ) {
        self.label = label
        self.normalColor = normalColor
        self.pressedColor = pressedColor
        self.cornerRadiusNorm = cornerRadiusNorm
        self.borderColor = borderColor
        self.onPress = onPress
        self.onRelease = onRelease
    }

    func makeUIView(context: Context) -> MultiTouchButtonView {
        let view = MultiTouchButtonView(
            cornerRadiusNorm: cornerRadiusNorm,
            label: label,
            customAccent: normalColor != .systemBlue ? normalColor : nil
        )
        view.onPress = { self.onPress?() }
        view.onRelease = { self.onRelease?() }
        return view
    }

    func updateUIView(_ uiView: MultiTouchButtonView, context: Context) {
        // Appearance updates handled internally
    }
}

// MARK: - UIViewRepresentable: Drag-Tracking Button

struct MultiTouchDragButton: UIViewRepresentable {
    let label: String
    let normalColor: UIColor
    let pressedColor: UIColor
    let cornerRadiusNorm: Double
    let borderColor: UIColor
    var onPress: (() -> Void)?
    var onDrag: ((CGSize) -> Void)?
    var onRelease: (() -> Void)?

    init(
        label: String,
        normalColor: UIColor = .systemBlue,
        pressedColor: UIColor = .systemGray,
        cornerRadiusNorm: Double = 1.0,
        borderColor: UIColor = .clear,
        onPress: (() -> Void)? = nil,
        onDrag: ((CGSize) -> Void)? = nil,
        onRelease: (() -> Void)? = nil
    ) {
        self.label = label
        self.normalColor = normalColor
        self.pressedColor = pressedColor
        self.cornerRadiusNorm = cornerRadiusNorm
        self.borderColor = borderColor
        self.onPress = onPress
        self.onDrag = onDrag
        self.onRelease = onRelease
    }

    func makeUIView(context: Context) -> DragTrackingButtonView {
        // Pass accent color as custom accent so face styles blend with module accent
        let accent = normalColor != .systemBlue ? normalColor : nil
        let view = DragTrackingButtonView(
            cornerRadiusNorm: cornerRadiusNorm,
            label: label,
            customAccent: accent
        )
        view.onPress = { self.onPress?() }
        view.onDrag = { translation in self.onDrag?(translation) }
        view.onRelease = { self.onRelease?() }
        return view
    }

    func updateUIView(_ uiView: DragTrackingButtonView, context: Context) {
        // Appearance updates handled internally
    }
}

// MARK: - SwiftUI GamepadButton wrapper (legacy-compatible interface)

struct GamepadButton: View {
    let label: String
    let action: () -> Void
    let actionUp: (() -> Void)?
    let onLongPress: (() -> Void)?
    let isEditMode: Bool
    let isKeyMappingMode: Bool
    let width: CGFloat

    @State private var isPressed = false
    @StateObject private var hapticManager = HapticFeedbackManager.shared

    init(label: String, action: @escaping () -> Void, actionUp: (() -> Void)? = nil, onLongPress: (() -> Void)? = nil, isEditMode: Bool = false, isKeyMappingMode: Bool = false, width: CGFloat = 50) {
        self.label = label
        self.action = action
        self.actionUp = actionUp
        self.onLongPress = onLongPress
        self.isEditMode = isEditMode
        self.isKeyMappingMode = isKeyMappingMode
        self.width = width
    }

    var body: some View {
        MultiTouchDragButton(
            label: label,
            normalColor: .systemBlue,
            pressedColor: .systemGray,
            cornerRadiusNorm: 0.23,
            borderColor: isEditMode ? .orange : .clear,
            onPress: {
                if !isKeyMappingMode && !isPressed {
                    isPressed = true
                    hapticManager.triggerButtonPress()
                    action()
                }
            },
            onRelease: {
                if !isKeyMappingMode {
                    isPressed = false
                    actionUp?()
                }
            }
        )
        .frame(width: width, height: 35)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .onTapGesture {
            if isKeyMappingMode {
                print("🔧 Tap detected on button: \(label)")
                onLongPress?()
            }
        }
    }
}
