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
        case .countdown: return CGFloat(timerElapsed) / CGFloat(timerDurationSecs)
        case .countup:   return CGFloat(timerElapsed) / CGFloat(max(timerDurationSecs, 1))
        }
    }

    private var targetOS: TargetOS { AISettings.shared.targetOS }

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

                Spacer(minLength: 12)

                slideNavButtons
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)

                actionRow
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)

                utilRow
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
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
        return VStack(spacing: 4) {
            Image(systemName: tool.iconName)
                .font(.system(size: 22, weight: selected ? .bold : .regular))
                .foregroundColor(selected ? .white : .secondary)
                .frame(width: 44, height: 44)
                .background(selected ? Color.blue : Color(UIColor.secondarySystemBackground))
                .clipShape(Circle())
            Text(tool.displayName)
                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                .foregroundColor(selected ? .blue : .secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 60)
        }
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

        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Progress fill
                Rectangle()
                    .fill((running ? Color.blue : Color.gray).opacity(running ? 0.18 : 0.10))
                    .frame(width: geo.size.width * fraction)
                    .animation(.linear(duration: 1.0), value: fraction)

                // Text content
                VStack(spacing: 4) {
                    Text(label)
                        .font(.system(size: 42, weight: .bold, design: .monospaced))
                        .foregroundColor(overtime ? .red : .primary)
                    Text(timerMode == .countdown ? "Countdown" : "Count Up")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        haptic.triggerMediumFeedback()
        stopTimer()
        timerElapsed = 0
        startTimer()
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
        HStack(spacing: 8) {
            // PREVIOUS – 1/3 width
            Button {
                haptic.triggerButtonPress()
                keyboardManager.handleKeyPress("Left")
            } label: {
                Text("◀  PREV")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color.gray.opacity(0.7))
                    .cornerRadius(10)
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                    haptic.triggerMediumFeedback()
                    keyboardManager.handleKeyPress("Home")
                }
            )
            .frame(maxWidth: .infinity)

            // NEXT – 2/3 width
            Button {
                haptic.triggerButtonPress()
                keyboardManager.handleKeyPress("Right")
            } label: {
                Text("NEXT  ▶")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color.blue)
                    .cornerRadius(10)
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                    haptic.triggerMediumFeedback()
                    keyboardManager.handleKeyPress("End")
                }
            )
            .frame(maxWidth: .infinity)
            .frame(maxWidth: .infinity) // second modifier makes it 2x weight in HStack
        }
        // Override weights: PREV=1, NEXT=2
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Action Row (Play / Black Screen)

    private var actionRow: some View {
        HStack(spacing: 8) {
            // Play / Stop
            Button {
                haptic.triggerButtonPress()
                togglePlay()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: playActive ? "stop.fill" : "play.fill")
                    Text(playActive ? "Stop" : "Play")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(playActive ? Color.red : Color.green)
                .cornerRadius(10)
            }

            // Hide / Show Screen (Black Screen)
            Button {
                guard playActive else { return }
                haptic.triggerButtonPress()
                showScreen.toggle()
                keyboardManager.handleKeyPress("b")
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showScreen ? "eye.slash" : "eye")
                    Text(showScreen ? "Hide" : "Show")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(playActive ? Color.indigo : Color.gray.opacity(0.5))
                .cornerRadius(10)
            }
            .disabled(!playActive)
        }
    }

    // MARK: - Util Row (App Switcher / Pointer)

    private var utilRow: some View {
        HStack(spacing: 8) {
            // App Switcher
            Button {
                haptic.triggerButtonPress()
                handleAppSwitcherTap()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.on.square")
                    Text(switcherState == .closed ? "Switcher" : "Release")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(switcherState == .open ? Color.green : Color.orange)
                .cornerRadius(10)
            }

            // Pointer / Touchpad
            Button {
                haptic.triggerButtonPress()
                showTouchpad = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "cursorarrow.motionlines")
                    Text("Pointer")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color.teal)
                .cornerRadius(10)
            }
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
            // Start presentation
            guard let modifiers = selectedTool.playModifiers,
                  let key = selectedTool.playKey else {
                return // tool has no play shortcut
            }
            playActive = true
            keyboardManager.handleKeyCombo(modifiers: modifiers, key: key)
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
