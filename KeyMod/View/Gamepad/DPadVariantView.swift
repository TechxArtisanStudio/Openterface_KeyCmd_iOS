//
//  DPadVariantView.swift
//  KeyMod
//
//  D-pad with 6 visual variants: cross, disc, split, floating, clicky, pivot.
//  All variants produce identical directional key events.
//

import SwiftUI

struct DPadVariantView: View {
    var variant: DPadVariant = .cross
    var onDirection: ((String) -> Void)?
    var onDirectionUp: ((String) -> Void)?
    var onLongPress: ((String) -> Void)?
    let isEditMode: Bool
    let isKeyMappingMode: Bool

    var body: some View {
        Group {
            switch variant {
            case .cross:
                CrossDPadView(
                    onDirection: onDirection,
                    onDirectionUp: onDirectionUp,
                    onLongPress: onLongPress,
                    isEditMode: isEditMode,
                    isKeyMappingMode: isKeyMappingMode
                )
            case .disc:
                DiscDPadView(
                    onDirection: onDirection,
                    onDirectionUp: onDirectionUp,
                    onLongPress: onLongPress,
                    isEditMode: isEditMode,
                    isKeyMappingMode: isKeyMappingMode
                )
            case .split:
                SplitDPadView(
                    onDirection: onDirection,
                    onDirectionUp: onDirectionUp,
                    onLongPress: onLongPress,
                    isEditMode: isEditMode,
                    isKeyMappingMode: isKeyMappingMode
                )
            case .floating:
                FloatingDPadView(
                    onDirection: onDirection,
                    onDirectionUp: onDirectionUp,
                    onLongPress: onLongPress,
                    isEditMode: isEditMode,
                    isKeyMappingMode: isKeyMappingMode
                )
            case .clicky:
                ClickyDPadView(
                    onDirection: onDirection,
                    onDirectionUp: onDirectionUp,
                    onLongPress: onLongPress,
                    isEditMode: isEditMode,
                    isKeyMappingMode: isKeyMappingMode
                )
            case .pivot:
                PivotDPadView(
                    onDirection: onDirection,
                    onDirectionUp: onDirectionUp,
                    onLongPress: onLongPress,
                    isEditMode: isEditMode,
                    isKeyMappingMode: isKeyMappingMode
                )
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isEditMode ? Color.orange : Color.clear, lineWidth: 3)
        )
    }
}

// MARK: - Shared D-Pad Button

struct DPadButton: View {
    let icon: String
    let direction: String
    var onDirection: ((String) -> Void)?
    var onDirectionUp: ((String) -> Void)?
    var onLongPress: ((String) -> Void)?
    let isEditMode: Bool
    let isKeyMappingMode: Bool

    @State private var isPressed = false
    @StateObject private var hapticManager = HapticFeedbackManager.shared

    var body: some View {
        ZStack {
            Image(systemName: icon)
                .foregroundColor(isPressed ? .white : .gray.opacity(0.7))
                .font(.system(size: 16, weight: .bold))
        }
        .frame(width: 40, height: 40)
        .background(isPressed ? Color.blue.opacity(0.5) : Color.black.opacity(0.3))
        .cornerRadius(6)
        .onTapGesture {
            if isKeyMappingMode {
                onLongPress?(direction)
            }
        }
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            if !isKeyMappingMode {
                if pressing {
                    pressDown()
                } else {
                    pressUp()
                }
            }
        }, perform: {
            if isKeyMappingMode {
                onLongPress?(direction)
            }
        })
    }

    private func pressDown() {
        isPressed = true
        hapticManager.triggerButtonPress()
        onDirection?(direction)
    }

    private func pressUp() {
        isPressed = false
        onDirectionUp?(direction)
    }
}

// MARK: - Cross Variant (default, matches existing DPadView)

struct CrossDPadView: View {
    var onDirection: ((String) -> Void)?
    var onDirectionUp: ((String) -> Void)?
    var onLongPress: ((String) -> Void)?
    let isEditMode: Bool
    let isKeyMappingMode: Bool

