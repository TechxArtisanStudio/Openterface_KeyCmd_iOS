//
//  ClipboardPromptView.swift
//  KeyMod
//
//  Displays a prompt when new clipboard content is detected
//

import SwiftUI

struct ClipboardPromptView: View {
    @ObservedObject var clipboardManager: ClipboardManager
    @ObservedObject var keyboardManager: KeyboardManager
    
    var body: some View {
        ZStack {
            if clipboardManager.showClipboardPrompt {
                // Semi-transparent background
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // Tap outside dialog does nothing (buttons handle dismiss)
                    }
                
                // Alert dialog
                VStack(spacing: 16) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Clipboard Content Detected")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text("Send to target device?")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Preview of clipboard content
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Preview:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(clipboardManager.pendingClipboardContent)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(3)
                            .padding(8)
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(6)
                            .foregroundColor(.primary)
                    }
                    
                    // Action buttons
                    HStack(spacing: 12) {
                        Button(action: {
                            clipboardManager.dismissClipboardPrompt()
                        }) {
                            Text("Dismiss")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color(UIColor.secondarySystemBackground))
                                .foregroundColor(.primary)
                                .cornerRadius(8)
                        }
                        
                        Button(action: {
                            clipboardManager.sendClipboardToTarget(keyboardManager)
                        }) {
                            Text("Send")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(16)
                .background(Color(UIColor.systemBackground))
                .cornerRadius(12)
                .shadow(radius: 8)
                .padding(16)
            }
        }
    }
}

#Preview {
    ClipboardPromptView(
        clipboardManager: ClipboardManager(),
        keyboardManager: KeyboardManager(bleManager: BLEManager())
    )
}
