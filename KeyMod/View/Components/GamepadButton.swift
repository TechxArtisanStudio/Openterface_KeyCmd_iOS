//
//  GamepadButton.swift
//  KeyMod
//
//  Created by System on 2025/7/17.
//

import SwiftUI

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
        Button(action: {}) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: width, height: 35)
                .background(isPressed ? Color.gray : Color.blue)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isEditMode ? Color.orange : Color.clear, lineWidth: 2)
                )
        }
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .onTapGesture {
            if isKeyMappingMode {
                print("🔧 Tap detected on button: \(label)")
                onLongPress?()
            }
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            if isKeyMappingMode {
                print("🔧 Long press detected on button: \(label)")
                onLongPress?()
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isKeyMappingMode && !isPressed {
                        withAnimation(.easeInOut(duration: 0.1)) {
                            isPressed = true
                        }
                        // Trigger haptic feedback on button press
                        hapticManager.triggerButtonPress()
                        action()
                    }
                }
                .onEnded { _ in
                    if !isKeyMappingMode {
                        withAnimation(.easeInOut(duration: 0.1)) {
                            isPressed = false
                        }
                        actionUp?()
                    }
                }
        )
    }
}