    var body: some View {
        ZStack {
            // Vertical bar
            Rectangle()
                .fill(Color.black.opacity(0.8))
                .frame(width: 50, height: 150)
                .overlay(
                    Rectangle().stroke(Color.gray.opacity(0.4), lineWidth: 2)
                )

            // Horizontal bar
            Rectangle()
                .fill(Color.black.opacity(0.8))
                .frame(width: 150, height: 50)
                .overlay(
                    Rectangle().stroke(Color.gray.opacity(0.4), lineWidth: 2)
                )

            // Direction buttons
            VStack {
                DPadButton(icon: "arrowtriangle.up.fill", direction: "Up",
                           onDirection: onDirection, onDirectionUp: onDirectionUp,
                           onLongPress: onLongPress, isEditMode: isEditMode,
                           isKeyMappingMode: isKeyMappingMode)

                HStack {
                    DPadButton(icon: "arrowtriangle.left.fill", direction: "Left",
                               onDirection: onDirection, onDirectionUp: onDirectionUp,
                               onLongPress: onLongPress, isEditMode: isEditMode,
                               isKeyMappingMode: isKeyMappingMode)
                    Spacer().frame(width: 40)
                    DPadButton(icon: "arrowtriangle.right.fill", direction: "Right",
                               onDirection: onDirection, onDirectionUp: onDirectionUp,
                               onLongPress: onLongPress, isEditMode: isEditMode,
                               isKeyMappingMode: isKeyMappingMode)
                }

                DPadButton(icon: "arrowtriangle.down.fill", direction: "Down",
                           onDirection: onDirection, onDirectionUp: onDirectionUp,
                           onLongPress: onLongPress, isEditMode: isEditMode,
                           isKeyMappingMode: isKeyMappingMode)
            }
        }
    }
}

// MARK: - Floating Variant (cross shifted upward)

struct FloatingDPadView: View {
    var onDirection: ((String) -> Void)?
    var onDirectionUp: ((String) -> Void)?
    var onLongPress: ((String) -> Void)?
    let isEditMode: Bool
    let isKeyMappingMode: Bool

    var body: some View {
        CrossDPadView(
            onDirection: onDirection,
            onDirectionUp: onDirectionUp,
            onLongPress: onLongPress,
            isEditMode: isEditMode,
            isKeyMappingMode: isKeyMappingMode
        )
        .offset(y: -8) // Slight upward shift
    }
}

// MARK: - Clicky Variant (thicker rim)

struct ClickyDPadView: View {
    var onDirection: ((String) -> Void)?
    var onDirectionUp: ((String) -> Void)?
    var onLongPress: ((String) -> Void)?
    let isEditMode: Bool
    let isKeyMappingMode: Bool

    var body: some View {
        CrossDPadView(
            onDirection: onDirection,
            onDirectionUp: onDirectionUp,
            onLongPress: onLongPress,
            isEditMode: isEditMode,
            isKeyMappingMode: isKeyMappingMode
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.6), lineWidth: 3)
        )
    }
}

// MARK: - Disc Variant (circular)

struct DiscDPadView: View {
    var onDirection: ((String) -> Void)?
    var onDirectionUp: ((String) -> Void)?
    var onLongPress: ((String) -> Void)?
    let isEditMode: Bool
    let isKeyMappingMode: Bool

    @State private var pressedDirection: String?

    var body: some View {
        ZStack {
            // Base disc
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.25, green: 0.25, blue: 0.28),
                                 Color(red: 0.15, green: 0.15, blue: 0.18)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 75
                    )
                )
                .overlay(
                    Circle().stroke(Color.gray.opacity(0.4), lineWidth: 2)
                )

            // Direction sectors
            VStack {
                // Up
                ZStack {
                    Image(systemName: "arrowtriangle.up.fill")
                        .foregroundColor(pressedDirection == "Up" ? .white : .gray.opacity(0.5))
                        .font(.system(size: 14, weight: .bold))
                }
                .frame(width: 50, height: 50)
                .onTapGesture {
                    if isKeyMappingMode { onLongPress?("Up") }
                }
                .onLongPressGesture(minimumDuration: 0, pressing: { pressing in
                    if !isKeyMappingMode { pressing ? press("Up") : release("Up") }
                }, perform: {
                    if isKeyMappingMode { onLongPress?("Up") }
                })

                HStack {
                    // Left
                    ZStack {
                        Image(systemName: "arrowtriangle.left.fill")
                            .foregroundColor(pressedDirection == "Left" ? .white : .gray.opacity(0.5))
                            .font(.system(size: 14, weight: .bold))
                    }
                    .frame(width: 50, height: 50)
                    .onTapGesture { if isKeyMappingMode { onLongPress?("Left") } }
                    .onLongPressGesture(minimumDuration: 0, pressing: { pressing in
                        if !isKeyMappingMode { pressing ? press("Left") : release("Left") }
                    }, perform: { if isKeyMappingMode { onLongPress?("Left") } })

                    Spacer().frame(width: 50)

                    // Right
                    ZStack {
                        Image(systemName: "arrowtriangle.right.fill")
                            .foregroundColor(pressedDirection == "Right" ? .white : .gray.opacity(0.5))
                            .font(.system(size: 14, weight: .bold))
                    }
                    .frame(width: 50, height: 50)
                    .onTapGesture { if isKeyMappingMode { onLongPress?("Right") } }
                    .onLongPressGesture(minimumDuration: 0, pressing: { pressing in
                        if !isKeyMappingMode { pressing ? press("Right") : release("Right") }
                    }, perform: { if isKeyMappingMode { onLongPress?("Right") } })
                }

                // Down
                ZStack {
                    Image(systemName: "arrowtriangle.down.fill")
                        .foregroundColor(pressedDirection == "Down" ? .white : .gray.opacity(0.5))
                        .font(.system(size: 14, weight: .bold))
                    }
                .frame(width: 50, height: 50)
                .onTapGesture { if isKeyMappingMode { onLongPress?("Down") } }
                .onLongPressGesture(minimumDuration: 0, pressing: { pressing in
                    if !isKeyMappingMode { pressing ? press("Down") : release("Down") }
                }, perform: { if isKeyMappingMode { onLongPress?("Down") } })
            }
        }
        .frame(width: 150, height: 150)
    }

    private func press(_ dir: String) {
        pressedDirection = dir
        HapticFeedbackManager.shared.triggerButtonPress()
        onDirection?(dir)
    }

    private func release(_ dir: String) {
        pressedDirection = nil
        onDirectionUp?(dir)
    }
}

