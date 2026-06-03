//
//  GamepadModuleContextMenu.swift
//  KeyMod
//
//  Centered context dialog for gamepad modules — matches Android's MaterialAlertDialog items list.
//  Shown when tapping the gear icon in edit mode.
//

import SwiftUI

struct GamepadModuleContextMenu: View {
    let moduleId: String
    let moduleDisplayName: String
    let showConfigure: Bool
    let showReorder: Bool
    let showRemove: Bool
    let onConfigure: () -> Void
    let onBringToFront: () -> Void
    let onSendToBack: () -> Void
    let onRemove: () -> Void

    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Title
            Text(moduleDisplayName)
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)
                .multilineTextAlignment(.center)

            Divider()

            // Menu items
            VStack(spacing: 0) {
                if showConfigure {
                    menuButton("Configure control...") { onConfigure() }
                    Divider()
                }

                if showReorder {
                    menuButton("Bring to front") { onBringToFront() }
                    Divider()
                    menuButton("Send to back") { onSendToBack() }
                    Divider()
                }

                if showRemove {
                    menuButton("Remove", foreground: .red) { onRemove() }
                }
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .frame(width: 240)
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .animation(.easeInOut(duration: 0.2), value: isPresented)
    }

    private func menuButton(_ title: String, foreground: Color = .primary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body)
                .foregroundColor(foreground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }
}
