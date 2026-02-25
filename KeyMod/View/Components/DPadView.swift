//
//  DPadView.swift
//  KeyMod
//
//  Created by System on 2025/7/17.
//

import SwiftUI

struct DPadView: View {
    var onDirection: ((String) -> Void)? = nil
    var onDirectionUp: ((String) -> Void)? = nil
    var onLongPress: ((String) -> Void)? = nil
    let isEditMode: Bool
    let isKeyMappingMode: Bool
    @State private var pressedDirection: String? = nil
    @StateObject private var hapticManager = HapticFeedbackManager.shared
    
    var body: some View {
        ZStack {
            // Vertical bar
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 40, height: 120)
            
            // Horizontal bar
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 120, height: 40)
            
            // Direction buttons
            VStack {
                // Up
                ZStack {
                    Image(systemName: "arrowtriangle.up.fill")
                        .foregroundColor(pressedDirection == "Up" ? .white : .blue)
                        .frame(width: 35, height: 35)
                }
                .background(pressedDirection == "Up" ? Color.blue : Color.clear)
                .cornerRadius(8)
                .onTapGesture {
                    if isKeyMappingMode {
                        print("🔧 Tap detected on D-pad: Up")
                        onLongPress?("Up")
                    }
                }
                .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
                    if !isKeyMappingMode {
                        if pressing {
                            pressDown("Up")
                        } else {
                            pressUp("Up")
                        }
                    }
                }, perform: {
                    if isKeyMappingMode {
                        print("🔧 Long press detected on D-pad: Up")
                        onLongPress?("Up")
                    }
                })
                
                HStack {
                    // Left
                    ZStack {
                        Image(systemName: "arrowtriangle.left.fill")
                            .foregroundColor(pressedDirection == "Left" ? .white : .blue)
                            .frame(width: 35, height: 35)
                    }
                    .background(pressedDirection == "Left" ? Color.blue : Color.clear)
                    .cornerRadius(8)
                    .onTapGesture {
                        if isKeyMappingMode {
                            print("🔧 Tap detected on D-pad: Left")
                            onLongPress?("Left")
                        }
                    }
                    .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
                        if !isKeyMappingMode {
                            if pressing {
                                pressDown("Left")
                            } else {
                                pressUp("Left")
                            }
                        }
                    }, perform: {
                        if isKeyMappingMode {
                            print("🔧 Long press detected on D-pad: Left")
                            onLongPress?("Left")
                        }
                    })
                    
                    Spacer()
                        .frame(width: 35)
                    
                    // Right
                    ZStack {
                        Image(systemName: "arrowtriangle.right.fill")
                            .foregroundColor(pressedDirection == "Right" ? .white : .blue)
                            .frame(width: 35, height: 35)
                    }
                    .background(pressedDirection == "Right" ? Color.blue : Color.clear)
                    .cornerRadius(8)
                    .onTapGesture {
                        if isKeyMappingMode {
                            print("🔧 Tap detected on D-pad: Right")
                            onLongPress?("Right")
                        }
                    }
                    .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
                        if !isKeyMappingMode {
                            if pressing {
                                pressDown("Right")
                            } else {
                                pressUp("Right")
                            }
                        }
                    }, perform: {
                        if isKeyMappingMode {
                            print("🔧 Long press detected on D-pad: Right")
                            onLongPress?("Right")
                        }
                    })
                }
                
                // Down
                ZStack {
                    Image(systemName: "arrowtriangle.down.fill")
                        .foregroundColor(pressedDirection == "Down" ? .white : .blue)
                        .frame(width: 35, height: 35)
                }
                .background(pressedDirection == "Down" ? Color.blue : Color.clear)
                .cornerRadius(8)
                .onTapGesture {
                    if isKeyMappingMode {
                        print("🔧 Tap detected on D-pad: Down")
                        onLongPress?("Down")
                    }
                }
                .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
                    if !isKeyMappingMode {
                        if pressing {
                            pressDown("Down")
                        } else {
                            pressUp("Down")
                        }
                    }
                }, perform: {
                    if isKeyMappingMode {
                        print("🔧 Long press detected on D-pad: Down")
                        onLongPress?("Down")
                    }
                })
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isEditMode ? Color.orange : Color.clear, lineWidth: 3)
        )
    }
    
    private func pressDown(_ direction: String) {
        pressedDirection = direction
        // Trigger haptic feedback on D-pad press
        hapticManager.triggerButtonPress()
        onDirection?(direction)
    }
    
    private func pressUp(_ direction: String) {
        pressedDirection = nil
        onDirectionUp?(direction)
    }
}
