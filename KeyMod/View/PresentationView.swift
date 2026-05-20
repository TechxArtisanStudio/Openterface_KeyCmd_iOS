//
//  PresentationView.swift
//  KeyMod
//
//  iOS port of Android PresentationFragment.
//

import SwiftUI
import UIKit

/// Conditional `.presentationDetents` for iOS 16+.
extension View {
    func presentationDetentsIfAvailable(large: Bool = false) -> some View {
        Group {
            if #available(iOS 16.0, *) {
                if large {
                    self.presentationDetents([.medium, .large])
                } else {
                    self.presentationDetents([.medium])
                }
            } else {
                self
            }
        }
    }
}

// MARK: - Presentation Tool

/// Maps each supported presentation app to its HID key combo.
enum PresentationTool: Int, CaseIterable {
    case keynote       = 0
    case powerPoint    = 1
    case googleSlides  = 2
    case word          = 3
    case adobeReader   = 4

    var displayName: String {
        switch self {
        case .keynote:      return "Keynote"
        case .powerPoint:   return "PowerPoint"
        case .googleSlides: return "Google Slides"
        case .word:         return "Word"
        case .adobeReader:  return "Adobe Reader"
        }
    }

    var iconName: String {
        switch self {
        case .keynote:      return "k.circle"
        case .powerPoint:   return "p.circle"
        case .googleSlides: return "s.circle"
        case .word:         return "w.circle"
        case .adobeReader:  return "a.circle"
        }
    }

    /// Modifier keys for the "start presentation" shortcut. nil = no shortcut.
    var playModifiers: [String]? {
        switch self {
        case .keynote:      return ["Alt", "Cmd"]   // Opt+Cmd+P
        case .powerPoint:   return ["Shift", "Cmd"] // Cmd+Shift+Enter
        case .googleSlides: return ["Cmd"]           // Cmd+Enter
        case .word:         return nil               // no shortcut
        case .adobeReader:  return ["Cmd"]           // Cmd+L
        }
    }

    /// Key code for the "start presentation" shortcut.
    var playKey: String? {
        switch self {
        case .keynote:      return "p"
        case .powerPoint:   return "Enter"
        case .googleSlides: return "Enter"
        case .word:         return nil
        case .adobeReader:  return "l"
        }
    }
}

// MARK: - Timer Mode

enum PresentationTimerMode: Int {
    case countdown = 0
    case countup   = 1
}

// MARK: - App-Switcher State

private enum AppSwitcherState {
    case closed
    case open   // modifier held, switcher visible
}

// MARK: - PresentationView

struct PresentationView: View {
    let keyboardManager: KeyboardManager
    let mouseManager: MouseManager
    let orientationManager: OrientationManager

    // MARK: Persistence
    @AppStorage("presentation_tool_index")      private var toolIndex: Int = 0
    @AppStorage("presentation_timer_duration")  private var timerDurationSecs: Int = 25 * 60
    @AppStorage("presentation_timer_mode")      private var timerModeRaw: Int = PresentationTimerMode.countdown.rawValue
    @AppStorage("presentation_timer_remaining") private var storedRemaining: Int = 25 * 60

    // MARK: Transient State
    @State private var playActive: Bool = false
    @State private var showScreen: Bool = true          // true = screen showing (black screen off)
    @State private var switcherState: AppSwitcherState = .closed
    @State private var switcherAutoReleaseTask: DispatchWorkItem? = nil

    // Timer
    @State private var timerRunning: Bool = false
    @State private var timerElapsed: Int = 0            // seconds elapsed from start
    @State private var timerTimer: Timer? = nil
    @State private var lastTapTime: Date? = nil

    // Sheet / popover
    @State private var showTouchpad: Bool = false
    @State private var showTimerSettings: Bool = false

    // Carousel drag
    @State private var carouselDragOffset: CGFloat = 0

    private let haptic = HapticFeedbackManager.shared

    // Derived
    private var timerMode: PresentationTimerMode { PresentationTimerMode(rawValue: timerModeRaw) ?? .countdown }
    private var selectedTool: PresentationTool   { PresentationTool(rawValue: toolIndex) ?? .keynote }

    /// Remaining / elapsed seconds for display
    private var displaySeconds: Int {
        switch timerMode {
        case .countdown: return timerDurationSecs - timerElapsed
        case .countup:   return timerElapsed
        }
    }

    /// Overtime = countdown went below zero
    private var isOvertime: Bool {
        timerMode == .countdown && timerElapsed > timerDurationSecs
    }