// MARK: - Split Variant (4 separate pads)

struct SplitDPadView: View {
    var onDirection: ((String) -> Void)?
    var onDirectionUp: ((String) -> Void)?
    var onLongPress: ((String) -> Void)?
    let isEditMode: Bool
    let isKeyMappingMode: Bool

    @State private var pressedDirection: String?

    private let gap: CGFloat = 12

    var body: some View {
        VStack(spacing: gap) {
            // Up pad
            DPadButton(icon: "arrowtriangle.up.fill", direction: "Up",
                       onDirection: onDirection, onDirectionUp: onDirectionUp,
                       onLongPress: onLongPress, isEditMode: isEditMode,
                       isKeyMappingMode: isKeyMappingMode)
                .frame(width: 60, height: 50)

            HStack(spacing: gap) {
                // Left pad
                DPadButton(icon: "arrowtriangle.left.fill", direction: "Left",
                           onDirection: onDirection, onDirectionUp: onDirectionUp,
                           onLongPress: onLongPress, isEditMode: isEditMode,
                           isKeyMappingMode: isKeyMappingMode)
                    .frame(width: 50, height: 60)

                Spacer().frame(width: 40)

                // Right pad
                DPadButton(icon: "arrowtriangle.right.fill", direction: "Right",
                           onDirection: onDirection, onDirectionUp: onDirectionUp,
                           onLongPress: onLongPress, isEditMode: isEditMode,
                           isKeyMappingMode: isKeyMappingMode)
                    .frame(width: 50, height: 60)
            }

            // Down pad
            DPadButton(icon: "arrowtriangle.down.fill", direction: "Down",
                       onDirection: onDirection, onDirectionUp: onDirectionUp,
                       onLongPress: onLongPress, isEditMode: isEditMode,
                       isKeyMappingMode: isKeyMappingMode)
                .frame(width: 60, height: 50)
        }
    }
}

// MARK: - Pivot Variant (center hub + drag)

struct PivotDPadView: View {
    var onDirection: ((String) -> Void)?
    var onDirectionUp: ((String) -> Void)?
    var onLongPress: ((String) -> Void)?
    let isEditMode: Bool
    let isKeyMappingMode: Bool

    @State private var pressedDirection: String?

    var body: some View {
        ZStack {
            // Horizontal bar
            Capsule()
                .fill(Color.black.opacity(0.7))
                .frame(width: 150, height: 44)

            // Vertical bar
            Capsule()
                .fill(Color.black.opacity(0.7))
                .frame(width: 44, height: 150)

            // Center hub
            Circle()
                .fill(Color(red: 0.15, green: 0.15, blue: 0.18))
                .frame(width: 40, height: 40)
                .overlay(
                    Circle().stroke(Color.gray.opacity(0.5), lineWidth: 2)
                )

            // Direction buttons on the bars
            VStack {
                DPadButton(icon: "arrowtriangle.up.fill", direction: "Up",
                           onDirection: onDirection, onDirectionUp: onDirectionUp,
                           onLongPress: onLongPress, isEditMode: isEditMode,
                           isKeyMappingMode: isKeyMappingMode)

                HStack {
                    DPadButton(icon: "arrowtriangle.left.fill", direction: "Left",
                               onDirection: onDirection, onDirectionUp: onDirectionUp,
                               onLongPress: onLongPress, isEditMode: isEditMode,
                               isKeyMappingMode: isKeyMappingMode)
                    Spacer().frame(width: 40)
                    DPadButton(icon: "arrowtriangle.right.fill", direction: "Right",
                               onDirection: onDirection, onDirectionUp: onDirectionUp,
                               onLongPress: onLongPress, isEditMode: isEditMode,
                               isKeyMappingMode: isKeyMappingMode)
                }

                DPadButton(icon: "arrowtriangle.down.fill", direction: "Down",
                           onDirection: onDirection, onDirectionUp: onDirectionUp,
                           onLongPress: onLongPress, isEditMode: isEditMode,
                           isKeyMappingMode: isKeyMappingMode)
            }
        }
    }
}
