//
//  GamepadView.swift
//  KeyMod
//
//  Created by System on 2025/6/21.
//

import SwiftUI

struct GamepadView: View {
    @ObservedObject var orientationManager: OrientationManager
    @ObservedObject var keyboardManager: KeyboardManager
    @ObservedObject var mouseManager: MouseManager
    @StateObject private var configManager = GamepadConfigManager()
    @StateObject private var turboEngine: TurboEngine
    @StateObject private var gestureLockTracker = GestureLockTracker()
    @State private var leftStickPosition: CGPoint = .zero
    @State private var rightStickPosition: CGPoint = .zero
    @State private var leftStickKeys: Set<String> = []
    @State private var rightStickKeys: Set<String> = []
    @State private var showConfigPopup = false
    @State private var configButtonName = ""
    @State private var isResetting = false
    @State private var isPositionEditMode = false
    @State private var isKeyMappingMode = false
    let selectedLayout: GamepadLayout
    let isEditMode: Bool

    init(orientationManager: OrientationManager, keyboardManager: KeyboardManager, mouseManager: MouseManager, selectedLayout: GamepadLayout, isEditMode: Bool) {
        self.orientationManager = orientationManager
        self.keyboardManager = keyboardManager
        self.mouseManager = mouseManager
        self.selectedLayout = selectedLayout
        self.isEditMode = isEditMode
        _turboEngine = StateObject(wrappedValue: TurboEngine(keyboardManager: keyboardManager))
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if selectedLayout == .nes {
                    // Special NES controller layout with classic appearance
                    nesControllerLayout(geometry: geometry)
                } else if selectedLayout == .simple {
                    // Simple layout: large D-pad left, large buttons right
                    simpleGamepadLayout(geometry: geometry)
                } else if orientationManager.isLandscape {
                    // Landscape gamepad layout
                    landscapeGamepadLayout(geometry: geometry)
                } else {
                    // Portrait gamepad layout
                    portraitGamepadLayout(geometry: geometry)
                }
            }
        }
        .onDisappear {
            // Release all pressed keys when the gamepad view disappears
            releaseAllAnalogStickKeys()
            keyboardManager.releaseAllKeys()
            // Reset mouse manager state
            mouseManager.handleDragEnded()
            // Stop turbo engine
            turboEngine.stop()
        }
        .sheet(isPresented: $showConfigPopup) {
            ButtonConfigPopup(
                layout: selectedLayout,
                buttonName: configButtonName,
                configManager: configManager,
                isPresented: $showConfigPopup
            )
        }
    }
}

// MARK: - NES Controller Layout
extension GamepadView {
    
    @ViewBuilder
    func nesControllerLayout(geometry: GeometryProxy) -> some View {
        // NES Controller background and layout
        VStack(spacing: 0) {
            Spacer(minLength: orientationManager.isLandscape ? 20 : 40)
            
            // Main NES controller body
            ZStack {
                // Controller background with NES-style rounded rectangle
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.85, green: 0.85, blue: 0.85),
                                Color(red: 0.75, green: 0.75, blue: 0.75),
                                Color(red: 0.65, green: 0.65, blue: 0.65)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.black.opacity(0.4),
                                        Color.black.opacity(0.2)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ), 
                                lineWidth: 3
                            )
                    )
                    .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 6)
                
                // Controller elements layout
                HStack(spacing: orientationManager.isLandscape ? 40 : 30) {
                    // Left side - D-Pad
                    VStack {
                        Spacer()
                        
                        DraggableComponent(
                            componentName: "DPad",
                            layout: selectedLayout,
                            configManager: configManager,
                            isPositionEditMode: isPositionEditMode,
                            isKeyMappingMode: isKeyMappingMode,
                            geometry: geometry,
                            onLongPress: { showButtonConfig("DPad") }
                        ) {
                            NESDPadView(
                                onDirection: handleDPadPress, 
                                onDirectionUp: handleDPadRelease,
                                onLongPress: { direction in
                                    showButtonConfig(direction)
                                },
                                isEditMode: isEditMode,
                                isKeyMappingMode: isKeyMappingMode
                            )
                            .frame(width: orientationManager.isLandscape ? 160 : 140, height: orientationManager.isLandscape ? 160 : 140)
                        }
                        
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Center area - Start/Select buttons
                    VStack(spacing: 20) {
                        Spacer()
                        
                        // NES logo area
                        VStack(spacing: 8) {
                            Text("Nintendo")
                                .font(.system(size: orientationManager.isLandscape ? 20 : 18, weight: .bold, design: .monospaced))
                                .foregroundColor(.black.opacity(0.7))
                            
                            Text("ENTERTAINMENT SYSTEM")
                                .font(.system(size: orientationManager.isLandscape ? 10 : 9, weight: .medium, design: .monospaced))
                                .foregroundColor(.black.opacity(0.5))
                        }
                        .padding(.bottom, 15)
                        
                        // Inset area for Select/Start buttons (like real NES)
                        VStack(spacing: 12) {
                            // Select and Start buttons (horizontal layout like original NES)
                            HStack(spacing: 20) {
                                DraggableComponent(
                                    componentName: "CenterButton_1",
                                    layout: selectedLayout,
                                    configManager: configManager,
                                    isPositionEditMode: isPositionEditMode,
                                    isKeyMappingMode: isKeyMappingMode,
                                    geometry: geometry,
                                    onLongPress: { showButtonConfig(selectedLayout.centerButtons[1]) }
                                ) {
                                    NESCenterButton(
                                        label: selectedLayout.centerButtons[1],
                                        action: { handleButtonPress(selectedLayout.centerButtons[1]) },
                                        actionUp: { handleButtonRelease(selectedLayout.centerButtons[1]) },
                                        onLongPress: { showButtonConfig(selectedLayout.centerButtons[1]) },
                                        isEditMode: isEditMode,
                                        isKeyMappingMode: isKeyMappingMode
                                    )
                                }
                                
                                DraggableComponent(
                                    componentName: "CenterButton_0",
                                    layout: selectedLayout,
                                    configManager: configManager,
                                    isPositionEditMode: isPositionEditMode,
                                    isKeyMappingMode: isKeyMappingMode,
                                    geometry: geometry,
                                    onLongPress: { showButtonConfig(selectedLayout.centerButtons[0]) }
                                ) {
                                    NESCenterButton(
                                        label: selectedLayout.centerButtons[0],
                                        action: { handleButtonPress(selectedLayout.centerButtons[0]) },
                                        actionUp: { handleButtonRelease(selectedLayout.centerButtons[0]) },
                                        onLongPress: { showButtonConfig(selectedLayout.centerButtons[0]) },
                                        isEditMode: isEditMode,
                                        isKeyMappingMode: isKeyMappingMode
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.black.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.black.opacity(0.2), lineWidth: 1)
                                )
                        )
                        
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Right side - A/B buttons
                    VStack {
                        Spacer()
                        
                        DraggableComponent(
                            componentName: "ActionButtons",
                            layout: selectedLayout,
                            configManager: configManager,
                            isPositionEditMode: isPositionEditMode,
                            isKeyMappingMode: isKeyMappingMode,
                            geometry: geometry,
                            onLongPress: { showButtonConfig("ActionButtons") }
                        ) {
                            NESActionButtonsView(
                                buttonConfigs: selectedLayout.actionButtons,
                                onAction: handleActionButtonPress,
                                onActionUp: handleActionButtonRelease,
                                onLongPress: { buttonName in
                                    showButtonConfig(buttonName)
                                },
                                isEditMode: isEditMode,
                                isKeyMappingMode: isKeyMappingMode,
                                isLandscape: orientationManager.isLandscape
                            )
                        }
                        
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 20)
            }
            .frame(
                width: orientationManager.isLandscape ? geometry.size.width * 0.95 : geometry.size.width * 0.95,
                height: orientationManager.isLandscape ? geometry.size.height * 0.85 : geometry.size.height * 0.5
            )
            
            Spacer(minLength: orientationManager.isLandscape ? 20 : 40)
        }
    }
}

