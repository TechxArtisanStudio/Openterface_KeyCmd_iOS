//
//  DPadVariantView.swift
//  KeyMod
//
//  D-pad with 6 visual variants: cross, disc, split, floating, clicky, pivot.
//  All variants produce identical directional key events.
//
//  Gesture model: single DragGesture(minimumDistance: 0) over the entire D-pad area.
//  Direction is determined by finger position relative to center. Moving the finger
//  from one direction to another releases the old direction and presses the new one,
//  matching Android's hit-test-rect-by-position behavior.
//

import SwiftUI

// MARK: - Direction Detection

/// Determine which D-pad direction is active based on touch position relative to center.
/// Uses rectangular quadrant logic matching Android's RectF.contains hit testing.
func dPadDirection(at location: CGPoint, center: CGPoint) -> String? {
    let dx = location.x - center.x
    let dy = location.y - center.y

    // Dead zone: if near center (within ~10% of radius), no direction
    let deadZone: CGFloat = 0.1
    if abs(dx) < deadZone && abs(dy) < deadZone {
        return nil
    }

    // Determine dominant axis and direction
    if abs(dx) > abs(dy) {
        return dx > 0 ? "Right" : "Left"
    } else {
        return dy > 0 ? "Down" : "Up"
    }
}

// MARK: - Shared State (drives both gesture handling and visual feedback)

class DPadTouchState: ObservableObject {
    @Published var pressedDirection: String?
    var onDirection: ((String) -> Void)?
    var onDirectionUp: ((String) -> Void)?
    var centerPoint: CGPoint = .zero
    private let hapticManager = HapticFeedbackManager.shared

    func handleTouch(at location: CGPoint) {
        let newDir = dPadDirection(at: location, center: centerPoint)

        if newDir != pressedDirection {
            // Release old direction
            if let old = pressedDirection {
                onDirectionUp?(old)
            }
            // Press new direction
            if let dir = newDir {
                hapticManager.triggerButtonPress()
                onDirection?(dir)
            }
            pressedDirection = newDir
        }
    }

    func handleRelease() {
        if let dir = pressedDirection {
            onDirectionUp?(dir)
        }
        pressedDirection = nil
    }
}

// MARK: - Visual D-Pad Button (no gestures, driven by pressedVisual binding)

struct DPadVisualButton: View {
    let icon: String
    let direction: String
    let isPressed: Bool

    var body: some View {
        ZStack {
            Image(systemName: icon)
                .foregroundColor(isPressed ? .white : .gray.opacity(0.7))
                .font(.system(size: 16, weight: .bold))
        }
        .background(isPressed ? Color.blue.opacity(0.5) : Color.black.opacity(0.3))
        .cornerRadius(6)
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

    @StateObject private var touchState = DPadTouchState()

    var body: some View {
        Group {
            switch variant {
            case .cross:
                CrossDPadContent(baseRadius: baseRadius, touchState: touchState)
            case .disc:
                DiscDPadContent(baseRadius: baseRadius, touchState: touchState)
            case .split:
                SplitDPadContent(baseRadius: baseRadius, touchState: touchState)
            case .floating:
                FloatingDPadContent(baseRadius: baseRadius, touchState: touchState)
            case .clicky:
                ClickyDPadContent(baseRadius: baseRadius, touchState: touchState)
            case .pivot:
                PivotDPadContent(baseRadius: baseRadius, touchState: touchState)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isEditMode ? Color.orange : Color.clear, lineWidth: 3)
        )
        .onAppear {
            touchState.onDirection = onDirection
            touchState.onDirectionUp = onDirectionUp
        }
    }
}

// MARK: - Cross Variant

struct CrossDPadContent: View {
    let baseRadius: CGFloat
    @ObservedObject var touchState: DPadTouchState

