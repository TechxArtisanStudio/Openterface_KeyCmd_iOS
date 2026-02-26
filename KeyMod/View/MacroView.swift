import SwiftUI

// Extend Macro to support scheduling (optional properties)
struct Macro: Identifiable, Codable, Equatable {
    let id: UUID
    var label: String // for display
    var data: String  // actual data to send
    var intervalMs: Int // interval in ms between chars
    // Scheduling
    var scheduledTime: Date? = nil
    var repeatCount: Int? = nil
    var isScheduled: Bool = false
    var repeatIntervalSeconds: TimeInterval? = nil // interval between repeats in seconds
    
    init(label: String, data: String, intervalMs: Int = 100, scheduledTime: Date? = nil, repeatCount: Int? = nil, isScheduled: Bool = false, repeatIntervalSeconds: TimeInterval? = nil) {
        self.id = UUID()
        self.label = label
        self.data = data
        self.intervalMs = intervalMs
        self.scheduledTime = scheduledTime
        self.repeatCount = repeatCount
        self.isScheduled = isScheduled
        self.repeatIntervalSeconds = repeatIntervalSeconds
    }
    // Custom decoding to provide default for intervalMs and new fields
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        data = try container.decode(String.self, forKey: .data)
        intervalMs = (try? container.decode(Int.self, forKey: .intervalMs)) ?? 100
        scheduledTime = try? container.decodeIfPresent(Date.self, forKey: .scheduledTime)
        repeatCount = try? container.decodeIfPresent(Int.self, forKey: .repeatCount)
        isScheduled = (try? container.decodeIfPresent(Bool.self, forKey: .isScheduled)) ?? false
        repeatIntervalSeconds = try? container.decodeIfPresent(TimeInterval.self, forKey: .repeatIntervalSeconds)
    }
}

struct MacroView: View {
    @ObservedObject var keyboardManager: KeyboardManager
    @StateObject private var macroManager: MacroManager
    // Wizard dialog state
    @State private var showAddWizard = false
    @State private var wizardLabel = ""
    @State private var wizardData = ""
    @State private var wizardInterval: Double = 100
    @State private var isEditing = false
    @State private var scheduleEnabled = false
    @State private var scheduleDate = Date()
    @State private var repeatEnabled = false
    @State private var repeatTimes: Int = 1
    @State private var repeatIntervalEnabled = false
    @State private var repeatIntervalSeconds: Double = 60
    @State private var editingIndex: Int? = nil
    @State private var textEditorSelectedRange: NSRange = NSRange(location: 0, length: 0)
    
    init(keyboardManager: KeyboardManager) {
        self.keyboardManager = keyboardManager
        _macroManager = StateObject(wrappedValue: MacroManager(keyboardManager: keyboardManager))
    }
    
