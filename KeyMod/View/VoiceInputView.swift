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
    
    // Get selected text or nil if none selected
    func getSelectedText() -> String? {
        guard let selectedRange = textView.selectedTextRange else { return nil }
        return textView.text(in: selectedRange)
    }
    
    // Get selected text range
    func getSelectedRange() -> NSRange? {
        guard let selectedRange = textView.selectedTextRange else { return nil }
        let location = textView.offset(from: textView.beginningOfDocument, to: selectedRange.start)
        let length = textView.offset(from: selectedRange.start, to: selectedRange.end)
        return NSRange(location: location, length: length)
    }
    
    // Replace text at range
    func replaceText(at range: NSRange, with newText: String) {
        guard let swiftRange = Range(range, in: textView.text) else { return }
        textView.text.replaceSubrange(swiftRange, with: newText)
    }
    
    // Highlight text at range with red color
    func highlightText(at range: NSRange, withColor color: UIColor) {
        let attributedString = NSMutableAttributedString(string: textView.text)
        attributedString.addAttribute(.foregroundColor, value: color, range: range)
        attributedString.addAttribute(.font, value: textView.font ?? UIFont.preferredFont(forTextStyle: .body), range: NSRange(location: 0, length: attributedString.length))
        textView.attributedText = attributedString
    }
    
    // Clear text highlighting (restore to default black text)
    func clearHighlighting() {
        let attributedString = NSMutableAttributedString(string: textView.text)
        attributedString.addAttribute(.foregroundColor, value: UIColor.label, range: NSRange(location: 0, length: attributedString.length))
        attributedString.addAttribute(.font, value: textView.font ?? UIFont.preferredFont(forTextStyle: .body), range: NSRange(location: 0, length: attributedString.length))
        textView.attributedText = attributedString
    }

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
    var onSelectionChange: ((String?, NSRange?) -> Void)? = nil
    var onContainerCreated: ((BoundedTextViewContainer) -> Void)? = nil

    func makeCoordinator() -> Coordinator { 
        Coordinator(text: $text, onSelectionChange: onSelectionChange)
    }

    func makeUIView(context: Context) -> BoundedTextViewContainer {
        let container = BoundedTextViewContainer()
        container.textView.delegate = context.coordinator
        context.coordinator.container = container
        onContainerCreated?(container)
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
        var onSelectionChange: ((String?, NSRange?) -> Void)?
        var container: BoundedTextViewContainer?
        
        init(text: Binding<String>, onSelectionChange: ((String?, NSRange?) -> Void)? = nil) {
            _text = text
            self.onSelectionChange = onSelectionChange
        }
        
        func textViewDidChange(_ textView: UITextView) { 
            text = textView.text
        }
        
        func textViewDidChangeSelection(_ UITextView: UITextView) {
            let selectedText = container?.getSelectedText()
            let selectedRange = container?.getSelectedRange()
            onSelectionChange?(selectedText, selectedRange)
        }
    }
}

/// Shows icon + text when space allows; degrades to icon-only on narrow layouts.
/// Compatible with iOS 15+.
private struct AdaptiveLabel: View {
    let systemImage: String
    let text: String

