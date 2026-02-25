//
//  ActionButtonsView.swift
//  KeyMod
//
//  Created by System on 2025/7/17.
//

import SwiftUI

struct ActionButtonsView: View {
    let buttonConfigs: [ActionButtonConfig]
    var onAction: ((String) -> Void)? = nil
    var onActionUp: ((String) -> Void)? = nil
    var onLongPress: ((String) -> Void)? = nil
    let isEditMode: Bool
    let isKeyMappingMode: Bool
    @State private var pressedButton: String? = nil
    @StateObject private var hapticManager = HapticFeedbackManager.shared
    
    var body: some View {
        ZStack {
            ForEach(buttonConfigs, id: \.label) { config in
                Button(action: {}) {
                    Text(config.label)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(pressedButton == config.label ? .black : .white)
                        .frame(width: 50, height: 50)
                        .background(pressedButton == config.label ? Color.gray : config.color)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(isEditMode ? Color.orange : Color.clear, lineWidth: 2)
                        )
                }
                .position(positionFor(config.position))
                .onTapGesture {
                    if isKeyMappingMode {
                        print("🔧 Tap detected on button: \(config.label)")
                        onLongPress?(config.label)
                    }
                }
                .onLongPressGesture(minimumDuration: 0.5) {
                    // Handle long press for individual button configuration
                    if isKeyMappingMode {
                        print("🔧 Long press detected on button: \(config.label)")
                        onLongPress?(config.label)
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if pressedButton != config.label {
                                pressDown(config.label)
                            }
                        }
                        .onEnded { _ in
                            pressUp(config.label)
                        }
                )
            }
        }
    }
    
    private func positionFor(_ position: ActionButtonPosition) -> CGPoint {
        let center = CGPoint(x: 75, y: 75) // Adjusted center for larger frame
        let offset: CGFloat = 40 // Increased spacing between buttons
        
        switch position {
        case .top:
            return CGPoint(x: center.x, y: center.y - offset)
        case .bottom:
            return CGPoint(x: center.x, y: center.y + offset)
        case .left:
            return CGPoint(x: center.x - offset, y: center.y)
        case .right:
            return CGPoint(x: center.x + offset, y: center.y)
        }
    }
    
    private func pressDown(_ button: String) {
        pressedButton = button
        // Trigger haptic feedback on action button press
        hapticManager.triggerButtonPress()
        onAction?(button)
    }
    
    private func pressUp(_ button: String) {
        pressedButton = nil
        onActionUp?(button)
    }
}
