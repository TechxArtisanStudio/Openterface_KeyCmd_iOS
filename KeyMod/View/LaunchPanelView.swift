//
//  LaunchPanelView.swift
//  KeyMod
//
//  Created by GitHub Copilot on 2026/2/25.
//

import SwiftUI

struct LaunchPanelView: View {
    @ObservedObject var launchPanelManager: LaunchPanelManager
    @State private var selectedMode: ViewType = .keyboardMouse
    @State private var rememberChoice = true
    
    var body: some View {
        ZStack {
            // Background
            Color(UIColor.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                // Header
                VStack(spacing: 12) {
                    Text("Welcome to KeyMod")
                        .font(.system(size: 32, weight: .bold))
                    Text("Choose your preferred mode")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 40)
                
                // Mode Selection Grid
                VStack(spacing: 16) {
                    // First row
                    HStack(spacing: 12) {
                        ModeCard(
                            title: "Keyboard & Mouse",
                            icon: "keyboard",
                            isSelected: selectedMode == .keyboardMouse,
                            action: { selectedMode = .keyboardMouse }
                        )
                        
                        ModeCard(
                            title: "Gamepad",
                            icon: "gamecontroller",
                            isSelected: selectedMode == .gamepad,
                            action: { selectedMode = .gamepad }
                        )
                    }
                    
                    // Second row
                    HStack(spacing: 12) {
                        ModeCard(
                            title: "Numpad",
                            icon: "grid.circle",
                            isSelected: selectedMode == .numpad,
                            action: { selectedMode = .numpad }
                        )
                        
                        ModeCard(
                            title: "Blender",
                            icon: "cube.box",
                            isSelected: selectedMode == .blenderShortcuts,
                            action: { selectedMode = .blenderShortcuts }
                        )
                    }
                    
                    // Third row
                    HStack(spacing: 12) {
                        ModeCard(
                            title: "KiCAD",
                            icon: "cpu",
                            isSelected: selectedMode == .kicadShortcuts,
                            action: { selectedMode = .kicadShortcuts }
                        )
                        
                        ModeCard(
                            title: "Macros",
                            icon: "square.and.pencil",
                            isSelected: selectedMode == .macros,
                            action: { selectedMode = .macros }
                        )
                    }
                    
                    // Fourth row - Voice Input
                    HStack(spacing: 12) {
                        Spacer()
                        
                        ModeCard(
                            title: "Voice Input",
                            icon: "mic.circle",
                            isSelected: selectedMode == .voiceInput,
                            action: { selectedMode = .voiceInput }
                        )
                        .frame(maxWidth: 180)
                        
                        Spacer()
                    }
                }
                .padding(.horizontal, 16)
                
                Spacer()
                
                // Remember Choice Toggle
                HStack(spacing: 12) {
                    Image(systemName: rememberChoice ? "checkmark.square.fill" : "square")
                        .font(.system(size: 20))
                        .foregroundColor(rememberChoice ? .blue : .gray)
                    
                    Text("Remember this choice and auto-enter this mode")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.primary)
                    
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        rememberChoice.toggle()
                    }
                }
                .padding(.horizontal, 16)
                
                // Buttons
                VStack(spacing: 12) {
                    // Start Button
                    Button(action: {
                        if rememberChoice {
                            launchPanelManager.confirmSelection(selectedMode)
                        } else {
                            launchPanelManager.skipLaunchPanel()
                        }
                    }) {
                        HStack {
                            Image(systemName: "play.fill")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Start")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    
                    // Skip Button
                    Button(action: {
                        launchPanelManager.skipLaunchPanel()
                    }) {
                        Text("Skip for now")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color(UIColor.secondarySystemBackground))
                            .foregroundColor(.blue)
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}

struct ModeCard: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundColor(isSelected ? .white : .blue)
                
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isSelected ? .white : .primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 110)
            .background(isSelected ? Color.blue : Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    LaunchPanelView(launchPanelManager: LaunchPanelManager())
}
