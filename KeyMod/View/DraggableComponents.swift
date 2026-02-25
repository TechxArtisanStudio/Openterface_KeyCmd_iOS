//
//  DraggableComponents.swift
//  KeyMod
//
//  Created by System on 2025/7/17.
//

import SwiftUI

// MARK: - Draggable Component Wrapper
struct DraggableComponent<Content: View>: View {
    let content: Content
    let componentName: String
    let layout: GamepadLayout
    @ObservedObject var configManager: GamepadConfigManager
    let isPositionEditMode: Bool
    let isKeyMappingMode: Bool
    let geometry: GeometryProxy
    let onLongPress: (() -> Void)?
    @State private var currentOffset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero
    @State private var isDragging: Bool = false
    
    init(
        componentName: String,
        layout: GamepadLayout,
        configManager: GamepadConfigManager,
        isPositionEditMode: Bool,
        isKeyMappingMode: Bool,
        geometry: GeometryProxy,
        onLongPress: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.componentName = componentName
        self.layout = layout
        self.configManager = configManager
        self.isPositionEditMode = isPositionEditMode
        self.isKeyMappingMode = isKeyMappingMode
        self.geometry = geometry
        self.onLongPress = onLongPress
        self.content = content()
    }
    
    var body: some View {
        content
            .offset(currentOffset)
            .scaleEffect(isDragging ? 1.1 : 1.0)
            .opacity(isDragging ? 0.8 : 1.0)
            .overlay(
                isPositionEditMode && !isDragging ? 
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.orange.opacity(0.5), lineWidth: 2)
                    .background(Color.orange.opacity(0.1))
                : nil
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDragging)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentOffset)
            .onAppear {
                updateOffsetFromSavedPosition()
            }
            .onChange(of: layout) { _ in
                updateOffsetFromSavedPosition()
            }
            .onChange(of: configManager.layoutPositions) { _ in
                updateOffsetFromSavedPosition()
            }
            .modifier(
                ComponentGestureModifier(
                    componentName: componentName,
                    isPositionEditMode: isPositionEditMode,
                    isDragging: $isDragging,
                    currentOffset: $currentOffset,
                    baseOffset: $baseOffset,
                    configManager: configManager,
                    layout: layout,
                    onLongPress: openKeyMapping
                )
            )
    }
    
    private func updateOffsetFromSavedPosition() {
        let savedPosition = configManager.getComponentPosition(layout: layout, component: componentName)
        let newOffset = CGSize(width: savedPosition.x, height: savedPosition.y)
        
        print("🔄 DraggableComponent \(componentName): Updating position to (\(savedPosition.x), \(savedPosition.y))")
        
        // Use animation when updating from saved position (like reset)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            baseOffset = newOffset
            currentOffset = newOffset
        }
    }
    
    private func openKeyMapping() {
        print("🔧 Long press detected on \(componentName), opening key mapping")
        onLongPress?()
    }
}

// MARK: - ComponentGestureModifier
struct ComponentGestureModifier: ViewModifier {
    let componentName: String
    let isPositionEditMode: Bool
    @Binding var isDragging: Bool
    @Binding var currentOffset: CGSize
    @Binding var baseOffset: CGSize
    let configManager: GamepadConfigManager
    let layout: GamepadLayout
    let onLongPress: () -> Void
    
    func body(content: Content) -> some View {
        if isPositionEditMode && componentName != "ActionButtons" {
            content
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if !isDragging {
                                isDragging = true
                            }
                            currentOffset = CGSize(
                                width: baseOffset.width + value.translation.width,
                                height: baseOffset.height + value.translation.height
                            )
                        }
                        .onEnded { value in
                            isDragging = false
                            
                            // Save the final position
                            let finalOffset = CGSize(
                                width: baseOffset.width + value.translation.width,
                                height: baseOffset.height + value.translation.height
                            )
                            
                            let newPosition = ComponentPosition(
                                x: finalOffset.width,
                                y: finalOffset.height
                            )
                            configManager.setComponentPosition(layout: layout, component: componentName, position: newPosition)
                            
                            // Update base offset for next drag
                            baseOffset = finalOffset
                            currentOffset = finalOffset
                        }
                )
        } else {
            content
        }
    }
}
