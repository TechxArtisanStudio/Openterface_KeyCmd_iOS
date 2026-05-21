//
//  TouchpadModuleView.swift
//  KeyMod
//
//  Touchpad module for dynamic gamepad layouts.
//  Single touch surface with gradient background — matches Android's drawTouchpadModule.
//  L/M/R buttons are separate MOUSE_BUTTON modules in the preset, NOT embedded here.
//

import SwiftUI

struct TouchpadModuleView: View {
    @ObservedObject var mouseManager: MouseManager
    let isEditMode: Bool
    let onDelta: (CGFloat, CGFloat) -> Void
    let onDragEnd: () -> Void

    @State private var lastTouchLocation: CGPoint?

    var body: some View {
        ZStack {
            // Gradient background matching Android surface colors
            LinearGradient(
                colors: [
                    Color(red: 0.93, green: 0.94, blue: 0.96),
                    Color(red: 0.85, green: 0.86, blue: 0.89)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Subtle dot grid pattern (Android's gloss dots)
            DotGridPattern()

            // Label
            Text("Touchpad")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(red: 0.36, green: 0.38, blue: 0.41))

            // Border
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(red: 0.65, green: 0.68, blue: 0.72), lineWidth: 1)
        }
        .cornerRadius(10)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if let last = lastTouchLocation {
                        let dx = value.location.x - last.x
                        let dy = value.location.y - last.y
                        onDelta(dx, dy)
                    }
                    lastTouchLocation = value.location
                }
                .onEnded { _ in
                    lastTouchLocation = nil
                    onDragEnd()
                }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isEditMode ? Color.orange : Color.clear, lineWidth: 2)
        )
    }
}

// MARK: - Dot Grid Pattern

struct DotGridPattern: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 16
            var x: CGFloat = spacing
            while x < size.width - 8 {
                var y: CGFloat = spacing
                while y < size.height - 8 {
                    context.fill(Circle().path(in: CGRect(x: x, y: y, width: 1.3, height: 1.3)), with: .color(Color.black.opacity(0.08)))
                    y += spacing
                }
                x += spacing
            }
        }
    }
}
