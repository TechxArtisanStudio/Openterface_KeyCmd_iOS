//
//  AnalogStickView.swift
//  KeyMod
//
//  Created by System on 2025/7/17.
//

import SwiftUI

struct AnalogStickView: View {
    @Binding var position: CGPoint
    @State private var dragOffset: CGSize = .zero
    @State private var hasDragStarted = false
    @State private var hasFiredPress = false
    var onTap: (() -> Void)? = nil
    let stickName: String
    let isEditMode: Bool
    let baseRadius: CGFloat
    @StateObject private var hapticManager = HapticFeedbackManager.shared

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.gray.opacity(0.3))
                .overlay(
                    Circle()
                        .stroke(Color.gray, lineWidth: 2)
                )
                .overlay(
                    Circle()
                        .stroke(isEditMode ? Color.orange : Color.clear, lineWidth: 3)
                )
                .frame(width: baseRadius * 2, height: baseRadius * 2)
            Circle()
                .fill(Color.blue)
                .frame(width: baseRadius * 1.08, height: baseRadius * 1.08)
                .offset(dragOffset)
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            if !isEditMode {
                                if !hasFiredPress {
                                    hasFiredPress = true
                                    hapticManager.triggerButtonPress()
                                }
                                hasDragStarted = true

                                let distance = sqrt(value.translation.width * value.translation.width + value.translation.height * value.translation.height)
                                if distance <= baseRadius {
                                    dragOffset = value.translation
                                } else {
                                    let angle = atan2(value.translation.height, value.translation.width)
                                    dragOffset = CGSize(
                                        width: cos(angle) * baseRadius,
                                        height: sin(angle) * baseRadius
                                    )
                                }
                                let normalizedX = dragOffset.width / baseRadius
                                let normalizedY = dragOffset.height / baseRadius
                                position = CGPoint(x: normalizedX, y: normalizedY)
                            }
                        }
                        .onEnded { _ in
                            if !isEditMode {
                                hasDragStarted = false
                                hasFiredPress = false
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    dragOffset = .zero
                                    position = CGPoint.zero
                                }
                            }
                        }
                )
                .onTapGesture {
                    if isEditMode {
                        onTap?()
                    }
                }
        }
    }
}
