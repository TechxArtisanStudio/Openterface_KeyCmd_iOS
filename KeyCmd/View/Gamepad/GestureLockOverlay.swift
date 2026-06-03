//
//  GestureLockOverlay.swift
//  KeyMod
//
//  Visual overlay for gesture lock — shows four diagonal quadrants
//  and highlights the active direction during a drag gesture.
//

import SwiftUI

struct GestureLockOverlay: View {
    /// The currently highlighted quadrant (nil = no active gesture).
    let highlightedQuadrant: DiagonalDirection?
    /// Whether the overlay is in "gamepad" mode (all 4 quadrants) vs basic mode (up only).
    let isGamepadMode: Bool

    var body: some View {
        ZStack {
            // Circular background with quadrant dividers
            Circle()
                .fill(Color.black.opacity(0.6))
                .frame(width: 80, height: 80)
                .overlay(
                    GeometryReader { geo in
                        let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                        let radius = geo.size.width / 2

                        Path { path in
                            // Vertical divider
                            path.move(to: CGPoint(x: center.x, y: 0))
                            path.addLine(to: CGPoint(x: center.x, y: geo.size.height))
                            // Horizontal divider
                            path.move(to: CGPoint(x: 0, y: center.y))
                            path.addLine(to: CGPoint(x: geo.size.width, y: center.y))
                        }
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)

                        // Quadrant fills
                        if let highlighted = highlightedQuadrant {
                            quadrantShape(for: highlighted, in: geo.size)
                                .fill(Color.blue.opacity(0.4))
                        }
                    }
                )

            // Center icon
            Image(systemName: "lock.fill")
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(highlightedQuadrant != nil ? 0.9 : 0.5))
                .scaleEffect(highlightedQuadrant != nil ? 1.1 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: highlightedQuadrant)
        }
        .frame(width: 80, height: 80)
    }

    @ViewBuilder
    private func quadrantShape(for direction: DiagonalDirection, in size: CGSize) -> some Shape {
        QuadrantShape(direction: direction)
    }
}

struct QuadrantShape: Shape {
    let direction: DiagonalDirection

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)

        switch direction {
        case .upLeft:
            path.move(to: center)
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: rect.midX, y: 0))
            path.addLine(to: center)
        case .upRight:
            path.move(to: center)
            path.addLine(to: CGPoint(x: rect.midX, y: 0))
            path.addLine(to: CGPoint(x: rect.maxX, y: 0))
            path.addLine(to: center)
        case .downLeft:
            path.move(to: center)
            path.addLine(to: CGPoint(x: 0, y: rect.midY))
            path.addLine(to: CGPoint(x: 0, y: rect.maxY))
            path.addLine(to: center)
        case .downRight:
            path.move(to: center)
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: center)
        }

        path.closeSubpath()
        return path
    }
}

// MARK: - Gesture Lock State Tracker

/// Tracks drag gestures and classifies diagonal swipes for gesture lock.
class GestureLockTracker: ObservableObject {
    @Published var highlightedQuadrant: DiagonalDirection?

    private let minDistance: CGFloat = 10
    private let density: CGFloat = UIScreen.main.scale

    /// Update the tracker with the current drag offset.
    func update(dx: CGFloat, dy: CGFloat) {
        guard let result = GestureLockAnalyzer.classifyDiagonalSlot(
            dx: dx, dy: dy, density: density,
            rMinDp: PresetConstants.diagonalRMinDp,
            rCancelDp: PresetConstants.diagonalRCancelDp
        ) else {
            highlightedQuadrant = nil
            return
        }

        if result == gestureLockResultCancel {
            highlightedQuadrant = nil
            return
        }

        highlightedQuadrant = DiagonalDirection(rawValue: result)
    }

    /// Get the committed action on gesture end.
    func committedAction(for module: GamepadModule) -> String {
        guard let result = GestureLockAnalyzer.classifyDiagonalSlot(
            dx: currentDx, dy: currentDy, density: density,
            rMinDp: PresetConstants.diagonalRMinDp,
            rCancelDp: PresetConstants.diagonalRCancelDp
        ) else {
            return PresetConstants.gestureLockActionNone
        }

        if result == gestureLockResultCancel {
            return PresetConstants.gestureLockActionNone
        }

        return GestureLockAnalyzer.resolvedActionForSlot(
            module: module, slotKey: result
        )
    }

    private var currentDx: CGFloat = 0
    private var currentDy: CGFloat = 0

    func recordStart() {
        currentDx = 0
        currentDy = 0
        highlightedQuadrant = nil
    }

    func recordOffset(dx: CGFloat, dy: CGFloat) {
        currentDx = dx
        currentDy = dy
        update(dx: dx, dy: dy)
    }
}