    var body: some View {
        let barHalf = baseRadius * 0.36
        let cornerRadius: CGFloat = 8
        let btnSize = baseRadius * 0.5

        contentLayout(barHalf: barHalf, cornerRadius: cornerRadius, btnSize: btnSize)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if touchState.centerPoint == .zero {
                            touchState.centerPoint = CGPoint(
                                x: value.location.x - value.translation.width,
                                y: value.location.y - value.translation.height
                            )
                        }
                        touchState.handleTouch(at: value.location)
                    }
                    .onEnded { _ in
                        touchState.handleRelease()
                    }
            )
    }

    @ViewBuilder
    private func contentLayout(barHalf: CGFloat, cornerRadius: CGFloat, btnSize: CGFloat) -> some View {
        let totalWidth = baseRadius * 2
        let totalHeight = baseRadius * 2

        VStack(spacing: 0) {
            DPadVisualButton(
                icon: "arrowtriangle.up.fill", direction: "Up",
                isPressed: touchState.pressedDirection == "Up"
            )
            .frame(width: btnSize, height: btnSize)

            HStack(spacing: 0) {
                DPadVisualButton(
                    icon: "arrowtriangle.left.fill", direction: "Left",
                    isPressed: touchState.pressedDirection == "Left"
                )
                .frame(width: btnSize, height: btnSize)

                Spacer().frame(width: baseRadius * 0.65)

                DPadVisualButton(
                    icon: "arrowtriangle.right.fill", direction: "Right",
                    isPressed: touchState.pressedDirection == "Right"
                )
                .frame(width: btnSize, height: btnSize)
            }

            DPadVisualButton(
                icon: "arrowtriangle.down.fill", direction: "Down",
                isPressed: touchState.pressedDirection == "Down"
            )
            .frame(width: btnSize, height: btnSize)
        }
        .frame(width: totalWidth, height: totalHeight)
        .background(
            GeometryReader { geo in
                Color.clear
                    .preference(key: DPadCenterKey.self, value: CGPoint(x: geo.size.width / 2, y: geo.size.height / 2))
            }
        )
        .background(
            ZStack {
                Rectangle()
                    .fill(Color(red: 0.22, green: 0.22, blue: 0.25))
                    .frame(width: barHalf * 2, height: baseRadius * 2)
                    .cornerRadius(cornerRadius)
                Rectangle()
                    .fill(Color(red: 0.22, green: 0.22, blue: 0.25))
                    .frame(width: baseRadius * 2, height: barHalf * 2)
                    .cornerRadius(cornerRadius)
                let hubSize = min(barHalf * 0.95, baseRadius * 0.22)
                Circle()
                    .fill(Color(red: 0.18, green: 0.18, blue: 0.21))
                    .frame(width: hubSize, height: hubSize)
            }
        )
        .onPreferenceChange(DPadCenterKey.self) { center in
            touchState.centerPoint = center
        }
        .gesture(dpadDragGesture)
    }

    private var dpadDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                touchState.handleTouch(at: value.location)
            }
            .onEnded { _ in
                touchState.handleRelease()
            }
    }
}

// Preference key for D-pad center
struct DPadCenterKey: PreferenceKey {
    static var defaultValue: CGPoint = .zero
    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) {
        value = nextValue()
    }
}

// MARK: - Disc Variant

struct DiscDPadContent: View {
    let baseRadius: CGFloat
    @ObservedObject var touchState: DPadTouchState

    var body: some View {
        contentLayout(btnSize: baseRadius * 0.67)
    }

    @ViewBuilder
    private func contentLayout(btnSize: CGFloat) -> some View {
        let totalSize = baseRadius * 2

        VStack(spacing: 0) {
            DPadVisualButton(
                icon: "arrowtriangle.up.fill", direction: "Up",
                isPressed: touchState.pressedDirection == "Up"
            )
            .frame(width: btnSize, height: btnSize)

            HStack(spacing: 0) {
                DPadVisualButton(
                    icon: "arrowtriangle.left.fill", direction: "Left",
                    isPressed: touchState.pressedDirection == "Left"
                )
                .frame(width: btnSize, height: btnSize)

                Spacer().frame(width: baseRadius * 0.67)

                DPadVisualButton(
                    icon: "arrowtriangle.right.fill", direction: "Right",
                    isPressed: touchState.pressedDirection == "Right"
                )
                .frame(width: btnSize, height: btnSize)
            }

            DPadVisualButton(
                icon: "arrowtriangle.down.fill", direction: "Down",
                isPressed: touchState.pressedDirection == "Down"
            )
            .frame(width: btnSize, height: btnSize)
        }
        .frame(width: totalSize, height: totalSize)
        .background(
            GeometryReader { geo in
                Color.clear
                    .preference(key: DPadCenterKey.self, value: CGPoint(x: geo.size.width / 2, y: geo.size.height / 2))
            }
        )
        .background(
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(red: 0.25, green: 0.25, blue: 0.28),
                                     Color(red: 0.15, green: 0.15, blue: 0.18)],
                            center: .center,
                            startRadius: 0,
                            endRadius: baseRadius
                        )
                    )
                    .overlay(
                        Circle().stroke(Color.gray.opacity(0.4), lineWidth: 2)
                    )
            }
        )
        .onPreferenceChange(DPadCenterKey.self) { center in
            touchState.centerPoint = center
        }
        .gesture(dpadDragGesture)
    }

    private var dpadDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                touchState.handleTouch(at: value.location)
            }
            .onEnded { _ in
                touchState.handleRelease()
            }
    }
}

// MARK: - Split Variant

struct SplitDPadContent: View {
    let baseRadius: CGFloat
    @ObservedObject var touchState: DPadTouchState

    private var gap: CGFloat { baseRadius * 0.08 }

    var body: some View {
        contentLayout
    }

