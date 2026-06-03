//
//  IMEView.swift
//  KeyMod
//
//  IME tab: type text and send it as HID keystrokes via the keyboard manager.

import SwiftUI

struct IMEView: View {
    @ObservedObject var keyboardManager: KeyboardManager

    @State private var inputText: String = ""
    @State private var clearedText: String = ""
    @State private var keyboardHeight: CGFloat = 0
    @FocusState private var textFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Text area
            ZStack(alignment: .topLeading) {
                // Placeholder
                if inputText.isEmpty {
                    Text("Type text, then send (ASCII-friendly for HID).")
                        .foregroundColor(Color(UIColor.placeholderText))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $inputText)
                    .focused($textFieldFocused)
                    .padding(10)
                    .background(Color.clear)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .onAppear {
                        UITextView.appearance().backgroundColor = .clear
                    }
            }
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .frame(maxHeight: .infinity)

            // MARK: - Bottom buttons (float above system keyboard)
            HStack(spacing: 12) {
                // Clear
                Button(action: clearText) {
                    Label("Clear", systemImage: "trash")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(inputText.isEmpty)

                // Undo clear
                Button(action: undoClear) {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(clearedText.isEmpty)

                // Send
                Button(action: sendText) {
                    Label("Send", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(inputText.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(
                Color(UIColor.secondarySystemBackground)
                    .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: -2)
            )
        }
        .padding(.bottom, keyboardHeight)
        .animation(.easeOut(duration: 0.25), value: keyboardHeight)
        .onReceive(
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
        ) { notification in
            guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let safeBottom = UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.windows.first { $0.isKeyWindow } }
                .first?.safeAreaInsets.bottom ?? 0
            keyboardHeight = max(0, frame.height - safeBottom)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
        ) { _ in
            keyboardHeight = 0
        }
        // Dismiss keyboard when tapping outside the TextEditor
        .onTapGesture {
            textFieldFocused = false
        }
    }

    // MARK: - Actions

    private func clearText() {
        clearedText = inputText
        inputText = ""
    }

    private func undoClear() {
        inputText = clearedText
        clearedText = ""
    }

    private func sendText() {
        guard !inputText.isEmpty else { return }
        textFieldFocused = false
        let textToSend = inputText
        // Run on background thread to avoid blocking UI during HID sending
        DispatchQueue.global(qos: .userInitiated).async {
            keyboardManager.handleTextInputWithTokens(textToSend)
        }
    }
}
