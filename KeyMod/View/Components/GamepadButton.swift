//
//  GamepadButton.swift
//  KeyMod
//
//  Multi-touch buttons using a single UIView per button — each button tracks
//  its own touches via UITouch.hashValue (pointerID), so multiple fingers can
//  press multiple buttons simultaneously across the canvas.
//
//  Unlike SwiftUI's simultaneousGesture which competes across sibling views,
//  UIKit's touchesBegan/Moved/Ended/Cancelled natively supports per-touch
//  tracking within a single responder.
//
//  Corner radius uses `cornerRadiusNorm` (0.0–1.0) matching Android:
//  actual cornerRadius = min(width, height) / 2 * cornerRadiusNorm.
//  When cornerRadiusNorm = 1.0, the button is a perfect circle.
//

import SwiftUI
import UIKit

// MARK: - UIKit Simple Button View (press/release only)

class MultiTouchButtonView: UIView {

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var activePointerIds: Set<Int> = []

    // Visual styling — cornerRadiusNorm is 0.0–1.0, actual radius computed in layoutSubviews
    let cornerRadiusNorm: Double
    var isPressed: Bool = false {
        didSet { updateAppearance() }
    }
    let label: String
    let normalColor: UIColor
    let pressedColor: UIColor
    let borderColor: UIColor

    private var labelLayer: UILabel?
    private var backgroundLayer: CALayer?
    private var borderLayer: CALayer?

    init(
        cornerRadiusNorm: Double = 1.0,
        label: String,
        normalColor: UIColor = .systemBlue,
        pressedColor: UIColor = .systemGray,
        borderColor: UIColor = .clear
    ) {
        self.cornerRadiusNorm = cornerRadiusNorm
        self.label = label
        self.normalColor = normalColor
        self.pressedColor = pressedColor
        self.borderColor = borderColor
        super.init(frame: .zero)
        isUserInteractionEnabled = true
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        buildAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildAppearance() {
        let bg = CALayer()
        bg.masksToBounds = true
        layer.insertSublayer(bg, at: 0)
        backgroundLayer = bg

        if borderColor != .clear {
            let border = CALayer()
            border.borderWidth = 2
            layer.insertSublayer(border, at: 1)
            borderLayer = border
        }

        let lbl = UILabel()
        lbl.textAlignment = .center
        lbl.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        lbl.textColor = .white
        lbl.isUserInteractionEnabled = false
        addSubview(lbl)
        labelLayer = lbl

        updateAppearance()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let radius = min(bounds.width, bounds.height) / 2 * CGFloat(cornerRadiusNorm)
        backgroundLayer?.frame = bounds
        backgroundLayer?.cornerRadius = radius
        labelLayer?.frame = bounds
        if let border = borderLayer {
            border.frame = bounds
            border.cornerRadius = radius
            border.borderColor = borderColor.cgColor
        }
    }

    private func updateAppearance() {
        backgroundLayer?.backgroundColor = isPressed ? pressedColor.cgColor : normalColor.cgColor
    }

    // MARK: - Touch handling

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

// MARK: - UIKit Drag-Tracking Button View (for gesture lock modules)

class DragTrackingButtonView: UIView {

    var onPress: (() -> Void)?
    var onDrag: ((CGSize) -> Void)?
    var onRelease: (() -> Void)?

    private var activePointerIds: Set<Int> = []
    private var initialTouchLocation: CGPoint?

    // Visual styling — cornerRadiusNorm is 0.0–1.0, actual radius computed in layoutSubviews
    let cornerRadiusNorm: Double
    var isPressed: Bool = false {
        didSet { updateAppearance() }
    }
    let label: String
    let normalColor: UIColor
    let pressedColor: UIColor
    let borderColor: UIColor

    private var labelLayer: UILabel?
    private var backgroundLayer: CALayer?
    private var borderLayer: CALayer?

    init(
        cornerRadiusNorm: Double = 1.0,
        label: String,
        normalColor: UIColor = .systemBlue,
        pressedColor: UIColor = .systemGray,
        borderColor: UIColor = .clear
    ) {
        self.cornerRadiusNorm = cornerRadiusNorm
        self.label = label
        self.normalColor = normalColor
        self.pressedColor = pressedColor
        self.borderColor = borderColor
        super.init(frame: .zero)
        isUserInteractionEnabled = true
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        buildAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildAppearance() {
        let bg = CALayer()
        bg.masksToBounds = true
        layer.insertSublayer(bg, at: 0)
        backgroundLayer = bg

        if borderColor != .clear {
            let border = CALayer()
            border.borderWidth = 2
            layer.insertSublayer(border, at: 1)
            borderLayer = border
        }

        let lbl = UILabel()
        lbl.textAlignment = .center
        lbl.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        lbl.textColor = .white
        lbl.isUserInteractionEnabled = false
        addSubview(lbl)
        labelLayer = lbl

        updateAppearance()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let radius = min(bounds.width, bounds.height) / 2 * CGFloat(cornerRadiusNorm)
        backgroundLayer?.frame = bounds
        backgroundLayer?.cornerRadius = radius
        labelLayer?.frame = bounds
        if let border = borderLayer {
            border.frame = bounds
            border.cornerRadius = radius
            border.borderColor = borderColor.cgColor
        }
    }

    private func updateAppearance() {
        backgroundLayer?.backgroundColor = isPressed ? pressedColor.cgColor : normalColor.cgColor
    }

    // MARK: - Touch handling

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
            normalColor: normalColor,
            pressedColor: pressedColor,
            borderColor: borderColor
        )
        view.onPress = { self.onPress?() }
        view.onRelease = { self.onRelease?() }
        return view
    }

    func updateUIView(_ uiView: MultiTouchButtonView, context: Context) {
        // Appearance updates handled via @Binding in coordinator if needed
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
        let view = DragTrackingButtonView(
            cornerRadiusNorm: cornerRadiusNorm,
            label: label,
            normalColor: normalColor,
            pressedColor: pressedColor,
            borderColor: borderColor
        )
        view.onPress = { self.onPress?() }
        view.onDrag = { translation in self.onDrag?(translation) }
        view.onRelease = { self.onRelease?() }
        return view
    }

    func updateUIView(_ uiView: DragTrackingButtonView, context: Context) {
        // Appearance updates handled via @Binding in coordinator if needed
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
        MultiTouchButton(
            label: label,
            normalColor: .systemBlue,
            pressedColor: .systemGray,
            cornerRadiusNorm: 0.23,  // 8 / 35 ≈ 0.23 for non-round buttons
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