// MARK: - NES-specific D-Pad Component
struct NESDPadView: View {
    var onDirection: ((String) -> Void)? = nil
    var onDirectionUp: ((String) -> Void)? = nil
    var onLongPress: ((String) -> Void)? = nil
    let isEditMode: Bool
    let isKeyMappingMode: Bool
    @State private var pressedDirection: String? = nil
    @StateObject private var hapticManager = HapticFeedbackManager.shared
    
    var body: some View {
        ZStack {
            // Vertical bar - dark NES style
            Rectangle()
                .fill(Color.black.opacity(0.8))
                .frame(width: 50, height: 150)
                .overlay(
                    Rectangle()
                        .stroke(Color.gray.opacity(0.4), lineWidth: 2)
                )
            
            // Horizontal bar - dark NES style
            Rectangle()
                .fill(Color.black.opacity(0.8))
                .frame(width: 150, height: 50)
                .overlay(
                    Rectangle()
                        .stroke(Color.gray.opacity(0.4), lineWidth: 2)
                )
            
            // Direction buttons with NES styling
            VStack {
                // Up
                ZStack {
                    Image(systemName: "arrowtriangle.up.fill")
                        .foregroundColor(pressedDirection == "Up" ? .white : .gray.opacity(0.7))
                        .frame(width: 40, height: 40)
                        .font(.system(size: 20, weight: .bold))
                }
                .background(pressedDirection == "Up" ? Color.black : Color.clear)
                .cornerRadius(8)
                .onTapGesture {
                    if isKeyMappingMode {
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
                        onLongPress?("Up")
                    }
                })
                
                HStack {
                    // Left
                    ZStack {
                        Image(systemName: "arrowtriangle.left.fill")
                            .foregroundColor(pressedDirection == "Left" ? .white : .gray.opacity(0.7))
                            .frame(width: 40, height: 40)
                            .font(.system(size: 20, weight: .bold))
                    }
                    .background(pressedDirection == "Left" ? Color.black : Color.clear)
                    .cornerRadius(8)
                    .onTapGesture {
                        if isKeyMappingMode {
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
                            onLongPress?("Left")
                        }
                    })
                    
                    Spacer()
                        .frame(width: 40)
                    
                    // Right
                    ZStack {
                        Image(systemName: "arrowtriangle.right.fill")
                            .foregroundColor(pressedDirection == "Right" ? .white : .gray.opacity(0.7))
                            .frame(width: 40, height: 40)
                            .font(.system(size: 20, weight: .bold))
                    }
                    .background(pressedDirection == "Right" ? Color.black : Color.clear)
                    .cornerRadius(8)
                    .onTapGesture {
                        if isKeyMappingMode {
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
                            onLongPress?("Right")
                        }
                    })
                }
                
                // Down
                ZStack {
                    Image(systemName: "arrowtriangle.down.fill")
                        .foregroundColor(pressedDirection == "Down" ? .white : .gray.opacity(0.7))
                        .frame(width: 40, height: 40)
                        .font(.system(size: 20, weight: .bold))
                }
                .background(pressedDirection == "Down" ? Color.black : Color.clear)
                .cornerRadius(8)
                .onTapGesture {
                    if isKeyMappingMode {
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
        // Trigger haptic feedback on NES D-pad press
        hapticManager.triggerButtonPress()
        onDirection?(direction)
    }
    
    private func pressUp(_ direction: String) {
        pressedDirection = nil
        onDirectionUp?(direction)
    }
}

// MARK: - NES-specific UI Components
struct NESCenterButton: View {
    let label: String
    let action: () -> Void
    let actionUp: (() -> Void)?
    let onLongPress: (() -> Void)?
    let isEditMode: Bool
    let isKeyMappingMode: Bool
    @State private var isPressed = false
    @StateObject private var hapticManager = HapticFeedbackManager.shared
    
    var body: some View {
        Button(action: {}) {
            Text(label)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 80, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    isPressed ? Color.black.opacity(0.8) : Color.black.opacity(0.6),
                                    isPressed ? Color.black.opacity(0.6) : Color.black.opacity(0.4)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.gray.opacity(0.6), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.3), radius: isPressed ? 1 : 2, x: 0, y: isPressed ? 1 : 2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isEditMode ? Color.orange : Color.clear, lineWidth: 2)
                )
        }
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .onTapGesture {
            if isKeyMappingMode {
                onLongPress?()
            }
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            if isKeyMappingMode {
                onLongPress?()
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isKeyMappingMode && !isPressed {
                        isPressed = true
                        // Trigger haptic feedback on NES center button press
                        hapticManager.triggerButtonPress()
                        action()
                    }
                }
                .onEnded { _ in
                    if isPressed {
                        isPressed = false
                        actionUp?()
                    }
                }
        )
        .animation(.easeInOut(duration: 0.1), value: isPressed)
    }
}