    private var contentLayout: some View {
        VStack(spacing: gap) {
            DPadVisualButton(
                icon: "arrowtriangle.up.fill", direction: "Up",
                isPressed: touchState.pressedDirection == "Up"
            )
            .frame(width: baseRadius * 0.8, height: baseRadius * 0.67)

            HStack(spacing: gap) {
                DPadVisualButton(
                    icon: "arrowtriangle.left.fill", direction: "Left",
                    isPressed: touchState.pressedDirection == "Left"
                )
                .frame(width: baseRadius * 0.67, height: baseRadius * 0.8)

                Spacer().frame(width: baseRadius * 0.53)

                DPadVisualButton(
                    icon: "arrowtriangle.right.fill", direction: "Right",
                    isPressed: touchState.pressedDirection == "Right"
                )
                .frame(width: baseRadius * 0.67, height: baseRadius * 0.8)
            }

            DPadVisualButton(
                icon: "arrowtriangle.down.fill", direction: "Down",
                isPressed: touchState.pressedDirection == "Down"
            )
            .frame(width: baseRadius * 0.8, height: baseRadius * 0.67)
        }
        .frame(width: baseRadius * 2, height: baseRadius * 2)
        .background(
            GeometryReader { geo in
                Color.clear
                    .preference(key: DPadCenterKey.self, value: CGPoint(x: geo.size.width / 2, y: geo.size.height / 2))
            }
        )
        .onPreferenceChange(DPadCenterKey.self) { center in
            touchState.centerPoint = center
        }
        .gesture(dpadDragGesture)
    }

    private var dpadDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                touchState.handleTouch(at: value.location)
            }
            .onEnded { _ in
                touchState.handleRelease()
            }
    }
}

// MARK: - Floating Variant (cross shifted upward)

struct FloatingDPadContent: View {
    let baseRadius: CGFloat
    @ObservedObject var touchState: DPadTouchState

    var body: some View {
        CrossDPadContent(baseRadius: baseRadius, touchState: touchState)
            .offset(y: -baseRadius * 0.05)
    }
}

// MARK: - Clicky Variant (thicker rim)

struct ClickyDPadContent: View {
    let baseRadius: CGFloat
    @ObservedObject var touchState: DPadTouchState

    var body: some View {
        CrossDPadContent(baseRadius: baseRadius, touchState: touchState)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.6), lineWidth: 3)
            )
    }
}

// MARK: - Pivot Variant

struct PivotDPadContent: View {
    let baseRadius: CGFloat
    @ObservedObject var touchState: DPadTouchState

    var body: some View {
        contentLayout(barHalf: baseRadius * 0.36, btnSize: baseRadius * 0.5, hubSize: min(baseRadius * 0.36 * 0.95, baseRadius * 0.22))
    }

    @ViewBuilder
    private func contentLayout(barHalf: CGFloat, btnSize: CGFloat, hubSize: CGFloat) -> some View {
        let totalSize = baseRadius * 2

        VStack(spacing: 0) {
            DPadVisualButton(
                icon: "arrowtriangle.up.fill", direction: "Up",
                isPressed: touchState.pressedDirection == "Up"
            )
            .frame(width: btnSize, height: btnSize)

            HStack(spacing: 0) {
                DPadVisualButton(
                    icon: "arrowtriangle.left.fill", direction: "Left",
                    isPressed: touchState.pressedDirection == "Left"
                )
                .frame(width: btnSize, height: btnSize)

                Spacer().frame(width: baseRadius * 0.65)

                DPadVisualButton(
                    icon: "arrowtriangle.right.fill", direction: "Right",
                    isPressed: touchState.pressedDirection == "Right"
                )
                .frame(width: btnSize, height: btnSize)
            }

            DPadVisualButton(
                icon: "arrowtriangle.down.fill", direction: "Down",
                isPressed: touchState.pressedDirection == "Down"
            )
            .frame(width: btnSize, height: btnSize)
        }
        .frame(width: totalSize, height: totalSize)
        .background(
            GeometryReader { geo in
                Color.clear
                    .preference(key: DPadCenterKey.self, value: CGPoint(x: geo.size.width / 2, y: geo.size.height / 2))
            }
        )
        .background(
            ZStack {
                Capsule()
                    .fill(Color.black.opacity(0.7))
                    .frame(width: baseRadius * 2, height: barHalf * 2)
                Capsule()
                    .fill(Color.black.opacity(0.7))
                    .frame(width: barHalf * 2, height: baseRadius * 2)
                Circle()
                    .fill(Color(red: 0.15, green: 0.15, blue: 0.18))
                    .frame(width: hubSize, height: hubSize)
                    .overlay(
                        Circle().stroke(Color.gray.opacity(0.5), lineWidth: 2)
                    )
            }
        )
        .onPreferenceChange(DPadCenterKey.self) { center in
            touchState.centerPoint = center
        }
        .gesture(dpadDragGesture)
    }

    private var dpadDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                touchState.handleTouch(at: value.location)
            }
            .onEnded { _ in
                touchState.handleRelease()
            }
    }
}