    private var timerFraction: CGFloat {
        guard timerDurationSecs > 0 else { return 0 }
        switch timerMode {
        case .countdown:
            // Fill from trailing edge: fraction represents remaining time
            let remaining = timerDurationSecs - timerElapsed
            return CGFloat(max(0, remaining)) / CGFloat(timerDurationSecs)
        case .countup:
            // Fill from leading edge: fraction represents elapsed time
            return min(CGFloat(timerElapsed) / CGFloat(max(timerDurationSecs, 1)), 1.0)
        }
    }

    private var targetOS: TargetOS { AISettings.shared.targetOS }

    /// Formats seconds as "M:SS".
    private func formatDuration(_ seconds: Int) -> String {
        let mins = abs(seconds) / 60
        let secs = abs(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    /// Status text shown next to "TIMER" header, e.g. "remaining of 25:00".
    private var timerStatusText: String {
        let modeText = timerMode == .countdown ? "remaining" : "elapsed"
        return "\(modeText) of \(formatDuration(timerDurationSecs))"
    }

    /// Progress fill grows from leading edge for countup, trailing edge for countdown.
    private var timerFillFromLeading: Bool { timerMode == .countup }

    /// Shortcut hint shown below the Play button, matching each tool.
    private var playShortcutHint: String {
        switch selectedTool {
        case .keynote:      return "⌥⌘P / ESC"
        case .powerPoint:   return "⇧⌘↵ / ESC"
        case .googleSlides: return "⌘↵ / ESC"
        case .word:         return "F5 / ESC"
        case .adobeReader:  return "⌘L / ESC"
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                toolCarousel
                    .padding(.top, 12)

                timerCard
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 12)

                // Button rows fill remaining space with Android 2:1:1 weight proportions
                GeometryReader { geo in
                    let spacing: CGFloat = 8
                    let hPad: CGFloat = 16
                    let vPad: CGFloat = 16
                    let total = geo.size.height - spacing * 2 - vPad
                    let unit = max(total / 4, 44)
                    VStack(spacing: spacing) {
                        slideNavButtons
                            .frame(height: unit * 2)
                        actionRow
                            .frame(height: unit)
                        utilRow
                            .frame(height: unit)
                    }
                    .padding(.horizontal, hPad)
                    .padding(.bottom, vPad)
                }
            }
        }
        .gesture(swipeGesture)
        .onAppear {
            orientationManager.lockToPortrait()
            timerElapsed = storedRemaining
        }
        .onDisappear {
            pauseTimer()
            storedRemaining = timerElapsed
        }
        .sheet(isPresented: $showTouchpad) { touchpadSheet }
        .sheet(isPresented: $showTimerSettings) { timerSettingsSheet }
    }

    // MARK: - Tool Carousel

