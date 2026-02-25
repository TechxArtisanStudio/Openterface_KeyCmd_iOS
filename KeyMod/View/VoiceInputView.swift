//
//  VoiceInputView.swift
//  KeyMod
//
//  Created on 2026/2/25.
//

import SwiftUI
import UIKit

// MARK: - Bounded UITextView wrapper
// SwiftUI's TextEditor uses a UITextView whose UIKit layer can paint outside
// its SwiftUI frame. Wrapping it in a clipsToBounds container UIView and
// manually setting the text view's frame in layoutSubviews prevents this.
private final class BoundedTextViewContainer: UIView {
    let textView = UITextView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        textView.clipsToBounds = true
        textView.contentInsetAdjustmentBehavior = .never
        textView.insetsLayoutMarginsFromSafeArea = false
        textView.backgroundColor = UIColor.systemBackground
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        textView.isScrollEnabled = true
        textView.isEditable = true
        textView.isSelectable = true

        // Keyboard toolbar with Done button
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        let spacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let done = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(dismissKeyboard))
        toolbar.setItems([spacer, done], animated: false)
        textView.inputAccessoryView = toolbar

        addSubview(textView)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func dismissKeyboard() {
        textView.resignFirstResponder()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        textView.frame = bounds
        print("📦 BoundedTextViewContainer.layoutSubviews: bounds=\(bounds), textView.frame=\(textView.frame)")
    }
}

private struct BoundedTextView: UIViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeUIView(context: Context) -> BoundedTextViewContainer {
        let container = BoundedTextViewContainer()
        container.textView.delegate = context.coordinator
        return container
    }

    func updateUIView(_ container: BoundedTextViewContainer, context: Context) {
        if container.textView.text != text {
            container.textView.text = text
        }
        container.textView.backgroundColor = UIColor.systemBackground
    }

    class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String
        init(text: Binding<String>) { _text = text }
        func textViewDidChange(_ textView: UITextView) { text = textView.text }
    }
}

// MARK: - VoiceInputView
struct VoiceInputView: View {
    let keyboardManager: KeyboardManager

    @StateObject private var voiceManager = VoiceInputManager()
    @State private var isSending = false

    var body: some View {
        VStack(spacing: 0) {
            textArea
            Divider()
            actionRow
            Spacer()
        }
        .background(Color(UIColor.systemBackground))
    }

    // MARK: - Text Area

    private var textArea: some View {
        ZStack(alignment: .topLeading) {
            BoundedTextView(text: $voiceManager.transcribedText)

            if voiceManager.transcribedText.isEmpty {
                Text(voiceManager.isListening
                     ? "Speak now…"
                     : "Press the mic button and speak.\nYour speech will appear here.")
                    .foregroundColor(Color(UIColor.placeholderText))
                    .font(.body)
                    .padding(.horizontal, 12)
                    .padding(.top, 14)
                    .allowsHitTesting(false)
            }

            if let error = voiceManager.errorMessage {
                VStack {
                    Spacer()
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            GeometryReader { geo in
                Color(UIColor.systemBackground)
                    .onAppear {
                        print("🎙️ VoiceInputView textArea frame: origin=\(geo.frame(in: .global).origin) size=\(geo.size)")
                    }
                    .onChange(of: geo.size) { size in
                        print("🎙️ VoiceInputView textArea size changed: \(size)")
                    }
            }
        )
    }

    private var statusBadge: some View {
        Group {
            if voiceManager.isListening {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .scaleEffect(voiceManager.isListening ? 1.3 : 1.0)
                        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                                   value: voiceManager.isListening)
                    Text("Listening…")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            } else {
                Text(voiceManager.permissionGranted ? "Ready" : "No Permission")
                    .font(.caption)
                    .foregroundColor(voiceManager.permissionGranted ? .secondary : .orange)
            }
        }
    }

    // MARK: - Action Row

    private var actionRow: some View {
        HStack(spacing: 20) {
            // Clear button
            Button(action: {
                voiceManager.clearText()
                voiceManager.errorMessage = nil
            }) {
                Label("Clear", systemImage: "trash")
                    .font(.subheadline)
                    .foregroundColor(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(10)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(voiceManager.transcribedText.isEmpty && voiceManager.errorMessage == nil)

            Spacer()

            // Microphone button with status label below
            VStack(spacing: 6) {
                micButton
                statusBadge
            }

            Spacer()

            // Send button
            Button(action: sendText) {
                Label(isSending ? "Sending…" : "Send", systemImage: isSending ? "hourglass" : "paperplane.fill")
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(voiceManager.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? Color.blue.opacity(0.4)
                                : Color.blue)
                    .cornerRadius(10)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(voiceManager.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(UIColor.secondarySystemBackground))
    }

    // MARK: - Mic Button

    private var micButton: some View {
        Button(action: {
            voiceManager.toggleListening()
        }) {
            ZStack {
                // Pulsing ring when listening
                if voiceManager.isListening {
                    Circle()
                        .stroke(Color.red.opacity(0.3), lineWidth: 4)
                        .frame(width: 76, height: 76)
                        .scaleEffect(voiceManager.isListening ? 1.15 : 1.0)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                                   value: voiceManager.isListening)
                }
                Circle()
                    .fill(voiceManager.isListening ? Color.red : Color.blue)
                    .frame(width: 64, height: 64)
                    .shadow(color: voiceManager.isListening
                            ? Color.red.opacity(0.4)
                            : Color.blue.opacity(0.3),
                            radius: 8)
                Image(systemName: voiceManager.isListening ? "stop.fill" : "mic.fill")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!voiceManager.permissionGranted)
        .opacity(voiceManager.permissionGranted ? 1.0 : 0.5)
        .animation(.easeInOut(duration: 0.2), value: voiceManager.isListening)
    }

    // MARK: - Send

    private func sendText() {
        let text = voiceManager.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // Stop listening before sending
        if voiceManager.isListening {
            voiceManager.stopListening()
        }

        isSending = true
        keyboardManager.handleTextInput(text)

        // Give a short visual feedback then reset sending state
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isSending = false
            voiceManager.clearText()
        }
    }
}


#Preview {
    VoiceInputView(keyboardManager: KeyboardManager(bleManager: BLEManager()))
}
