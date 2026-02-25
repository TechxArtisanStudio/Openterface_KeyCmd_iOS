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
    var onTap: (() -> Void)? = nil
    let stickName: String
    let isEditMode: Bool
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
            Circle()
                .fill(Color.blue)
                .frame(width: 30, height: 30)
                .offset(dragOffset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if !isEditMode {
                                // Trigger haptic feedback only on first touch
                                if !hasDragStarted {
                                    hasDragStarted = true
                                    hapticManager.triggerButtonPress()
                                }
                                
                                let radius: CGFloat = 45
                                let distance = sqrt(value.translation.width * value.translation.width + value.translation.height * value.translation.height)
                                if distance <= radius {
                                    dragOffset = value.translation
                                } else {
                                    let angle = atan2(value.translation.height, value.translation.width)
                                    dragOffset = CGSize(
                                        width: cos(angle) * radius,
                                        height: sin(angle) * radius
                                    )
                                }
                                let normalizedX = dragOffset.width / radius
                                let normalizedY = dragOffset.height / radius
                                position = CGPoint(x: normalizedX, y: normalizedY)
                            }
                        }
                        .onEnded { _ in
                            if !isEditMode {
                                hasDragStarted = false
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