    private var toolCarousel: some View {
        let tools = PresentationTool.allCases
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(tools, id: \.rawValue) { tool in
                        toolCell(tool: tool)
                            .id(tool.rawValue)
                            .onTapGesture {
                                haptic.triggerButtonPress()
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    toolIndex = tool.rawValue
                                    proxy.scrollTo(tool.rawValue, anchor: .center)
                                }
                            }
                    }
                }
                .padding(.horizontal, 16)
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    proxy.scrollTo(toolIndex, anchor: .center)
                }
            }
        }
    }

    private func toolCell(tool: PresentationTool) -> some View {
        let selected = tool.rawValue == toolIndex
        return Text(tool.displayName)
            .font(.system(size: selected ? 20 : 16, weight: selected ? .bold : .regular))
            .foregroundColor(selected ? .primary : .secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .animation(.easeInOut(duration: 0.15), value: selected)
    }

    // MARK: - Timer Card

    private var timerCard: some View {
        let running = timerRunning
        let fraction = min(timerFraction, 1.0)
        let overtime = isOvertime
        let absSeconds = abs(displaySeconds)
        let mins = absSeconds / 60
        let secs = absSeconds % 60
        let label = overtime ? String(format: "+%d:%02d", mins, secs) : String(format: "%d:%02d", mins, secs)
        let fromLeading = timerFillFromLeading
        let progressColor: Color = running ? .blue : .gray
        let progressOpacity: Double = running ? 0.18 : 0.10

        return GeometryReader { geo in
            ZStack {
                // Progress fill — direction depends on timer mode
                if fromLeading {
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(progressColor.opacity(progressOpacity))
                            .frame(width: geo.size.width * fraction)
                            .animation(.linear(duration: 1.0), value: fraction)
                        Spacer(minLength: 0)
                    }
                } else {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Rectangle()
                            .fill(progressColor.opacity(progressOpacity))
                            .frame(width: geo.size.width * fraction)
                            .animation(.linear(duration: 1.0), value: fraction)
                    }
                }

                // Text content
                VStack(spacing: 4) {
                    HStack {
                        Text("TIMER")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.secondary)
                            .kerning(1.0)
                        Spacer()
                        Text(timerStatusText)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Text(label)
                        .font(.system(size: 42, weight: .bold, design: .monospaced))
                        .foregroundColor(overtime ? .red : .primary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 90)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)
        }
        .frame(height: 90)
        .gesture(
            TapGesture(count: 2).onEnded {
                handleTimerDoubleTap()
            }
        )
        .simultaneousGesture(
            TapGesture(count: 1).onEnded {
                handleTimerSingleTap()
            }
        )
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.6).onEnded { _ in
                haptic.triggerMediumFeedback()
                showTimerSettings = true
            }
        )
    }

    private func handleTimerSingleTap() {
        haptic.triggerButtonPress()
        if timerRunning {
            pauseTimer()
        } else {
            startTimer()
        }
    }

    private func handleTimerDoubleTap() {
        let wasRunning = timerRunning
        haptic.triggerMediumFeedback()
        stopTimer()
        timerElapsed = 0
        if wasRunning {
            startTimer()
        }
    }

    private func startTimer() {
        timerRunning = true
        timerTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            timerElapsed += 1
            // Notify when countdown reaches 0
            if timerMode == .countdown && timerElapsed == timerDurationSecs {
                haptic.triggerStrongFeedback()
            }
        }
    }

    private func pauseTimer() {
        timerRunning = false
        timerTimer?.invalidate()
        timerTimer = nil
    }

    private func stopTimer() {
        pauseTimer()
        timerElapsed = 0
    }

    // MARK: - Slide Navigation Buttons

    private var slideNavButtons: some View {
        GeometryReader { geo in
            let prevW = (geo.size.width - 8) / 3
            let nextW = (geo.size.width - 8) * 2 / 3
            HStack(spacing: 8) {
                // PREVIOUS – 1/3 width
                VStack(spacing: 3) {
                    Button {
                        haptic.triggerButtonPress()
                        keyboardManager.handleKeyPress("Left")
                    } label: {
                        Text("◀  PREVIOUS")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.gray.opacity(0.7))
                            .cornerRadius(10)
                    }
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                            haptic.triggerMediumFeedback()
                            keyboardManager.handleKeyPress("Home")
                        }
                    )
                    .frame(maxHeight: .infinity)
                    Text("← Left arrow\nLong = First slide")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: prevW, height: geo.size.height)

                // NEXT – 2/3 width
                VStack(spacing: 3) {
                    Button {
                        haptic.triggerButtonPress()
                        keyboardManager.handleKeyPress("Right")
                    } label: {
                        Text("NEXT  ▶")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                            haptic.triggerMediumFeedback()
                            keyboardManager.handleKeyPress("End")
                        }
                    )
                    .frame(maxHeight: .infinity)
                    Text("→ Right arrow\nLong = Last slide")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: nextW, height: geo.size.height)
            }
        }
    }

    // MARK: - Action Row (Play / Black Screen)

    private var actionRow: some View {
        HStack(spacing: 8) {
            // Play / Stop
            VStack(spacing: 3) {
                Button {
                    haptic.triggerButtonPress()
                    togglePlay()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: playActive ? "stop.fill" : "play.fill")
                        Text(playActive ? "STOP" : "PRESENT")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(playActive ? Color.red : Color.green)
                    .cornerRadius(10)
                }
                .frame(maxHeight: .infinity)
                Text(playShortcutHint)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)

            // Hide / Show Screen (Black Screen)
            VStack(spacing: 3) {
                Button {
                    guard playActive else { return }
                    haptic.triggerButtonPress()
                    showScreen.toggle()
                    keyboardManager.handleKeyPress("b")
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showScreen ? "eye.slash" : "eye")
                        Text(showScreen ? "HIDE\nSCREEN" : "SHOW\nSCREEN")
                            .font(.system(size: 15, weight: .semibold))
                            .multilineTextAlignment(.center)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(playActive ? Color.indigo : Color.gray.opacity(0.5))
                    .cornerRadius(10)
                }
                .disabled(!playActive)
                .frame(maxHeight: .infinity)
                Text("B")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Util Row (App Switcher / Pointer)

    private var utilRow: some View {
        HStack(spacing: 8) {
            // App Switcher — single tap = open/cycle; double tap = confirm & close
            VStack(spacing: 3) {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(switcherState == .open ? Color.green : Color.orange)
                    .cornerRadius(10)
                    .overlay(
                        HStack(spacing: 6) {
                            Image(systemName: "square.on.square")
                            Text(switcherState == .open ? "RELEASE" : "SWITCH APP")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundColor(.white)
                    )
                    .gesture(
                        TapGesture(count: 2).onEnded {
                            haptic.triggerMediumFeedback()
                            if switcherState == .open {
                                closeAppSwitcher()
                            }
                        }
                    )
                    .simultaneousGesture(
                        TapGesture(count: 1).onEnded {
                            haptic.triggerButtonPress()
                            handleAppSwitcherTap()
                        }
                    )
                Text("⌘Tab · tap / cycle · double = confirm")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)

            // Pointer / Touchpad
            VStack(spacing: 3) {
                Button {
                    haptic.triggerButtonPress()
                    showTouchpad = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "cursorarrow.motionlines")
                        Text("TOUCHPAD")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.teal)
                    .cornerRadius(10)
                }
                .frame(maxHeight: .infinity)
                Text("Mouse move / click / right-click")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Swipe Gesture (whole background)

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let dx = value.translation.width
                if dx < -30 {
                    // swipe left → next slide
                    haptic.triggerButtonPress()
                    keyboardManager.handleKeyPress("Right")
                } else if dx > 30 {
                    // swipe right → previous slide
                    haptic.triggerButtonPress()
                    keyboardManager.handleKeyPress("Left")
                }
            }
    }

    // MARK: - Play / Stop Logic

    private func togglePlay() {
        if playActive {
            // Stop presentation
            playActive = false
            showScreen = true
            keyboardManager.handleKeyPress("Escape")
        } else {
            // Start presentation — always mark active; send key only if tool has a shortcut
            playActive = true
            if let modifiers = selectedTool.playModifiers,
               let key = selectedTool.playKey {
                keyboardManager.handleKeyCombo(modifiers: modifiers, key: key)
            }
        }
    }

    // MARK: - App Switcher Logic

    private func handleAppSwitcherTap() {
        switch switcherState {
        case .closed:
            // Open: hold modifier + press Tab
            openAppSwitcher()
        case .open:
            // Already open: cycle (send Tab with modifier still held)
            cycleAppSwitcher()
        }
    }

    private func openAppSwitcher() {
        let modifier = (targetOS == .macOS) ? "Cmd" : "Alt"
        switcherState = .open
        keyboardManager.handleKeyDown(modifier)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            keyboardManager.handleKeyPress("Tab")
        }
        scheduleAutoRelease()
    }

    private func cycleAppSwitcher() {
        keyboardManager.handleKeyPress("Tab")
        scheduleAutoRelease()
    }

    private func closeAppSwitcher() {
        let modifier = (targetOS == .macOS) ? "Cmd" : "Alt"
        keyboardManager.handleKeyUp(modifier)
        switcherState = .closed
        switcherAutoReleaseTask?.cancel()
        switcherAutoReleaseTask = nil
    }

    private func scheduleAutoRelease() {
        switcherAutoReleaseTask?.cancel()
        let task = DispatchWorkItem { closeAppSwitcher() }
        switcherAutoReleaseTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: task)
    }

    // MARK: - Touchpad Sheet

    @StateObject private var pointerTipState = PointerTipState()

    private var touchpadSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Pointer")
                    .font(.headline)
                Spacer()
                Button("Done") { showTouchpad = false }
            }
            .padding()

            TouchpadView(
                mouseManager: mouseManager,
                pointerTipState: pointerTipState
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)
            .padding()
        }
        .presentationDetentsIfAvailable(large: true)
    }

    // MARK: - Timer Settings Sheet

    @State private var settingsMins: Int = 25
    @State private var settingsMode: PresentationTimerMode = .countdown

    private var timerSettingsSheet: some View {
        NavigationView {
            Form {
                Section("Duration") {
                    HStack {
                        Text("Minutes")
                        Spacer()
                        TextField("", value: $settingsMins, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                    }
                    // Presets
                    let presets = [5, 10, 15, 20, 30, 60]
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                        ForEach(presets, id: \.self) { mins in
                            Button("\(mins) min") {
                                settingsMins = mins
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Mode") {
                    Picker("Timer Mode", selection: $settingsMode) {
                        Text("Countdown").tag(PresentationTimerMode.countdown)
                        Text("Count Up").tag(PresentationTimerMode.countup)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Timer Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { showTimerSettings = false }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Apply") {
                        let secs = max(1, settingsMins) * 60
                        timerDurationSecs = secs
                        timerModeRaw = settingsMode.rawValue
                        stopTimer()
                        timerElapsed = 0
                        showTimerSettings = false
                    }
                }
            }
            .onAppear {
                settingsMins = timerDurationSecs / 60
                settingsMode = timerMode
            }
        }
        .presentationDetentsIfAvailable()
    }
}

#Preview {
    let ble = BLEManager()
    let mouse = MouseManager(bleManager: ble)
    let keyboard = KeyboardManager(bleManager: ble)
    return PresentationView(
        keyboardManager: keyboard,
        mouseManager: mouse,
        orientationManager: OrientationManager()
    )
}
