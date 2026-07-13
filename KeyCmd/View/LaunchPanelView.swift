//
//  LaunchPanelView.swift
//  KeyCmd
//
//  Created by GitHub Copilot on 2026/2/25.
//

import SwiftUI

struct LaunchPanelView: View {
    @ObservedObject var launchPanelManager: LaunchPanelManager
    @State private var selectedMode: ViewType = .keyboardMouseBasic
    @State private var rememberChoice = true
    
    var body: some View {
        ZStack {
            // Background
            Color(UIColor.systemBackground)
                .ignoresSafeArea()
            
            ScrollView {
            VStack(spacing: 30) {
                // Header
                VStack(spacing: 12) {
                    Text("Welcome to KeyCmd")
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
                            isSelected: selectedMode == .keyboardMouseBasic,
                            action: { selectedMode = .keyboardMouseBasic }
                        )

                        ModeCard(
                            title: "Keyboard & Mouse Pro",
                            icon: "keyboard.badge.ellipsis",
                            isSelected: selectedMode == .keyboardMousePro,
                            action: { selectedMode = .keyboardMousePro }
                        )
                    }

                    // Second row
                    HStack(spacing: 12) {
                        ModeCard(
                            title: "Gamepad",
                            icon: "gamecontroller",
                            isSelected: selectedMode == .gamepad,
                            action: { selectedMode = .gamepad }
                        )

                        ModeCard(
                            title: "Numpad",
                            icon: "grid.circle",
                            isSelected: selectedMode == .numpad,
                            action: { selectedMode = .numpad }
                        )
                    }

                    // Third row
                    HStack(spacing: 12) {
                        ModeCard(
                            title: "Shortcut Hub",
                            icon: "square.grid.2x2",
                            isSelected: selectedMode == .shortcutHub,
                            action: { selectedMode = .shortcutHub }
                        )

                        ModeCard(
                            title: "Macros",
                            icon: "square.and.pencil",
                            isSelected: selectedMode == .macros,
                            isBeta: true,
                            action: { selectedMode = .macros }
                        )
                    }

                    // Fourth row
                    HStack(spacing: 12) {
                        ModeCard(
                            title: "Voice Input",
                            icon: "mic.circle",
                            isSelected: selectedMode == .voiceInput,
                            isBeta: true,
                            action: { selectedMode = .voiceInput }
                        )

                        Spacer()
                    }
                }
                .padding(.horizontal, 16)
                
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
            } // ScrollView
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onAppear {
            selectedMode = launchPanelManager.selectedMode
        }
    }
}

struct ModeCard: View {
    let title: LocalizedStringKey
    let icon: String
    let isSelected: Bool
    let isBeta: Bool
    let action: () -> Void
    
    init(title: LocalizedStringKey, icon: String, isSelected: Bool, isBeta: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.isSelected = isSelected
        self.isBeta = isBeta
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 28))
                        .foregroundColor(isSelected ? .white : .blue)
                    
                    HStack(spacing: 4) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(isSelected ? .white : .primary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                        
                        if isBeta {
                            Image(systemName: "flask.fill")
                                .font(.system(size: 11))
                                .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 110)
                .background(isSelected ? Color.blue : Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    LaunchPanelView(launchPanelManager: LaunchPanelManager())
}