    var body: some View {
        if #available(iOS 16.0, *) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 3) {
                    Image(systemName: systemImage)
                    Text(text).lineLimit(1)
                }
                Image(systemName: systemImage)
            }
        } else {
            HStack(spacing: 3) {
                Image(systemName: systemImage)
                Text(text)
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}

// MARK: - VoiceInputView
struct VoiceInputView: View {
    let keyboardManager: KeyboardManager

    @StateObject private var voiceManager = VoiceInputManager()
    @ObservedObject private var aiSettings = AISettings.shared
    @ObservedObject private var modelManager = WhisperModelManager.shared
    @StateObject private var macroManager: MacroManager
    @State private var isSending = false
    @State private var sentHistory: [HistoryItem] = []
    @State private var historyHeight: CGFloat = 150
    @State private var lastDragValue: CGFloat = 0
    
    // AI Refinement states
    @State private var isRefining = false
    @State private var refinedText: String?
    @State private var refinementError: String?
    @State private var selectedText: String?
    @State private var selectedTextRange: NSRange?
    @State private var textViewContainer: BoundedTextViewContainer?
    @State private var refiningSelectedOnly = false  // Track if refining selected or all text
    @State private var existingWording: String?  // Marked existing wording for refinement
    @State private var existingWordingRange: NSRange?  // Range of existing wording
    @State private var isRefiningWithExistingWording = false  // Track if in "refine with existing" mode
    @State private var showSelectionMenu = false  // Context menu visibility
    
    // Macro save states
    @State private var showMacroSaveDialog = false
    @State private var macroNameInput = ""
    @State private var selectedHistoryItemForMacro: HistoryItem?

    private let historyKey = "VoiceInputHistory"

    init(keyboardManager: KeyboardManager) {
        self.keyboardManager = keyboardManager
        _macroManager = StateObject(wrappedValue: MacroManager(keyboardManager: keyboardManager))
    }

    var body: some View {
        VStack(spacing: 0) {
            textArea
                .frame(maxHeight: .infinity)
            
            // Existing Wording Mode Status
            if isRefiningWithExistingWording && !(existingWording?.isEmpty ?? true) {
                Divider()
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("📝 Awaiting Voice Input")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                        Text(existingWording ?? "")
                            .font(.caption)
                            .lineLimit(2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: {
                        textViewContainer?.clearHighlighting()
                        existingWording = nil
                        existingWordingRange = nil
                        isRefiningWithExistingWording = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.05))
            }
            
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
            // Auto-refine when user finishes speaking.
            // Guard: skip if Whisper is still processing audio asynchronously.
            if !isListening && !voiceManager.isProcessingAudio && aiSettings.isEnabled {
                let text = voiceManager.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty && refinedText == nil && !isRefining {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        refineText()
                    }
                }
            }
        }
        .onChange(of: voiceManager.isProcessingAudio) { isProcessing in
            // For WhisperEngine: trigger refinement once async inference finishes
            // (at this point isListening is already false)
            if !isProcessing && !voiceManager.isListening && aiSettings.isEnabled {
                let text = voiceManager.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty && refinedText == nil && !isRefining {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        refineText()
                    }
                }
            }
        }
        .sheet(isPresented: $showMacroSaveDialog) {
            macroSaveDialogContent
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
            // Highlight background when in existing wording mode
            if isRefiningWithExistingWording {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue, lineWidth: 3)
                    .background(Color.blue.opacity(0.05))
            }
            
            BoundedTextView(
                text: $voiceManager.transcribedText,
                onSelectionChange: { selected, range in
                    selectedText = selected
                    selectedTextRange = range
                    LogManager.shared.log("📍 Selection changed - text: \(selected ?? "nil"), range: \(range?.description ?? "nil")", category: "VoiceInput", level: .debug)
                },
                onContainerCreated: { container in
                    textViewContainer = container
                }
            )

            if voiceManager.transcribedText.isEmpty {
                Text(voiceManager.isListening
                     ? "Speak now…"
                     : "Press the mic button and speak.\nYour speech will appear here.\n\nSpecial tokens: <CTRL>, <SHIFT>, <ALT>, <CMD>, <SPACE>, <F1>-<F12>\nComposite keys: <CTRL>A</CTRL>")
                    .foregroundColor(Color(UIColor.placeholderText))
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.top, 14)
                    .allowsHitTesting(false)
            }
            
            // Indicator badge when text is marked for refinement
            if isRefiningWithExistingWording {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.blue)
                        Text("Text marked for refinement")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(6)
                    .padding(.top, 16)
                    .padding(.leading, 16)
                    Spacer()
                }
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
            
            // Selection context button - toggle to mark/unmark as existing wording
            if aiSettings.isEnabled && (!isRefining) && (!(selectedText?.isEmpty ?? true) || isRefiningWithExistingWording) {
                VStack(alignment: .leading, spacing: 8) {
                    Button(action: toggleExistingWordingMark) {
                        Image(systemName: isRefiningWithExistingWording ? "checkmark.circle.fill" : "checkmark.circle")
                            .font(.system(size: 20))
                            .foregroundColor(isRefiningWithExistingWording ? .green : .gray)
                            .padding(8)
                    }
                    Spacer()
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .topTrailing)
                .allowsHitTesting(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground))
    }
    
    private func toggleExistingWordingMark() {
        LogManager.shared.log("🔄 toggleExistingWordingMark called", category: "VoiceInput", level: .info)
        LogManager.shared.log("  - isRefiningWithExistingWording: \(isRefiningWithExistingWording)", category: "VoiceInput", level: .info)
        LogManager.shared.log("  - selectedText: \(selectedText ?? "nil")", category: "VoiceInput", level: .info)
        LogManager.shared.log("  - selectedTextRange: \(selectedTextRange?.description ?? "nil")", category: "VoiceInput", level: .info)
        LogManager.shared.log("  - existingWording: \(existingWording ?? "nil")", category: "VoiceInput", level: .info)
        
        if isRefiningWithExistingWording {
            // Unmark: remove existing wording
            LogManager.shared.log("  ➡️ Unmarking existing wording mode", category: "VoiceInput", level: .info)
            textViewContainer?.clearHighlighting()
            LogManager.shared.log("    ✓ Cleared highlighting", category: "VoiceInput", level: .info)
            existingWording = nil
            existingWordingRange = nil
            isRefiningWithExistingWording = false
            LogManager.shared.log("    ✓ Set states to nil/false", category: "VoiceInput", level: .info)
            LogManager.shared.log("  ✅ Unmarked - new isRefiningWithExistingWording: \(isRefiningWithExistingWording)", category: "VoiceInput", level: .info)
        } else {
            // Mark: set existing wording
            LogManager.shared.log("  ➡️ Marking existing wording mode", category: "VoiceInput", level: .info)
            guard let selected = selectedText, !selected.isEmpty,
                  let range = selectedTextRange else {
                LogManager.shared.log("    ❌ Guard failed - selected: \(selectedText?.isEmpty ?? true), range: \(selectedTextRange?.description ?? "nil")", category: "VoiceInput", level: .error)
                return
            }
            LogManager.shared.log("    ✓ Guard passed", category: "VoiceInput", level: .info)
            existingWording = selected
            LogManager.shared.log("    ✓ Set existingWording", category: "VoiceInput", level: .info)
            existingWordingRange = range
            LogManager.shared.log("    ✓ Set existingWordingRange", category: "VoiceInput", level: .info)
            isRefiningWithExistingWording = true
            LogManager.shared.log("    ✓ Set isRefiningWithExistingWording to true", category: "VoiceInput", level: .info)
            selectedText = nil  // Clear selection
            LogManager.shared.log("    ✓ Cleared selectedText", category: "VoiceInput", level: .info)
            // Highlight the marked text in red
            textViewContainer?.highlightText(at: range, withColor: .systemRed)
            LogManager.shared.log("    ✓ Applied red highlighting", category: "VoiceInput", level: .info)
            LogManager.shared.log("  ✅ Marked - new isRefiningWithExistingWording: \(isRefiningWithExistingWording)", category: "VoiceInput", level: .info)
        }
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
                Text(voiceManager.permissionGranted
                        ? (aiSettings.sttEngine == .whisper ? modelManager.selectedModel.displayName : "Ready")
                        : "No Permission")
                    .font(.caption)
                    .foregroundColor(voiceManager.permissionGranted ? .secondary : .orange)
            }
        }
    }

    // MARK: - Action Row

    private var actionRow: some View {
        VStack(spacing: 12) {
            // Special tokens quick insert row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach([
                        ("⌃ Ctrl", "<CTRL>"), ("⇧ Shift", "<SHIFT>"), ("⎇ Alt", "<ALT>"), ("⌘ Cmd", "<CMD>"),
                        ("⎋ Esc", "<ESC>"), ("⏎ Enter", "<ENTER>"), ("⌫ Back", "<BACK>"), ("␣ Space", "<SPACE>"),
                        ("F1", "<F1>"), ("F2", "<F2>"), ("F3", "<F3>"), ("F4", "<F4>"),
                        ("F5", "<F5>"), ("F6", "<F6>"), ("F7", "<F7>"), ("F8", "<F8>"),
                        ("F9", "<F9>"), ("F10", "<F10>"), ("F11", "<F11>"), ("F12", "<F12>")
                    ], id: \.1) { label, token in
                        Button(action: {
                            voiceManager.transcribedText += token
                        }) {
                            Text(label)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(6)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            
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
        VStack(alignment: .leading, spacing: 6) {
            Text(item.text)
                .font(.callout)
                .foregroundColor(.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 4) {
                Text(formatTimestamp(item.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: {
                    voiceManager.transcribedText = item.text
                }) {
                    AdaptiveLabel(systemImage: "pencil", text: "Edit")
                    .font(.caption2)
                    .foregroundColor(.blue)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(5)
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: {
                    resendText(item.text)
                }) {
                    AdaptiveLabel(systemImage: "paperplane.fill", text: "Resend")
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.blue)
                    .cornerRadius(5)
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: {
                    selectedHistoryItemForMacro = item
                    macroNameInput = String(item.text.prefix(20))
                    showMacroSaveDialog = true
                }) {
                    AdaptiveLabel(systemImage: "plus.circle", text: "Macro")
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.green)
                    .cornerRadius(5)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.vertical, 6)
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
                    let message = isRefiningWithExistingWording ? "AI is combining and refining…" : (refiningSelectedOnly ? "AI is refining selected text…" : "AI is refining your text…")
                    Text(message)
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
            
            // Success state - auto-applied
            if let refined = refinedText, refinementError == nil {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        let title = isRefiningWithExistingWording ? "✨ Combined & Refined" : (refiningSelectedOnly ? "✨ Selected Text Refined" : "✨ AI Refined Text")
                        Text(title)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                        Text(refined)
                            .font(.body)
                            .lineLimit(3)
                            .foregroundColor(.primary)
                    }
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.green)
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
                .onAppear {
                    // Auto-dismiss after 2 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        refinedText = nil
                    }
                }
            }
        }
    }

    // MARK: - AI Refinement
    
    /// Returns the macro catalog suffix when the command_assistant role is active, nil otherwise.
    private func commandAssistantMacroSuffix() -> String? {
        guard AISettings.shared.selectedSystemPromptRole == "command_assistant" else { return nil }
        return macroManager.macroContextSection()
    }

    private func refineText() {
        let text = voiceManager.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        isRefining = true
        refinedText = nil
        refinementError = nil
        refiningSelectedOnly = false  // Refining all text
        
        // If in "existing wording" mode, combine both texts for refinement
        let inputText: String
        if isRefiningWithExistingWording, let existing = existingWording, !existing.isEmpty {
            inputText = "Existing wording: \(existing)\nNew input: \(text)\n\nPlease refine and combine these into a coherent, improved version."
        } else {
            inputText = text
        }
        
        AITextRefinementManager.shared.refineText(input: inputText, systemPromptSuffix: commandAssistantMacroSuffix()) { result in
            DispatchQueue.main.async {
                isRefining = false
                switch result {
                case .success(let refined):
                    // Auto-apply the refined text - AI returns complete combined result
                    voiceManager.transcribedText = refined
                    
                    // Clear existing wording mode if active
                    if isRefiningWithExistingWording {
                        textViewContainer?.clearHighlighting()
                        existingWording = nil
                        existingWordingRange = nil
                        isRefiningWithExistingWording = false
                    }
                    
                    // Show success briefly then clear
                    refinedText = refined
                    refinementError = nil
                    LogManager.shared.log("✅ Text refinement successful and applied: \(refined)", category: "VoiceInput", level: .info)
                    
                case .failure(let error):
                    refinedText = nil
                    refinementError = error.localizedDescription
                    LogManager.shared.log("❌ Text refinement failed: \(error.localizedDescription)", category: "VoiceInput", level: .error)
                }
            }
        }
    }
    
    private func refineSelectedText() {
        guard let selected = selectedText, !selected.isEmpty,
              let range = selectedTextRange else { return }
        
        isRefining = true
        refinedText = nil
        refinementError = nil
        refiningSelectedOnly = true  // Refining selected text only
        
        AITextRefinementManager.shared.refineText(input: selected, systemPromptSuffix: commandAssistantMacroSuffix()) { result in
            DispatchQueue.main.async {
                isRefining = false
                switch result {
                case .success(let refined):
                    // Auto-apply the refined text to selected portion
                    let mutableString = NSMutableString(string: voiceManager.transcribedText)
                    mutableString.replaceCharacters(in: range, with: refined)
                    voiceManager.transcribedText = mutableString as String
                    
                    // Show success briefly then clear
                    refinedText = refined
                    refinementError = nil
                    refiningSelectedOnly = false
                    selectedText = nil
                    selectedTextRange = nil
                    LogManager.shared.log("✅ Selected text refinement successful and applied", category: "VoiceInput", level: .info)
                    
                case .failure(let error):
                    refinedText = nil
                    refinementError = error.localizedDescription
                    LogManager.shared.log("❌ Selected text refinement failed: \(error.localizedDescription)", category: "VoiceInput", level: .error)
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
        // Use the new handleTextInputWithTokens to support special tokens
        keyboardManager.handleTextInputWithTokens(text)

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
        // Use the new handleTextInputWithTokens to support special tokens
        keyboardManager.handleTextInputWithTokens(text)
    }

    // MARK: - Macro Saving

    private var macroSaveDialogContent: some View {
        NavigationView {
            VStack(spacing: 16) {
                Text("Save as Macro")
                    .font(.headline)
                    .padding(.top)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Macro Name")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextField("Enter macro name", text: $macroNameInput)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal)
                    
                    Text("Text: \(selectedHistoryItemForMacro?.text ?? "")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .padding(.horizontal)
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button("Cancel") {
                        showMacroSaveDialog = false
                        macroNameInput = ""
                        selectedHistoryItemForMacro = nil
                    }
                    .foregroundColor(.blue)
                    
                    Spacer()
                    
                    Button(action: saveMacro) {
                        Text("Save")
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .cornerRadius(8)
                    }
                    .disabled(macroNameInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func saveMacro() {
        guard let item = selectedHistoryItemForMacro,
              !macroNameInput.trimmingCharacters(in: .whitespaces).isEmpty else {
            return
        }
        
        let macro = Macro(
            label: macroNameInput.trimmingCharacters(in: .whitespaces),
            data: item.text,
            intervalMs: 100
        )
        
        macroManager.addMacro(macro)
        LogManager.shared.log("✅ Saved voice input as macro: \(macro.label)", category: "VoiceInput", level: .info)
        
        // Close dialog and reset state
        showMacroSaveDialog = false
        macroNameInput = ""
        selectedHistoryItemForMacro = nil
    }
}


#Preview {
    VoiceInputView(keyboardManager: KeyboardManager(bleManager: BLEManager()))
}
