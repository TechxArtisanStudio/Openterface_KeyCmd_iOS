//
//  ClipboardStatusView.swift
//  KeyMod
//
//  Shows current clipboard status and monitoring information
//

import SwiftUI

struct ClipboardStatusView: View {
    @ObservedObject var clipboardManager: ClipboardManager
    @ObservedObject var keyboardManager: KeyboardManager
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Status")) {
                    HStack {
                        Text("Monitoring Active")
                        Spacer()
                        Circle()
                            .fill(clipboardManager.isMonitoring ? Color.green : Color.red)
                            .frame(width: 10, height: 10)
                    }
                }
                
                Section(header: Text("Current Clipboard Content")) {
                    if clipboardManager.lastClipboardContent.isEmpty {
                        Text("(Empty)")
                            .foregroundColor(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(clipboardManager.lastClipboardContent)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(5)
                            
                            HStack(spacing: 8) {
                                Button(action: {
                                    UIPasteboard.general.string = clipboardManager.lastClipboardContent
                                }) {
                                    Label("Copy", systemImage: "doc.on.doc")
                                        .font(.caption)
                                }
                                .foregroundColor(.blue)
                                
                                Spacer()
                                
                                Text("\(clipboardManager.lastClipboardContent.count) characters")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                Section(header: Text("Actions")) {
                    Button(action: {
                        clipboardManager.lastClipboardContent = clipboardManager.getClipboardContent()
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Refresh")
                        }
                        .foregroundColor(.blue)
                    }
                    
                    Button(action: {
                        clipboardManager.clearClipboard()
                    }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Clear Clipboard")
                        }
                        .foregroundColor(.red)
                    }
                    
                    if !clipboardManager.lastClipboardContent.isEmpty {
                        Button(action: {
                            clipboardManager.sendClipboardToTarget(keyboardManager)
                        }) {
                            HStack {
                                Image(systemName: "paperplane")
                                Text("Send to Target")
                            }
                            .foregroundColor(.green)
                        }
                    }
                }
                
                Section(header: Text("Information")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Clipboard Detection:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Automatically detects when new text is copied to the clipboard. When new content is detected, a prompt will appear asking if you want to send it to the target device.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Clipboard Info")
            .navigationBarItems(
                trailing: Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }
}

#Preview {
    ClipboardStatusView(
        clipboardManager: ClipboardManager(),
        keyboardManager: KeyboardManager(bleManager: BLEManager())
    )
}