    var body: some View {
        VStack {
            HStack {
                Text("Macros")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button(action: {
                    wizardLabel = ""
                    wizardData = ""
                    wizardInterval = 100
                    isEditing = false
                    scheduleEnabled = false
                    repeatEnabled = false
                    repeatTimes = 1
                    repeatIntervalEnabled = false
                    repeatIntervalSeconds = 60
                    showAddWizard = true
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                .accessibilityLabel("Add Macro")
            }
            .padding(.top)
            
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
                    ForEach(Array(macroManager.macros.enumerated()), id: \.element.id) { idx, macro in
                        HStack {
                            Button(action: {
                                macroManager.sendMacro(macro)
                            }) {
                                VStack(spacing: 2) {
                                    Text(macro.label)
                                        .font(.headline)
                                    if macro.repeatIntervalSeconds != nil {
                                        HStack(spacing: 2) {
                                            Image(systemName: "repeat")
                                                .font(.caption2)
                                            Text(formatInterval(macro.repeatIntervalSeconds!))
                                                .font(.caption2)
                                        }
                                        .foregroundColor(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(macro.repeatIntervalSeconds != nil ? Color.green.opacity(0.2) : Color.blue.opacity(0.2))
                                .cornerRadius(8)
                            }
                            .contextMenu {
                                Button("Edit") {
                                    wizardLabel = macro.label
                                    wizardData = macro.data
                                    wizardInterval = Double(macro.intervalMs)
                                    editingIndex = idx
                                    isEditing = true
                                    showAddWizard = true
                                    scheduleEnabled = macro.isScheduled
                                    scheduleDate = macro.scheduledTime ?? Date()
                                    repeatEnabled = macro.repeatCount != nil
                                    repeatTimes = macro.repeatCount ?? 1
                                    repeatIntervalEnabled = macro.repeatIntervalSeconds != nil
                                    repeatIntervalSeconds = macro.repeatIntervalSeconds ?? 60
                                }
                                if macro.repeatIntervalSeconds != nil {
                                    Button("Stop Repeat") {
                                        macroManager.stopRepeatInterval(for: macro.id)
                                    }
                                }
                                Button("Delete", role: .destructive) {
                                    macroManager.removeMacro(at: idx)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical)
            }
            Spacer()
        }
        .padding(.horizontal)
        .onAppear {
            macroManager.loadMacros()
        }
        .sheet(isPresented: $showAddWizard) {
            NavigationView {
                Form {
                    Section(header: Text("Macro Name (Label)")) {
                        TextField("e.g. Copy", text: $wizardLabel)
                    }
                    Section(header: Text("Macro Data (e.g. ^C, Hello,  A)")) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Composite Keys: <CTRL>A</CTRL> = press Ctrl, press A, release all")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            // Tokenized preview with icons and delete buttons
                            TokenizedMacroView(text: $wizardData)
                            CursorTextEditor(text: $wizardData, selectedRange: $textEditorSelectedRange)
                                .frame(minHeight: 80, maxHeight: 160)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3)))
                            // Special keys row
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach([
                                        ("⎇ Alt", "<ALT>"), ("^ Ctrl", "<CTRL>"), ("⇧ Shift", "<SHIFT>"), ("⌘ Cmd", "<CMD>"),
                                        ("</ALT>", "</ALT>"), ("</CTRL>", "</CTRL>"), ("</SHIFT>", "</SHIFT>"), ("</CMD>", "</CMD>"),
                                        ("⎋ Esc", "<ESC>"), ("⌫ Back", "<BACK>"), ("⏎ Enter", "<ENTER>"), ("␣ Space", "<SPACE>"),
                                        ("←", "<LEFT>"), ("→", "<RIGHT>"), ("↑", "<UP>"), ("↓", "<DOWN>"),
                                        ("⇱ Home", "<HOME>"), ("⇲ End", "<END>"),
                                        ("⏱ 1s", "<DELAY1S>"), ("⏱ 2s", "<DELAY2S>"), ("⏱ 5s", "<DELAY5S>"), ("⏱ 10s", "<DELAY10S>")
                                    ], id: \.1) { label, key in
                                        Button(action: {
                                            let range = textEditorSelectedRange
                                            let start = wizardData.index(wizardData.startIndex, offsetBy: range.location)
                                            let end = wizardData.index(start, offsetBy: range.length)
                                            wizardData.replaceSubrange(start..<end, with: key)
                                            // Move cursor after inserted token
                                            let newLoc = range.location + key.count
                                            textEditorSelectedRange = NSRange(location: newLoc, length: 0)
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
                            }
                        }
                    }
                    Section(header: Text("Send Char Interval (ms)")) {
                        HStack {
                            Slider(value: $wizardInterval, in: 10...1000, step: 10)
                            Text("\(Int(wizardInterval)) ms")
                                .frame(width: 60, alignment: .trailing)
                        }
                    }
                    Section(header: Text("Scheduler (Optional)")) {
                        Toggle("Enable Scheduler", isOn: $scheduleEnabled)
                        if scheduleEnabled {
                            DatePicker("Run At", selection: $scheduleDate, displayedComponents: [.hourAndMinute, .date])
                            Toggle("Repeat", isOn: $repeatEnabled)
                            if repeatEnabled {
                                Stepper(value: $repeatTimes, in: 1...100) {
                                    Text("Repeat \(repeatTimes)x")
                                }
                            }
                            Toggle("Repeat Interval", isOn: $repeatIntervalEnabled)
                            if repeatIntervalEnabled {
                                VStack(alignment: .leading) {
                                    HStack {
                                        Text("Every")
                                        Slider(value: $repeatIntervalSeconds, in: 5...3600, step: 5)
                                        Text("\(Int(repeatIntervalSeconds))s")
                                            .frame(width: 50, alignment: .trailing)
                                    }
                                    HStack {
                                        ForEach([
                                            ("30s", 30.0), ("1m", 60.0), ("5m", 300.0), 
                                            ("10m", 600.0), ("30m", 1800.0), ("1h", 3600.0)
                                        ], id: \.0) { label, seconds in
                                            Button(label) {
                                                repeatIntervalSeconds = seconds
                                            }
                                            .buttonStyle(.bordered)
                                            .font(.caption)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .navigationTitle(isEditing ? "Edit Macro" : "Add Macro")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showAddWizard = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            let label = wizardLabel.isEmpty ? wizardData : wizardLabel
                            if !wizardData.isEmpty {
                                let scheduledTime = scheduleEnabled ? scheduleDate : nil
                                let repeatCount = (scheduleEnabled && repeatEnabled) ? repeatTimes : nil
                                let isScheduled = scheduleEnabled
                                let repeatInterval = repeatIntervalEnabled ? repeatIntervalSeconds : nil
                                let newMacro = Macro(label: label, data: wizardData, intervalMs: Int(wizardInterval), scheduledTime: scheduledTime, repeatCount: repeatCount, isScheduled: isScheduled, repeatIntervalSeconds: repeatInterval)
                                if isEditing, let idx = editingIndex {
                                    macroManager.updateMacro(newMacro, at: idx)
                                } else {
                                    macroManager.addMacro(newMacro)
                                }
                            }
                            wizardLabel = ""
                            wizardData = ""
                            wizardInterval = 100
                            isEditing = false
                            editingIndex = nil
                            showAddWizard = false
                            scheduleEnabled = false
                            repeatEnabled = false
                            repeatTimes = 1
                            repeatIntervalEnabled = false
                            repeatIntervalSeconds = 60
                        }.disabled(wizardData.isEmpty)
                    }
                }
            }
        }
    }
    
    private func formatInterval(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        if totalSeconds < 60 {
            return "\(totalSeconds)s"
        } else if totalSeconds < 3600 {
            let minutes = totalSeconds / 60
            return "\(minutes)m"
        } else {
            let hours = totalSeconds / 3600
            return "\(hours)h"
        }
    }
    
    private func bindingLabel(for macro: Macro) -> Binding<String> {
        Binding<String>(
            get: {
                macro.label
            },
            set: { newValue in
                if let idx = macroManager.macros.firstIndex(of: macro) {
                    macroManager.macros[idx].label = newValue
                }
            }
        )
    }
    private func bindingData(for macro: Macro) -> Binding<String> {
        Binding<String>(
            get: {
                macro.data
            },
            set: { newValue in
                if let idx = macroManager.macros.firstIndex(of: macro) {
                    macroManager.macros[idx].data = newValue
                }
            }
        )
    }
}

// MARK: - TokenizedMacroView
struct TokenizedMacroView: View {
    @Binding var text: String
    let tokenMap: [String: String] = [
        "<ALT>": "⎇",
        "<CTRL>": "^",
        "<SHIFT>": "⇧",
        "<CMD>": "⌘",
        "</ALT>": "⎇✕",
        "</CTRL>": "^✕",
        "</SHIFT>": "⇧✕",
        "</CMD>": "⌘✕",
        "<ESC>": "⎋",
        "<BACK>": "⌫",
        "<ENTER>": "⏎",
        "<LEFT>": "←",
        "<RIGHT>": "→",
        "<UP>": "↑",
        "<DOWN>": "↓",
        "<HOME>": "⇱",
        "<END>": "⇲",
        "<DELAY1S>": "⏱1s",
        "<DELAY2S>": "⏱2s",
        "<DELAY5S>": "⏱5s",
        "<DELAY10S>": "⏱10s",
        " ": "␣"
    ]
    
    var tokenRows: [[String]] {
        let tokens = tokenize(text)
        var rows: [[String]] = [[]]
        var currentRowWidth: CGFloat = 0
        let estimatedItemWidth: CGFloat = 60
        let containerWidth: CGFloat = UIScreen.main.bounds.width - 40
        
        for token in tokens {
            if currentRowWidth + estimatedItemWidth > containerWidth && !rows.last!.isEmpty {
                rows.append([token])
                currentRowWidth = estimatedItemWidth
            } else {
                rows[rows.count - 1].append(token)
                currentRowWidth += estimatedItemWidth
            }
        }
        return rows
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(tokenRows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 4) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, token in
                        if let icon = tokenMap[token] {
                            HStack(spacing: 2) {
                                Text(icon)
                                    .font(token == " " ? .body : .headline)
                                    .padding(4)
                                    .background(token.hasPrefix("</") ? Color.red.opacity(0.2) : (token == " " ? Color.blue.opacity(0.15) : Color.yellow.opacity(0.3)))
                                    .cornerRadius(4)
                                Button(action: {
                                    removeToken(token)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                            }
                        } else {
                            Text(token)
                                .font(.body)
                        }
                    }
                    Spacer()
                }
            }
        }
    }
    // Tokenize macro string into text and special tokens, including spaces and delay tokens as separate tokens
    func tokenize(_ str: String) -> [String] {
        let pattern = "</?([A-Z0-9]+S?)>| " // Match special tokens (opening and closing), delay tokens, or spaces
        let regex = try? NSRegularExpression(pattern: pattern)
        let nsStr = str as NSString
        var lastIndex = 0
        var result: [String] = []
        if let regex = regex {
            let matches = regex.matches(in: str, range: NSRange(location: 0, length: nsStr.length))
            for match in matches {
                let range = match.range
                if range.location > lastIndex {
                    let text = nsStr.substring(with: NSRange(location: lastIndex, length: range.location - lastIndex))
                    result.append(contentsOf: text.map { String($0) })
                }
                let token = nsStr.substring(with: range)
                result.append(token)
                lastIndex = range.location + range.length
            }
            if lastIndex < nsStr.length {
                let text = nsStr.substring(from: lastIndex)
                result.append(contentsOf: text.map { String($0) })
            }
        } else {
            result = str.map { String($0) }
        }
        return result
    }
    // Remove token at index
    func removeToken(_ token: String, at idx: Int) {
        let tokens = tokenize(text)
        var newTokens = tokens
        newTokens.remove(at: idx)
        text = newTokens.joined()
    }
    
    // Remove first occurrence of token
    func removeToken(_ token: String) {
        let tokens = tokenize(text)
        var newTokens = tokens
        if let idx = newTokens.firstIndex(of: token) {
            newTokens.remove(at: idx)
            text = newTokens.joined()
        }
    }
}

// MARK: - CursorTextEditor
import UIKit

struct CursorTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.isScrollEnabled = true
        textView.backgroundColor = UIColor.clear
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        if uiView.selectedRange != selectedRange {
            uiView.selectedRange = selectedRange
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: CursorTextEditor
        init(_ parent: CursorTextEditor) {
            self.parent = parent
        }
        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }
        func textViewDidChangeSelection(_ textView: UITextView) {
            parent.selectedRange = textView.selectedRange
        }
    }
}

#Preview {
    MacroView(keyboardManager: KeyboardManager(bleManager: BLEManager()))
}
