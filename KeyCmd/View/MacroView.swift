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
    @State private var editMode = false
    
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
                    editMode.toggle()
                }) {
                    Image(systemName: editMode ? "checkmark.circle.fill" : "pencil.circle.fill")
                        .font(.title2)
                        .foregroundColor(editMode ? .green : .orange)
                }
                .accessibilityLabel(editMode ? "Done Editing" : "Edit Macros")
                
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
                        ZStack(alignment: .topTrailing) {
                            Button(action: {
                                if !editMode {
                                    macroManager.sendMacro(macro)
                                }
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
                            
                            // Delete button in edit mode
                            if editMode {
                                Button(action: {
                                    macroManager.removeMacro(at: idx)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title3)
                                        .foregroundColor(.red)
                                        .padding(8)
                                }
                                .background(Color.white)
                                .clipShape(Circle())
                                .offset(x: 8, y: -8)
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
                            // Insert tokens
                            Text("INSERT TOKENS").font(.caption).fontWeight(.semibold).foregroundColor(.secondary)
                            FlowLayout(spacing: 6) {
                                tokenInsertButton("⎇ Alt", "<ALT>"); tokenInsertButton("^ Ctrl", "<CTRL>"); tokenInsertButton("⇧ Shift", "<SHIFT>"); tokenInsertButton("⌘ Cmd", "<CMD>")
                                tokenInsertButton("</ALT>", "</ALT>"); tokenInsertButton("</CTRL>", "</CTRL>"); tokenInsertButton("</SHIFT>", "</SHIFT>"); tokenInsertButton("</CMD>", "</CMD>")
                                tokenInsertButton("⎋ Esc", "<ESC>"); tokenInsertButton("⌫ Back", "<BACK>"); tokenInsertButton("⏎ Enter", "<ENTER>"); tokenInsertButton("␣ Space", "<SPACE>")
                                tokenInsertButton("←", "<LEFT>"); tokenInsertButton("→", "<RIGHT>"); tokenInsertButton("↑", "<UP>"); tokenInsertButton("↓", "<DOWN>")
                                tokenInsertButton("⇱ Home", "<HOME>"); tokenInsertButton("⇲ End", "<END>")
                                tokenInsertButton("⏱ 1s", "<DELAY1S>"); tokenInsertButton("⏱ 2s", "<DELAY2S>"); tokenInsertButton("⏱ 5s", "<DELAY5S>"); tokenInsertButton("⏱ 10s", "<DELAY10S>")
                                ForEach(1...12, id: \.self) { n in
                                    tokenInsertButton("F\(n)", "<F\(n)>")
                                }
                                Text("SYMBOLS").font(.caption2).fontWeight(.semibold).foregroundColor(.secondary).padding(.top, 4)
                                ForEach(["(", ")", "-", "+", "=", "!", "@", "#", "$", "%", "^", "&", "*", "<", ">", "{", "}", "[", "]", "|", "\\", ":", ";", "\"", "'", ",", ".", "/", "?", "~", "`", "_"], id: \.self) { sym in
                                    tokenInsertButton(sym, String(sym))
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
    
    @ViewBuilder
    private func tokenInsertButton(_ label: String, _ key: String) -> some View {
        Button(action: {
            var range = textEditorSelectedRange
            // If cursor is invalid or at 0 when text is non-empty, append to end
            if range.location == 0 && range.length == 0 && !wizardData.isEmpty {
                range.location = wizardData.count
            }
            let clampedLoc = min(range.location, wizardData.count)
            let clampedLen = min(range.length, wizardData.count - clampedLoc)
            let start = wizardData.index(wizardData.startIndex, offsetBy: clampedLoc)
            let end = wizardData.index(start, offsetBy: clampedLen)
            wizardData.replaceSubrange(start..<end, with: key)
            textEditorSelectedRange = NSRange(location: clampedLoc + key.count, length: 0)
        }) {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(6)
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
                        } else if token.count == 1 && !token.allSatisfy({ $0.isLetter || $0.isNumber }) {
                            // Symbol character — show with subtle background
                            Text(token)
                                .font(.body.monospaced())
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.15))
                                .cornerRadius(3)
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
        Keymod.tokenizeScript(str)
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

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > maxW { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
        return CGSize(width: maxW == .infinity ? x : maxW, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            sv.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}

#Preview {
    MacroView(keyboardManager: KeyboardManager(bleManager: BLEManager()))
}