struct NESActionButtonsView: View {
    let buttonConfigs: [ActionButtonConfig]
    let onAction: (String) -> Void
    let onActionUp: (String) -> Void
    let onLongPress: ((String) -> Void)?
    let isEditMode: Bool
    let isKeyMappingMode: Bool
    let isLandscape: Bool
    @State private var pressedButton: String?
    @StateObject private var hapticManager = HapticFeedbackManager.shared
    
    var body: some View {
        HStack(spacing: isLandscape ? 24 : 20) {
            ForEach(buttonConfigs.indices, id: \.self) { index in
                let config = buttonConfigs[index]
                let isPressed = pressedButton == config.label
                
                Button(action: {}) {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    isPressed ? config.color.opacity(0.7) : config.color,
                                    isPressed ? config.color.opacity(0.9) : config.color.opacity(0.8)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: isLandscape ? 65 : 60, height: isLandscape ? 65 : 60)
                        .overlay(
                            Text(config.label)
                                .font(.system(size: isLandscape ? 20 : 18, weight: .bold))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.3), radius: 1, x: 1, y: 1)
                        )
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.black.opacity(0.4),
                                            Color.black.opacity(0.2)
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ), 
                                    lineWidth: 2
                                )
                        )
                        .overlay(
                            Circle()
                                .stroke(isEditMode ? Color.orange : Color.clear, lineWidth: 2)
                        )
                        .shadow(color: .black.opacity(0.4), radius: isPressed ? 2 : 4, x: 0, y: isPressed ? 1 : 3)
                }
                .scaleEffect(isPressed ? 0.9 : 1.0)
                .onTapGesture {
                    if isKeyMappingMode {
                        onLongPress?(config.label)
                    }
                }
                .onLongPressGesture(minimumDuration: 0.5) {
                    if isKeyMappingMode {
                        onLongPress?(config.label)
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if !isKeyMappingMode && pressedButton != config.label {
                                pressDown(config.label)
                            }
                        }
                        .onEnded { _ in
                            pressUp(config.label)
                        }
                )
                .animation(.easeInOut(duration: 0.1), value: isPressed)
            }
        }
    }
    
    private func pressDown(_ buttonLabel: String) {
        pressedButton = buttonLabel
        // Trigger haptic feedback on NES action button press
        hapticManager.triggerButtonPress()
        onAction(buttonLabel)
    }
    
    private func pressUp(_ buttonLabel: String) {
        if pressedButton == buttonLabel {
            pressedButton = nil
            onActionUp(buttonLabel)
        }
    }
}

// MARK: - Layout Extensions
extension GamepadView {
    
