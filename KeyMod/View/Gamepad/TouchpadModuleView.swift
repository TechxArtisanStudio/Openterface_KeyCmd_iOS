//
//  TouchpadModuleView.swift
//  KeyMod
//
//  Touchpad module for dynamic gamepad layouts.
//  Reuses the existing TouchpadView for touch input, with L/M/R click buttons.
//

import SwiftUI

struct TouchpadModuleView: View {
    @ObservedObject var mouseManager: MouseManager
    let isEditMode: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Touchpad surface
            ZStack {
                // Touchpad background
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )

                // Touch area indicator
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Circle()
                            .stroke(Color.blue.opacity(0.4), lineWidth: 1)
                    )

                // Instruction text
                Text("Slide to move cursor")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(4)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 100)

            // L/M/R click buttons
            HStack(spacing: 1) {
                TouchpadClickButton(label: "L", onClick: { mouseManager.handleClick() })
                    .frame(maxWidth: .infinity)

                TouchpadClickButton(label: "M", onClick: { mouseManager.handleMiddleClick() })
                    .frame(maxWidth: .infinity)

                TouchpadClickButton(label: "R", onClick: { mouseManager.handleRightClick() })
                    .frame(maxWidth: .infinity)
            }
            .frame(height: 28)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isEditMode ? Color.orange : Color.clear, lineWidth: 2)
        )
    }
}

// MARK: - Touchpad Click Button

struct TouchpadClickButton: View {
    let label: String
    let onClick: () -> Void
    @State private var isPressed = false
    @StateObject private var hapticManager = HapticFeedbackManager.shared

    var body: some View {
        Button(action: {}) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isPressed ? .white : .secondary)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity)
                .background(isPressed ? Color.blue : Color.gray.opacity(0.15))
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        isPressed = true
                        hapticManager.triggerButtonPress()
                        onClick()
                    }
                }
                .onEnded { _ in
                    isPressed = false
                }
        )
    }
}
