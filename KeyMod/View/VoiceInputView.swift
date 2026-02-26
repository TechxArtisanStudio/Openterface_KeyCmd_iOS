//
//  VoiceInputView.swift
//  KeyMod
//
//  Created on 2026/2/25.
//

import SwiftUI
import UIKit

// MARK: - History Item Model
struct HistoryItem: Codable, Equatable {
    let text: String
    let timestamp: Date
    
    static func == (lhs: HistoryItem, rhs: HistoryItem) -> Bool {
        lhs.text == rhs.text && lhs.timestamp == rhs.timestamp
    }
}

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
    @ObservedObject private var aiSettings = AISettings.shared
    @State private var isSending = false
    @State private var sentHistory: [HistoryItem] = []
    @State private var historyHeight: CGFloat = 150
    @State private var lastDragValue: CGFloat = 0
    
    // AI Refinement states
    @State private var isRefining = false
    @State private var refinedText: String?
    @State private var refinementError: String?

    private let historyKey = "VoiceInputHistory"

    var body: some View {
        VStack(spacing: 0) {
            textArea
                .frame(maxHeight: .infinity)
            
            // AI Refinement inline display
            if refinedText != nil || isRefining || refinementError != nil {
                Divider()
                refinementInlineDisplay
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
            }
            
            if !sentHistory.isEmpty {
                Divider()
                historySection
                    .frame(height: historyHeight)
            }
            Divider()
            actionRow
            Spacer()
        }
        .background(Color(UIColor.systemBackground))
        .onAppear {
            loadHistory()
        }
        .onChange(of: sentHistory) { _ in
            saveHistory()
        }
        .onChange(of: voiceManager.isListening) { isListening in
            // Auto-refine when user finishes speaking (isListening becomes false)
            if !isListening && aiSettings.isEnabled {
                let text = voiceManager.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty && refinedText == nil && !isRefining {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        refineText()
                    }
                }
            }
        }
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey) else { return }
        if let decodedHistory = try? JSONDecoder().decode([HistoryItem].self, from: data) {
            sentHistory = decodedHistory
        }
    }

    private func saveHistory() {
        if let encodedData = try? JSONEncoder().encode(sentHistory) {
            UserDefaults.standard.set(encodedData, forKey: historyKey)
        }
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
        .background(Color(UIColor.systemBackground))
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
                refinedText = nil
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

    // MARK: - History Section

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Resize handle at top
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.4))
                        .frame(width: 40, height: 4)
                    Spacer()
                }
                .padding(.vertical, 6)
                .background(Color(UIColor.systemBackground))
                .gesture(
                    DragGesture()
                        .onChanged { gesture in
                            let delta = lastDragValue - gesture.translation.height
                            let newHeight = historyHeight + delta
                            historyHeight = max(80, min(300, newHeight))
                            lastDragValue = gesture.translation.height
                        }
                        .onEnded { _ in
                            lastDragValue = 0
                        }
                )
                .contentShape(Rectangle())
                Divider()
            }
            
            HStack {
                Text("History")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                Spacer()
                Button(action: { sentHistory.removeAll() }) {
                    Text("Clear All")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.trailing, 16)
                .padding(.top, 8)
            }
            List {
                ForEach(sentHistory.indices.reversed(), id: \.self) { index in
                    historyRow(item: sentHistory[index], index: index)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowSeparator(.hidden)
                }
                .onDelete { offsets in
                    let actualIndices = offsets.map { sentHistory.count - 1 - $0 }
                    for idx in actualIndices.sorted(by: >) {
                        if idx >= 0 && idx < sentHistory.count {
                            sentHistory.remove(at: idx)
                        }
                    }
                }
            }
            .listStyle(.inset)
            .frame(maxHeight: .infinity)
        }
    }

    private func historyRow(item: HistoryItem, index: Int) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.text)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(3)
                Text(formatTimestamp(item.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                Button(action: {
                    voiceManager.transcribedText = item.text
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                        Text("Edit")
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: {
                    resendText(item.text)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "paperplane.fill")
                        Text("Resend")
                    }
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.blue)
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.vertical, 8)
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // MARK: - AI Refinement Inline Display
    
    private var refinementInlineDisplay: some View {
        VStack(spacing: 12) {
            // Loading state
            if isRefining {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8, anchor: .center)
                    Text("AI is refining your text…")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Error state
            if let error = refinementError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Refinement Failed")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                        Text(error)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: {
                        refinedText = nil
                        refinementError = nil
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Success state
            if let refined = refinedText, refinementError == nil {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("✨ AI Refined Text")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                        Text(refined)
                            .font(.body)
                            .lineLimit(3)
                            .foregroundColor(.primary)
                    }
                    Spacer()
                    
                    // Accept button (checkmark)
                    Button(action: {
                        voiceManager.transcribedText = refined
                        refinedText = nil
                        refinementError = nil
                    }) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.green)
                    }
                    
                    // Reject button (X)
                    Button(action: {
                        refinedText = nil
                        refinementError = nil
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.red)
                    }
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - AI Refinement
    
    private func refineText() {
        let text = voiceManager.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        isRefining = true
        refinedText = nil
        refinementError = nil
        
        AITextRefinementManager.shared.refineText(input: text) { result in
            DispatchQueue.main.async {
                isRefining = false
                switch result {
                case .success(let refined):
                    refinedText = refined
                    refinementError = nil
                    LogManager.shared.log("✅ Text refinement successful", category: "VoiceInput", level: .info)
                case .failure(let error):
                    refinedText = nil
                    refinementError = error.localizedDescription
                    LogManager.shared.log("❌ Text refinement failed: \(error.localizedDescription)", category: "VoiceInput", level: .error)
                }
            }
        }
    }

    // MARK: - Send

    private func sendText() {
        let text = voiceManager.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if voiceManager.isListening { voiceManager.stopListening() }

        isSending = true
        keyboardManager.handleTextInput(text)

        // Add to history (avoid duplicating the most recent entry)
        let newItem = HistoryItem(text: text, timestamp: Date())
        if sentHistory.last?.text != text {
            sentHistory.append(newItem)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isSending = false
            voiceManager.clearText()
        }
    }

    private func resendText(_ text: String) {
        if voiceManager.isListening { voiceManager.stopListening() }
        keyboardManager.handleTextInput(text)
    }
}


#Preview {
    VoiceInputView(keyboardManager: KeyboardManager(bleManager: BLEManager()))
}