    @ViewBuilder
    func landscapeGamepadLayout(geometry: GeometryProxy) -> some View {
        HStack {
            // Left side controls
            VStack {
                Spacer()
                
                // Left analog stick (hide for NES layout)
                if selectedLayout != .nes {
                    DraggableComponent(
                        componentName: "LeftStick",
                        layout: selectedLayout,
                        configManager: configManager,
                        isPositionEditMode: isPositionEditMode,
                        isKeyMappingMode: isKeyMappingMode,
                        geometry: geometry,
                        onLongPress: { showButtonConfig("LeftStick") }
                    ) {
                        AnalogStickView(
                            position: $leftStickPosition, 
                            onTap: { showButtonConfig("LeftStick") },
                            stickName: "LeftStick",
                            isEditMode: isEditMode
                        )
                        .frame(width: 120, height: 120)
                    }
                    .onChange(of: leftStickPosition) { newValue in
                        handleAnalogStickMove(stick: "left", position: newValue)
                    }
                    
                    Spacer()
                }
                
                // D-Pad
                DraggableComponent(
                    componentName: "DPad",
                    layout: selectedLayout,
                    configManager: configManager,
                    isPositionEditMode: isPositionEditMode,
                    isKeyMappingMode: isKeyMappingMode,
                    geometry: geometry,
                    onLongPress: { showButtonConfig("DPad") }
                ) {
                    DPadView(
                        onDirection: handleDPadPress, 
                        onDirectionUp: handleDPadRelease,
                        onLongPress: { direction in
                            showButtonConfig(direction)
                        },
                        isEditMode: isEditMode,
                        isKeyMappingMode: isKeyMappingMode
                    )
                    .frame(width: 150, height: 150)
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity)
            
            // Center area
            VStack {
                // Shoulder buttons (only show if layout has them)
                if selectedLayout.shoulderButtons.count >= 2 {
                    HStack(spacing: 40) {
                        DraggableComponent(
                            componentName: "ShoulderButton_0",
                            layout: selectedLayout,
                            configManager: configManager,
                            isPositionEditMode: isPositionEditMode,
                            isKeyMappingMode: isKeyMappingMode,
                            geometry: geometry,
                            onLongPress: { showButtonConfig(selectedLayout.shoulderButtons[0]) }
                        ) {
                            GamepadButton(
                                label: selectedLayout.shoulderButtons[0], 
                                action: { handleButtonPress(selectedLayout.shoulderButtons[0]) }, 
                                actionUp: { handleButtonRelease(selectedLayout.shoulderButtons[0]) },
                                onLongPress: { showButtonConfig(selectedLayout.shoulderButtons[0]) },
                                isEditMode: isEditMode,
                                isKeyMappingMode: isKeyMappingMode,
                                width: buttonWidth(for: selectedLayout)
                            )
                        }
                        DraggableComponent(
                            componentName: "ShoulderButton_1",
                            layout: selectedLayout,
                            configManager: configManager,
                            isPositionEditMode: isPositionEditMode,
                            isKeyMappingMode: isKeyMappingMode,
                            geometry: geometry,
                            onLongPress: { showButtonConfig(selectedLayout.shoulderButtons[1]) }
                        ) {
                            GamepadButton(
                                label: selectedLayout.shoulderButtons[1], 
                                action: { handleButtonPress(selectedLayout.shoulderButtons[1]) }, 
                                actionUp: { handleButtonRelease(selectedLayout.shoulderButtons[1]) },
                                onLongPress: { showButtonConfig(selectedLayout.shoulderButtons[1]) },
                                isEditMode: isEditMode,
                                isKeyMappingMode: isKeyMappingMode,
                                width: buttonWidth(for: selectedLayout)
                            )
                        }
                    }
                }
                
                Spacer()
                
                // Center buttons
                HStack(spacing: 30) {
                    DraggableComponent(
                        componentName: "CenterButton_1",
                        layout: selectedLayout,
                        configManager: configManager,
                        isPositionEditMode: isPositionEditMode,
                        isKeyMappingMode: isKeyMappingMode,
                        geometry: geometry,
                        onLongPress: { showButtonConfig(selectedLayout.centerButtons[1]) }
                    ) {
                        GamepadButton(
                            label: selectedLayout.centerButtons[1], 
                            action: { handleButtonPress(selectedLayout.centerButtons[1]) }, 
                            actionUp: { handleButtonRelease(selectedLayout.centerButtons[1]) },
                            onLongPress: { showButtonConfig(selectedLayout.centerButtons[1]) },
                            isEditMode: isEditMode,
                            isKeyMappingMode: isKeyMappingMode,
                            width: buttonWidth(for: selectedLayout)
                        )
                    }
                    DraggableComponent(
                        componentName: "CenterButton_0",
                        layout: selectedLayout,
                        configManager: configManager,
                        isPositionEditMode: isPositionEditMode,
                        isKeyMappingMode: isKeyMappingMode,
                        geometry: geometry,
                        onLongPress: { showButtonConfig(selectedLayout.centerButtons[0]) }
                    ) {
                        GamepadButton(
                            label: selectedLayout.centerButtons[0], 
                            action: { handleButtonPress(selectedLayout.centerButtons[0]) }, 
                            actionUp: { handleButtonRelease(selectedLayout.centerButtons[0]) },
                            onLongPress: { showButtonConfig(selectedLayout.centerButtons[0]) },
                            isEditMode: isEditMode,
                            isKeyMappingMode: isKeyMappingMode,
                            width: buttonWidth(for: selectedLayout)
                        )
                    }
                }
                
                Spacer()
                
                // Trigger buttons (only show if layout has them)
                if selectedLayout.shoulderButtons.count >= 4 {
                    HStack(spacing: 40) {
                        DraggableComponent(
                            componentName: "ShoulderButton_2",
                            layout: selectedLayout,
                            configManager: configManager,
                            isPositionEditMode: isPositionEditMode,
                            isKeyMappingMode: isKeyMappingMode,
                            geometry: geometry,
                            onLongPress: { showButtonConfig(selectedLayout.shoulderButtons[2]) }
                        ) {
                            GamepadButton(
                                label: selectedLayout.shoulderButtons[2], 
                                action: { handleButtonPress(selectedLayout.shoulderButtons[2]) }, 
                                actionUp: { handleButtonRelease(selectedLayout.shoulderButtons[2]) },
                                onLongPress: { showButtonConfig(selectedLayout.shoulderButtons[2]) },
                                isEditMode: isEditMode,
                                isKeyMappingMode: isKeyMappingMode,
                                width: buttonWidth(for: selectedLayout)
                            )
                        }
                        DraggableComponent(
                            componentName: "ShoulderButton_3",
                            layout: selectedLayout,
                            configManager: configManager,
                            isPositionEditMode: isPositionEditMode,
                            isKeyMappingMode: isKeyMappingMode,
                            geometry: geometry,
                            onLongPress: { showButtonConfig(selectedLayout.shoulderButtons[3]) }
                        ) {
                            GamepadButton(
                                label: selectedLayout.shoulderButtons[3], 
                                action: { handleButtonPress(selectedLayout.shoulderButtons[3]) }, 
                                actionUp: { handleButtonRelease(selectedLayout.shoulderButtons[3]) },
                                onLongPress: { showButtonConfig(selectedLayout.shoulderButtons[3]) },
                                isEditMode: isEditMode,
                                isKeyMappingMode: isKeyMappingMode,
                                width: buttonWidth(for: selectedLayout)
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            
            // Right side controls
            VStack {
                Spacer()
                
                // Action buttons (ABXY)
                DraggableComponent(
                    componentName: "ActionButtons",
                    layout: selectedLayout,
                    configManager: configManager,
                    isPositionEditMode: isPositionEditMode,
                    isKeyMappingMode: isKeyMappingMode,
                    geometry: geometry,
                    onLongPress: { showButtonConfig("ActionButtons") }
                ) {
                    ActionButtonsView(
                        buttonConfigs: selectedLayout.actionButtons,
                        onAction: handleActionButtonPress,
                        onActionUp: handleActionButtonRelease,
                        onLongPress: { buttonName in
                            showButtonConfig(buttonName)
                        },
                        isEditMode: isEditMode,
                        isKeyMappingMode: isKeyMappingMode
                    )
                    .frame(width: 150, height: 150)
                }
                
                Spacer()
                
                // Right analog stick (hide for NES layout)
                if selectedLayout != .nes {
                    DraggableComponent(
                        componentName: "RightStick",
                        layout: selectedLayout,
                        configManager: configManager,
                        isPositionEditMode: isPositionEditMode,
                        isKeyMappingMode: isKeyMappingMode,
                        geometry: geometry,
                        onLongPress: { showButtonConfig("RightStick") }
                    ) {
                        AnalogStickView(
                            position: $rightStickPosition,
                            onTap: { showButtonConfig("RightStick") },
                            stickName: "RightStick",
                            isEditMode: isEditMode
                        )
                        .frame(width: 120, height: 120)
                    }
                    .onChange(of: rightStickPosition) { newValue in
                        handleAnalogStickMove(stick: "right", position: newValue)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
    }
    
    @ViewBuilder
    func portraitGamepadLayout(geometry: GeometryProxy) -> some View {
        VStack(spacing: 20) {
            // Top shoulder buttons (only show if layout has them)
            if selectedLayout.shoulderButtons.count >= 4 {
                HStack(spacing: 60) {
                    DraggableComponent(
                        componentName: "ShoulderButton_0",
                        layout: selectedLayout,
                        configManager: configManager,
                        isPositionEditMode: isPositionEditMode,
                        isKeyMappingMode: isKeyMappingMode,
                        geometry: geometry,
                        onLongPress: { showButtonConfig(selectedLayout.shoulderButtons[0]) }
                    ) {
                        GamepadButton(
                            label: selectedLayout.shoulderButtons[0], 
                            action: { handleButtonPress(selectedLayout.shoulderButtons[0]) }, 
                            actionUp: { handleButtonRelease(selectedLayout.shoulderButtons[0]) },
                            onLongPress: { showButtonConfig(selectedLayout.shoulderButtons[0]) },
                            isEditMode: isEditMode,
                            isKeyMappingMode: isKeyMappingMode,
                            width: buttonWidth(for: selectedLayout)
                        )
                    }
                    DraggableComponent(
                        componentName: "ShoulderButton_2",
                        layout: selectedLayout,
                        configManager: configManager,
                        isPositionEditMode: isPositionEditMode,
                        isKeyMappingMode: isKeyMappingMode,
                        geometry: geometry,
                        onLongPress: { showButtonConfig(selectedLayout.shoulderButtons[2]) }
                    ) {
                        GamepadButton(
                            label: selectedLayout.shoulderButtons[2], 
                            action: { handleButtonPress(selectedLayout.shoulderButtons[2]) }, 
                            actionUp: { handleButtonRelease(selectedLayout.shoulderButtons[2]) },
                            onLongPress: { showButtonConfig(selectedLayout.shoulderButtons[2]) },
                            isEditMode: isEditMode,
                            isKeyMappingMode: isKeyMappingMode,
                            width: buttonWidth(for: selectedLayout)
                        )
                    }
                    
                    Spacer()
                    
                    DraggableComponent(
                        componentName: "ShoulderButton_3",
                        layout: selectedLayout,
                        configManager: configManager,
                        isPositionEditMode: isPositionEditMode,
                        isKeyMappingMode: isKeyMappingMode,
                        geometry: geometry,
                        onLongPress: { showButtonConfig(selectedLayout.shoulderButtons[3]) }
                    ) {
                        GamepadButton(
                            label: selectedLayout.shoulderButtons[3], 
                            action: { handleButtonPress(selectedLayout.shoulderButtons[3]) }, 
                            actionUp: { handleButtonRelease(selectedLayout.shoulderButtons[3]) },
                            onLongPress: { showButtonConfig(selectedLayout.shoulderButtons[3]) },
                            isEditMode: isEditMode,
                            isKeyMappingMode: isKeyMappingMode,
                            width: buttonWidth(for: selectedLayout)
                        )
                    }
                    DraggableComponent(
                        componentName: "ShoulderButton_1",
                        layout: selectedLayout,
                        configManager: configManager,
                        isPositionEditMode: isPositionEditMode,
                        isKeyMappingMode: isKeyMappingMode,
                        geometry: geometry,
                        onLongPress: { showButtonConfig(selectedLayout.shoulderButtons[1]) }
                    ) {
                        GamepadButton(
                            label: selectedLayout.shoulderButtons[1], 
                            action: { handleButtonPress(selectedLayout.shoulderButtons[1]) }, 
                            actionUp: { handleButtonRelease(selectedLayout.shoulderButtons[1]) },
                            onLongPress: { showButtonConfig(selectedLayout.shoulderButtons[1]) },
                            isEditMode: isEditMode,
                            isKeyMappingMode: isKeyMappingMode,
                            width: buttonWidth(for: selectedLayout)
                        )
                    }
                }
                .padding(.horizontal)
            }
            
            // Main control area
            HStack {
                // Left controls
                VStack(spacing: 20) {
                    // D-Pad
                    DraggableComponent(
                        componentName: "DPad",
                        layout: selectedLayout,
                        configManager: configManager,
                        isPositionEditMode: isPositionEditMode,
                        isKeyMappingMode: isKeyMappingMode,
                        geometry: geometry,
                        onLongPress: { showButtonConfig("DPad") }
                    ) {
                        DPadView(
                            onDirection: handleDPadPress, 
                            onDirectionUp: handleDPadRelease,
                            onLongPress: { direction in
                                showButtonConfig(direction)
                            },
                            isEditMode: isEditMode,
                            isKeyMappingMode: isKeyMappingMode
                        )
                        .frame(width: 130, height: 130)
                    }
                    
                    // Left analog stick (hide for NES layout)
                    if selectedLayout != .nes {
                        DraggableComponent(
                            componentName: "LeftStick",
                            layout: selectedLayout,
                            configManager: configManager,
                            isPositionEditMode: isPositionEditMode,
                            isKeyMappingMode: isKeyMappingMode,
                            geometry: geometry,
                            onLongPress: { showButtonConfig("LeftStick") }
                        ) {
                            AnalogStickView(
                                position: $leftStickPosition,
                                onTap: { showButtonConfig("LeftStick") },
                                stickName: "LeftStick",
                                isEditMode: isEditMode
                            )
                            .frame(width: 100, height: 100)
                        }
                        .onChange(of: leftStickPosition) { newValue in
                            handleAnalogStickMove(stick: "left", position: newValue)
                        }
                    }
                }
                
                Spacer()
                
                // Right controls
                VStack(spacing: 20) {
                    DraggableComponent(
                        componentName: "ActionButtons",
                        layout: selectedLayout,
                        configManager: configManager,
                        isPositionEditMode: isPositionEditMode,
                        isKeyMappingMode: isKeyMappingMode,
                        geometry: geometry,
                        onLongPress: { showButtonConfig("ActionButtons") }
                    ) {
                        ActionButtonsView(
                            buttonConfigs: selectedLayout.actionButtons,
                            onAction: handleActionButtonPress,
                            onActionUp: handleActionButtonRelease,
                            onLongPress: { buttonName in
                                showButtonConfig(buttonName)
                            },
                            isEditMode: isEditMode,
                            isKeyMappingMode: isKeyMappingMode
                        )
                        .frame(width: 130, height: 130)
                    }

                    // Right analog stick (hide for NES layout)
                    if selectedLayout != .nes {
                        DraggableComponent(
                            componentName: "RightStick",
                            layout: selectedLayout,
                            configManager: configManager,
                            isPositionEditMode: isPositionEditMode,
                            isKeyMappingMode: isKeyMappingMode,
                            geometry: geometry,
                            onLongPress: { showButtonConfig("RightStick") }
                        ) {
                            AnalogStickView(
                                position: $rightStickPosition,
                                onTap: { showButtonConfig("RightStick") },
                                stickName: "RightStick",
                                isEditMode: isEditMode
                            )
                            .frame(width: 100, height: 100)
                        }
                        .onChange(of: rightStickPosition) { newValue in
                            handleAnalogStickMove(stick: "right", position: newValue)
                        }
                    }
                }
            }
            .padding(.horizontal)
            
            // Bottom center buttons
            HStack(spacing: 40) {
                DraggableComponent(
                    componentName: "CenterButton_1",
                    layout: selectedLayout,
                    configManager: configManager,
                    isPositionEditMode: isPositionEditMode,
                    isKeyMappingMode: isKeyMappingMode,
                    geometry: geometry,
                    onLongPress: { showButtonConfig(selectedLayout.centerButtons[1]) }
                ) {
                    GamepadButton(
                        label: selectedLayout.centerButtons[1], 
                        action: { handleButtonPress(selectedLayout.centerButtons[1]) }, 
                        actionUp: { handleButtonRelease(selectedLayout.centerButtons[1]) },
                        onLongPress: { showButtonConfig(selectedLayout.centerButtons[1]) },
                        isEditMode: isEditMode,
                        isKeyMappingMode: isKeyMappingMode,
                        width: buttonWidth(for: selectedLayout)
                    )
                }
                DraggableComponent(
                    componentName: "CenterButton_0",
                    layout: selectedLayout,
                    configManager: configManager,
                    isPositionEditMode: isPositionEditMode,
                    isKeyMappingMode: isKeyMappingMode,
                    geometry: geometry,
                    onLongPress: { showButtonConfig(selectedLayout.centerButtons[0]) }
                ) {
                    GamepadButton(
                        label: selectedLayout.centerButtons[0], 
                        action: { handleButtonPress(selectedLayout.centerButtons[0]) }, 
                        actionUp: { handleButtonRelease(selectedLayout.centerButtons[0]) },
                        onLongPress: { showButtonConfig(selectedLayout.centerButtons[0]) },
                        isEditMode: isEditMode,
                        isKeyMappingMode: isKeyMappingMode,
                        width: buttonWidth(for: selectedLayout)
                    )
                }
            }
            
            Spacer()
        }
        .padding()
    }

    // MARK: - Simple Layout
    @ViewBuilder
    func simpleGamepadLayout(geometry: GeometryProxy) -> some View {
        // Simple layout: large D-pad on left, large action buttons on right
        HStack(spacing: orientationManager.isLandscape ? 60 : 40) {
            // Left side: large D-pad
            VStack {
                Spacer()

                DraggableComponent(
                    componentName: "DPad",
                    layout: selectedLayout,
                    configManager: configManager,
                    isPositionEditMode: isPositionEditMode,
                    isKeyMappingMode: isKeyMappingMode,
                    geometry: geometry,
                    onLongPress: { showButtonConfig("DPad") }
                ) {
                    DPadView(
                        onDirection: handleDPadPress,
                        onDirectionUp: handleDPadRelease,
                        onLongPress: { direction in
                            showButtonConfig(direction)
                        },
                        isEditMode: isEditMode,
                        isKeyMappingMode: isKeyMappingMode
                    )
                    .frame(width: orientationManager.isLandscape ? 180 : 150,
                           height: orientationManager.isLandscape ? 180 : 150)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity)

            // Right side: large action buttons
            VStack {
                Spacer()

                DraggableComponent(
                    componentName: "ActionButtons",
                    layout: selectedLayout,
                    configManager: configManager,
                    isPositionEditMode: isPositionEditMode,
                    isKeyMappingMode: isKeyMappingMode,
                    geometry: geometry,
                    onLongPress: { showButtonConfig("ActionButtons") }
                ) {
                    ActionButtonsView(
                        buttonConfigs: selectedLayout.actionButtons,
                        onAction: handleActionButtonPress,
                        onActionUp: handleActionButtonRelease,
                        onLongPress: { buttonName in
                            showButtonConfig(buttonName)
                        },
                        isEditMode: isEditMode,
                        isKeyMappingMode: isKeyMappingMode
                    )
                    .frame(width: orientationManager.isLandscape ? 180 : 150,
                           height: orientationManager.isLandscape ? 180 : 150)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
    }
}

// MARK: - Event Handlers Extension
extension GamepadView {
    
    // MARK: - Button Configuration
    func showButtonConfig(_ buttonName: String) {
        if isKeyMappingMode {
            configButtonName = buttonName
            showConfigPopup = true
        }
    }
    
    // MARK: - Button Press/Release Handlers
    func handleButtonPress(_ button: String) {
        if isKeyMappingMode {
            showButtonConfig(button)
            return
        }
        gestureLockTracker.recordStart()
        print("Gamepad button pressed down: \(button)")
        let action = configManager.getEffectiveKey(layout: selectedLayout, button: button)
        print("🔍 Button \(button) mapped to action: '\(action)'")
        if !action.isEmpty {
            if isMouseAction(action) {
                print("🖱️ Executing mouse action: \(action)")
                handleMouseAction(action)
            } else if configManager.isTurboEnabled(layout: selectedLayout, button: button) {
                let turboCfg = configManager.getTurboConfig(layout: selectedLayout, button: button)
                turboEngine.start(key: action, config: TurboConfig(enabled: true, intervalMs: turboCfg.intervalMs, initialDelayMs: turboCfg.initialDelayMs))
            } else if configManager.hasGestureLock(layout: selectedLayout, button: button) {
                keyboardManager.handleKeyDown(action)
            } else {
                print("⌨️ Executing keyboard action: \(action)")
                keyboardManager.handleKeyDown(action)
            }
        }
    }

    func handleButtonRelease(_ button: String) {
        print("Gamepad button released: \(button)")
        let action = configManager.getEffectiveKey(layout: selectedLayout, button: button)
        if !action.isEmpty {
            let gestureAction = resolveGestureLockAction(button: button)
            switch gestureAction {
            case PresetConstants.gestureLockActionHoldLock:
                keyboardManager.handleKeyUp(action)
            case PresetConstants.gestureLockActionTurbo, PresetConstants.gestureLockActionKeyTurbo:
                turboEngine.stop()
            case PresetConstants.gestureLockActionKeyHold:
                keyboardManager.handleKeyUp(action)
            default:
                if !isMouseAction(action) && !turboEngine.isActive {
                    keyboardManager.handleKeyUp(action)
                }
            }
        }
    }
    
    func handleActionButtonPress(_ button: String) {
        if isKeyMappingMode {
            showButtonConfig(button)
            return
        }
        gestureLockTracker.recordStart()
        print("🔴 === ACTION BUTTON PRESS DEBUG ===")
        print("🔴 Button name received: '\(button)'")
        print("🔴 Selected layout: \(selectedLayout.rawValue)")
        print("Action button pressed down: \(button)")
        let action = configManager.getEffectiveKey(layout: selectedLayout, button: button)
        print("🔍 Action Button \(button) mapped to action: '\(action)'")
        print("🔴 === END ACTION BUTTON PRESS DEBUG ===")
        if !action.isEmpty {
            if isMouseAction(action) {
                print("🖱️ Executing mouse action: \(action)")
                handleMouseAction(action)
            } else if configManager.isTurboEnabled(layout: selectedLayout, button: button) {
                let turboCfg = configManager.getTurboConfig(layout: selectedLayout, button: button)
                turboEngine.start(key: action, config: TurboConfig(enabled: true, intervalMs: turboCfg.intervalMs, initialDelayMs: turboCfg.initialDelayMs))
            } else if configManager.hasGestureLock(layout: selectedLayout, button: button) {
                keyboardManager.handleKeyDown(action)
            } else {
                print("⌨️ Executing keyboard action: \(action)")
                keyboardManager.handleKeyDown(action)
            }
        }
    }

    func handleActionButtonRelease(_ button: String) {
        print("Action button released: \(button)")
        let action = configManager.getEffectiveKey(layout: selectedLayout, button: button)
        if !action.isEmpty {
            let gestureAction = resolveGestureLockAction(button: button)
            switch gestureAction {
            case PresetConstants.gestureLockActionHoldLock:
                keyboardManager.handleKeyUp(action)
            case PresetConstants.gestureLockActionTurbo, PresetConstants.gestureLockActionKeyTurbo:
                turboEngine.stop()
            case PresetConstants.gestureLockActionKeyHold:
                keyboardManager.handleKeyUp(action)
            default:
                if !isMouseAction(action) && !turboEngine.isActive {
                    keyboardManager.handleKeyUp(action)
                }
            }
        }
    }
    
    // MARK: - D-Pad Handlers
    func handleDPadPress(_ direction: String) {
        if isKeyMappingMode {
            showButtonConfig(direction)
            return
        }
        print("D-Pad pressed down: \(direction)")
        // Map D-Pad to arrow keys
        switch direction {
        case "Up": keyboardManager.handleKeyDown("Up")
        case "Down": keyboardManager.handleKeyDown("Down")
        case "Left": keyboardManager.handleKeyDown("Left")
        case "Right": keyboardManager.handleKeyDown("Right")
        default: break
        }
    }
    
    func handleDPadRelease(_ direction: String) {
        print("D-Pad released: \(direction)")
        // Map D-Pad to arrow keys
        switch direction {
        case "Up": keyboardManager.handleKeyUp("Up")
        case "Down": keyboardManager.handleKeyUp("Down")
        case "Left": keyboardManager.handleKeyUp("Left")
        case "Right": keyboardManager.handleKeyUp("Right")
        default: break
        }
    }
    
    // MARK: - Analog Stick Handlers
    func handleAnalogStickMove(stick: String, position: CGPoint) {
        if stick == "left" {
            // Handle left stick - map to keyboard keys with composite direction support
            let activationThreshold: CGFloat = 0.6  // Lower threshold for initial activation
            let deactivationThreshold: CGFloat = 0.4  // Even lower threshold for deactivation (hysteresis)
            
            // Debug: check if stick returned to center and reset state
            if abs(position.x) < 0.1 && abs(position.y) < 0.1 {
                if !leftStickKeys.isEmpty {
                    print("🔄 Left stick returned to center, releasing all keys: \(Array(leftStickKeys))")
                    keyboardManager.handleKeysUp(Array(leftStickKeys))
                    leftStickKeys.removeAll()
                    return
                }
            }
            
            // Handle left stick - get configurable keys
            let keys = configManager.getAnalogStickKeys(layout: selectedLayout, stick: "LeftStick")
            handleAnalogStickCompositeWithHysteresis(stick: stick, position: position, activationThreshold: activationThreshold, deactivationThreshold: deactivationThreshold, keys: keys)
            
        } else if stick == "right" {
            // Handle right stick - map to mouse movement in relative mode
            // Check if stick returned to center
            if abs(position.x) < 0.1 && abs(position.y) < 0.1 {
                // Stick is centered, end any mouse drag to reset state
                mouseManager.handleDragEnded()
                return
            }
            
            handleRightStickMouseMovement(position: position)
        }
    }
    
    func handleAnalogStickCompositeWithHysteresis(stick: String, position: CGPoint, activationThreshold: CGFloat, deactivationThreshold: CGFloat, keys: (up: String, down: String, left: String, right: String)) {
        let currentKeys = stick == "left" ? leftStickKeys : rightStickKeys
        
        // Determine which keys should be pressed based on current position with hysteresis
        var keysToPress: Set<String> = []

        // Vertical movement with hysteresis
        let isUpCurrentlyPressed = currentKeys.contains(keys.up)
        let isDownCurrentlyPressed = currentKeys.contains(keys.down)
        
        if -position.y > activationThreshold || (isUpCurrentlyPressed && -position.y > deactivationThreshold) {
            keysToPress.insert(keys.up)
        } else if -position.y < -activationThreshold || (isDownCurrentlyPressed && -position.y < -deactivationThreshold) {
            keysToPress.insert(keys.down)
        }
        
        // Horizontal movement with hysteresis
        let isLeftCurrentlyPressed = currentKeys.contains(keys.left)
        let isRightCurrentlyPressed = currentKeys.contains(keys.right)
        
        if position.x > activationThreshold || (isRightCurrentlyPressed && position.x > deactivationThreshold) {
            keysToPress.insert(keys.right)
        } else if position.x < -activationThreshold || (isLeftCurrentlyPressed && position.x < -deactivationThreshold) {
            keysToPress.insert(keys.left)
        }
        
        // Calculate keys to release (currently pressed but not in new set)
        let keysToRelease = currentKeys.subtracting(keysToPress)
        
        // Calculate keys to press (in new set but not currently pressed)
        let keysToAdd = keysToPress.subtracting(currentKeys)
        
        // Release keys that are no longer needed
        if !keysToRelease.isEmpty {
            keyboardManager.handleKeysUp(Array(keysToRelease))
            if stick == "left" {
                leftStickKeys = leftStickKeys.subtracting(keysToRelease)
            } else {
                rightStickKeys = rightStickKeys.subtracting(keysToRelease)
            }
        }
        
        // Press new keys (including composite directions)
        if !keysToAdd.isEmpty {
            keyboardManager.handleKeysDown(Array(keysToAdd))
            if stick == "left" {
                leftStickKeys = leftStickKeys.union(keysToAdd)
            } else {
                rightStickKeys = rightStickKeys.union(keysToAdd)
            }
        }
        
        // Debug output for composite directions
        if keysToPress.count > 1 {
            print("Composite direction detected for \(stick) stick: \(Array(keysToPress).joined(separator: " + "))")
        }
    }
    
    func releaseAllAnalogStickKeys() {
        // Release all currently pressed left stick keys
        if !leftStickKeys.isEmpty {
            keyboardManager.handleKeysUp(Array(leftStickKeys))
            leftStickKeys.removeAll()
        }
        
        // Right stick no longer uses keyboard keys, so no need to release anything for it
    }
    
    func handleRightStickMouseMovement(position: CGPoint) {
        // If stick is near center, don't send mouse movement
        let deadZone: CGFloat = 0.15
        if abs(position.x) < deadZone && abs(position.y) < deadZone {
            return
        }
        
        // Calculate the magnitude of the stick position for dynamic sensitivity
        let magnitude = sqrt(position.x * position.x + position.y * position.y)
        
        // Base sensitivity and dynamic scaling
        let baseSensitivity: CGFloat = 2.0
        let maxSensitivity: CGFloat = 8.0
        
        // Apply exponential curve for more natural acceleration
        let accelerationFactor = pow(magnitude, 1.8)
        let dynamicSensitivity = baseSensitivity + (maxSensitivity - baseSensitivity) * accelerationFactor
        
        // Calculate mouse movement deltas
        var deltaX = position.x * dynamicSensitivity
        var deltaY = position.y * dynamicSensitivity  // Use natural Y direction
        
        // Apply maximum movement limit for very large stick deflections
        let maxMovement: CGFloat = 25.0
        deltaX = max(-maxMovement, min(maxMovement, deltaX))
        deltaY = max(-maxMovement, min(maxMovement, deltaY))
        
        // Create a simulated current position for the mouse manager
        // Since we're doing relative movement, we can use any base position
        let basePosition = CGPoint(x: 100, y: 100)
        let currentPosition = CGPoint(x: basePosition.x + deltaX, y: basePosition.y + deltaY)
        
        // Set previous position to create the delta
        mouseManager.previousPosition = basePosition
        
        // Send the mouse movement
        mouseManager.handleDragChanged(currentPosition: currentPosition)
        
        // Optional: Less verbose logging for smoother experience
        if magnitude > 0.3 {  // Only log significant movements
            print("🖱️ Right stick mouse - Mag: \(String(format: "%.2f", magnitude)), X: \(String(format: "%.1f", deltaX)), Y: \(String(format: "%.1f", deltaY))")
        }
    }
    
    // MARK: - Mouse Action Helpers
    func isMouseAction(_ action: String) -> Bool {
        let mouseActions = ["Left Click", "Right Click", "Double Click", "Drag Toggle", "Scroll Up", "Scroll Down"]
        return mouseActions.contains(action)
    }
    
    func handleMouseAction(_ action: String) {
        switch action {
        case "Left Click":
            mouseManager.handleClick()
        case "Right Click":
            mouseManager.handleRightClick()
        case "Double Click":
            mouseManager.handleDoubleClick()
        case "Drag Toggle":
            mouseManager.handleDragModeToggle()
        case "Scroll Up":
            mouseManager.handleScroll(deltaX: 0, deltaY: 1)
        case "Scroll Down":
            mouseManager.handleScroll(deltaX: 0, deltaY: -1)
        default:
            print("Unknown mouse action: \(action)")
        }
    }

    /// Resolve the gesture lock action for a button based on the tracker state.
    /// Returns the appropriate gesture lock action string, or "none" if no gesture detected.
    func resolveGestureLockAction(button: String) -> String {
        guard configManager.hasGestureLock(layout: selectedLayout, button: button) else {
            return PresetConstants.gestureLockActionNone
        }

        let gestureConfig = configManager.getGestureLockConfig(layout: selectedLayout, button: button)
        // Build a synthetic module with gesture lock config for the analyzer
        let module = GamepadModule(
            id: button,
            type: .button,
            anchorX: 0,
            anchorY: 0,
            scale: 1.0,
            zIndex: 0,
            keyboardHoldLock: gestureConfig.holdLock || gestureConfig.turbo,
            gestureLock: nil
        )

        // Use the tracker's current state
        if gestureConfig.turbo {
            // For turbo mode, classify the current swipe
            let result = GestureLockAnalyzer.classifyDiagonalSlot(
                dx: gestureLockTracker.highlightedQuadrant != nil ? 15 : 0,
                dy: gestureLockTracker.highlightedQuadrant != nil ? -15 : 0,
                density: UIScreen.main.scale,
                rMinDp: PresetConstants.diagonalRMinDp,
                rCancelDp: PresetConstants.diagonalRCancelDp
            )
            if let slotKey = result, slotKey != gestureLockResultCancel {
                return GestureLockAnalyzer.resolvedActionForSlot(module: module, slotKey: slotKey)
            }
        }

        return gestureConfig.holdLock ? PresetConstants.gestureLockActionHoldLock : PresetConstants.gestureLockActionNone
    }
}

// MARK: - Helper Extensions
extension GamepadView {
    
    // MARK: - Computed Properties
    var isAnyEditModeActive: Bool {
        isPositionEditMode || isKeyMappingMode
    }
    
    // MARK: - Helper Functions
    func buttonWidth(for layout: GamepadLayout) -> CGFloat {
        switch layout {
        case .xbox, .playStation:
            return 80 // Wider buttons for Xbox and PlayStation layouts
        case .nes:
            return 50 // Standard width for NES layout
        case .simple:
            return 60 // Medium width for Simple layout
        }
    }
    
    // MARK: - Position Management
    func resetComponentPositions() {
        print("🔄 Resetting component positions for layout: \(selectedLayout.rawValue)")
        isResetting = true
        
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            configManager.resetLayoutPositions(layout: selectedLayout)
        }
        
        // Reset the visual feedback after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isResetting = false
            }
        }
    }
}

#Preview {
    GamepadView(
        orientationManager: OrientationManager(), 
        keyboardManager: KeyboardManager(bleManager: BLEManager()),
        mouseManager: MouseManager(bleManager: BLEManager()),
        selectedLayout: .xbox,
        isEditMode: false
    )
}
