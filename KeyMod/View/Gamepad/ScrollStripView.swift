//
//  ScrollStripView.swift
//  KeyMod
//
//  Vertical scroll strip module — drag vertically to send HID mouse wheel events.
//  Matches Android's SCROLL_STRIP module behavior.
//

import SwiftUI

struct ScrollStripView: View {
    let mouseManager: MouseManager
    let isEditMode: Bool
    let sensitivity: Double

    @State private var lastScrollY: CGFloat = 0
    @State private var scrollAccumulator: CGFloat = 0
    @State private var isDragging = false
    @State private var highlightDir: Int = 0 // +1 = up, -1 = down

    private let scrollThreshold: CGFloat = 15.0
    private let pixelsPerWheel: CGFloat = 5.0

    init(mouseManager: MouseManager, isEditMode: Bool = false, sensitivity: Double = 1.0) {
        self.mouseManager = mouseManager
        self.isEditMode = isEditMode
        self.sensitivity = sensitivity
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Track background
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.25), lineWidth: 1)
                    )

                // Chevron indicators
                VStack {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(chevronColor(dir: 1))
                        .padding(.top, 8)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(chevronColor(dir: -1))
                        .padding(.bottom, 8)
                }

                // Thumb indicator
                if isDragging {
                    let progress = scrollProgress(in: geo.size)
                    Circle()
                        .fill(Color.blue.opacity(0.6))
                        .frame(width: 24, height: 24)
                        .position(x: geo.size.width / 2, y: progress)
                        .animation(.easeOut(duration: 0.1), value: progress)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { value in
                        isDragging = true
                        let deltaY = value.translation.height - lastScrollY
                        scrollAccumulator += deltaY

                        if abs(scrollAccumulator) >= scrollThreshold {
                            let direction: CGFloat = scrollAccumulator > 0 ? -1 : 1
                            let wheelAmount = Int(direction * sensitivity)
                            mouseManager.handleScroll(deltaX: 0, deltaY: wheelAmount)
                            highlightDir = Int(direction)
                            scrollAccumulator = 0

                            withAnimation(.easeOut(duration: 0.1)) {}
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                highlightDir = 0
                            }
                        }

                        lastScrollY = value.translation.height
                    }
                    .onEnded { _ in
                        isDragging = false
                        lastScrollY = 0
                        scrollAccumulator = 0
                        highlightDir = 0
                    }
            )
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isEditMode ? Color.orange : Color.clear, lineWidth: 2)
        )
    }

    private func chevronColor(dir: Int) -> Color {
        if highlightDir == dir {
            return .blue
        }
        return .gray.opacity(0.4)
    }

    private func scrollProgress(in size: CGSize) -> CGFloat {
        // Map scroll accumulator to visual position
        let maxAccum = scrollThreshold * 3
        let normalized = max(-1, min(1, scrollAccumulator / maxAccum))
        return size.height / 2 + normalized * size.height / 3
    }
}
