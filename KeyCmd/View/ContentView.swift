//
//  ContentView.swift
//  KeyMod
//
//  Created by 彭志坚 on 2025/6/19.
//  Modified on 2025/6/21.
//

import SwiftUI
import CoreBluetooth
import UIKit

struct ContentView: View {
    @ObservedObject var launchPanelManager: LaunchPanelManager
    @StateObject private var bleManager: BLEManager
    @StateObject private var mouseManager: MouseManager
    @StateObject private var keyboardManager: KeyboardManager
    @StateObject private var orientationManager: OrientationManager
    @StateObject private var viewManager: ViewManager
    @StateObject private var clipboardManager: ClipboardManager
    @ObservedObject private var aiSettings = AISettings.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @State private var showPopup = false
    @State private var sidebarVisible = false
    @State private var showSettings = false
    @State private var showSetupSheet = false
    @State private var showProSetupSheet = false
    @State private var isGamepadEditMode = false
    @State private var showPresetPicker = false
    @State private var showBackgroundPicker = false
    @State private var showAddModulePicker = false
    @State private var showTargetOSDialog = false
    @StateObject private var presetRepository = GamepadPresetRepository()
    @StateObject private var backgroundManager = GamepadBackgroundManager()
    @StateObject private var gyroMouseManager: GyroMouseManager
    @AppStorage("gyroMouseEnabled") private var gyroMouseEnabled = false
    @AppStorage("gyroMouseSensitivity") private var gyroMouseSensitivity: Double = 1.0
    @State private var basicSubmode: BasicKeyboardMouseView.Submode = .touchpad
    @AppStorage("km_pro_submode") private var proSubmodeRaw: Int = 0
    
    init(launchPanelManager: LaunchPanelManager) {
        self.launchPanelManager = launchPanelManager
        let bleManager = BLEManager()
        let mouseManager = MouseManager(bleManager: bleManager)
        let keyboardManager = KeyboardManager(bleManager: bleManager)
        _bleManager = StateObject(wrappedValue: bleManager)
        _mouseManager = StateObject(wrappedValue: mouseManager)
        _keyboardManager = StateObject(wrappedValue: keyboardManager)
        _orientationManager = StateObject(wrappedValue: OrientationManager())
        _viewManager = StateObject(wrappedValue: ViewManager())
        _clipboardManager = StateObject(wrappedValue: ClipboardManager())
        let gyroManager = GyroMouseManager(mouseManager: mouseManager)
        gyroManager.sensitivity = UserDefaults.standard.double(forKey: "gyroMouseSensitivity") != 0 ? UserDefaults.standard.double(forKey: "gyroMouseSensitivity") : 1.0
        _gyroMouseManager = StateObject(wrappedValue: gyroManager)
    }
    
    // MARK: - Sidebar View
    private func sidebarView(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarHeader
            modifiersDisplay
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    sidebarNavigation
                    sidebarSettingsButton
                    sidebarReportBugButton
                    sidebarWelcomeGuideButton
                    sidebarSidebarLogo
                    sidebarVersionDisplay
                }
            }
        }
        .frame(width: width)
        .background(Color(UIColor.secondarySystemBackground))
        .transition(.move(edge: .leading))
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    if value.translation.width < -50 {
                        withAnimation {
                            sidebarVisible = false
                        }
                    }
                }
        )
    }
    
    private var sidebarHeader: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Button(action: {
                    withAnimation {
                        sidebarVisible.toggle()
                    }
                }) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.gray)
                        .scaleEffect(x: 0.65, y: 1, anchor: .center)
                }
                .buttonStyle(PlainButtonStyle())
                Image("keycmd_wordmark")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(height: 18)
                    .foregroundColor(.primary)
                    .accessibilityLabel(Text("KeyCmd"))
                    .onTapGesture {
                        withAnimation {
                            sidebarVisible.toggle()
                        }
                    }
            }
            // Mode indicator badge - Hidden as both modes now show all views
            /*
            HStack(spacing: 4) {
                Circle()
                    .fill(viewManager.currentMode == .basic ? Color.green : Color.purple)
                    .frame(width: 8, height: 8)
                Text(viewManager.currentMode.rawValue)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(viewManager.currentMode == .basic ? .green : .purple)
                    .textCase(.uppercase)
                Spacer()
                // Mode switch button
                Button(action: {
                    viewManager.switchToMode(viewManager.currentMode == .basic ? .pro : .basic)
                }) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 12))
                        .foregroundColor(themeManager.accentColor)
                }
            }
            .padding(.leading, 16)
            */
        }
        .padding(.vertical, 12)
        .padding(.leading, 16)
    }
    
    private var modifiersDisplay: some View {
        Group {
            if !keyboardManager.activeModifiers.isEmpty || keyboardManager.capsLockActive {
                HStack {
                    ForEach(Array(keyboardManager.activeModifiers), id: \.self) { modifier in
                        Text(modifier)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(4)
                    }
                    if keyboardManager.capsLockActive {
                        Text("CAPS")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(4)
                    }
                }
                .padding(.leading, 16)
                .padding(.bottom, 10)
            }
        }
    }
    
    private var sidebarNavigation: some View {
        ForEach(viewManager.currentMode.views, id: \.self) { viewType in
            Button(action: {
                viewManager.switchToView(viewType)
                // Exit edit mode when switching away from gamepad
                if viewType != .gamepad {
                    isGamepadEditMode = false
                }
                withAnimation {
                    sidebarVisible = false
                }
            }) {
                HStack {
                    Image(viewType.iconAssetName)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                        .foregroundColor(themeManager.accentColor)
                    Text(viewType.localizedName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    // Beta badge for experimental features
                    if viewType == .macros || viewType == .voiceInput || viewType == .terminal {
                        Image(systemName: "flask.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .padding(.leading, 4)
                    }
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 12)
                .background(viewManager.currentView == viewType ? themeManager.accentColor.opacity(0.15) : Color.clear)
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .id(viewManager.currentMode) // Force re-render when mode changes
    }
    
    // MARK: - Main Content View
    private var topSafeAreaInset: CGFloat {
        #if os(iOS)
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else { return 0 }
        return window.safeAreaInsets.top
        #else
        return 0
        #endif
    }

    private var mainContentView: some View {
        VStack(spacing: 0) {
            // Top bar: positioned below Dynamic Island
            topBar
                .padding(.top, max(0, topSafeAreaInset - 24))

            // Touch pad/numpad: fills remaining space below top bar
            mainContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(edges: [.bottom, .leading, .trailing])
        }
        .onAppear {
            LogManager.shared.log("MainContentView frame: maxWidth=.infinity, maxHeight=.infinity", category: "UI")
        }
    }
    
    private var topBar: some View {
        HStack {
            if !sidebarVisible {
                if viewManager.currentView == .gamepad {
                    gamepadTopBarButtons
                } else {
                    Button(action: {
                        withAnimation {
                            sidebarVisible.toggle()
                        }
                    }) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.gray)
                            .scaleEffect(x: 0.65, y: 1, anchor: .center)
                            .frame(width: 22, height: 44)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .padding(.leading, 12)
                    if viewManager.currentView == .keyboardMouseBasic {
                        BasicKeyboardMouseView(
                            mouseManager: mouseManager,
                            keyboardManager: keyboardManager,
                            orientationManager: orientationManager,
                            selectedSubmode: $basicSubmode
                        ).landscapeTabBar
                    }
                    if viewManager.currentView == .keyboardMousePro {
                        proSubmodeSelector
                        let currentSubmode = ProKeyboardMouseView.ProSubmode(rawValue: proSubmodeRaw) ?? .keyboard
                        if currentSubmode == .keyboard {
                            orientationToggleDivider
                            orientationToggleButton
                        }
                    }
                }
            }
            Spacer()
            topBarButtons
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .zIndex(100)
        .onAppear {
            LogManager.shared.log("TopBar rendered", category: "UI")
        }
    }

    @ViewBuilder private var proSubmodeSelector: some View {
        let current = ProKeyboardMouseView.ProSubmode(rawValue: proSubmodeRaw) ?? .keyboard
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                Button { proSubmodeRaw = ProKeyboardMouseView.ProSubmode.keyboard.rawValue } label: {
                    Image("ic_km_pro_submode_keyboard")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .foregroundColor(current == .keyboard ? .purple : .secondary)
                        .frame(width: 34, height: 34)
                }
                Button { proSubmodeRaw = ProKeyboardMouseView.ProSubmode.compose.rawValue } label: {
                    Image("ic_km_pro_submode_compose")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .foregroundColor(current == .compose ? .purple : .secondary)
                        .frame(width: 34, height: 34)
                }
                Button { proSubmodeRaw = ProKeyboardMouseView.ProSubmode.numpad.rawValue } label: {
                    Image("ic_km_pro_submode_numpad")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .foregroundColor(current == .numpad ? .purple : .secondary)
                        .frame(width: 34, height: 34)
                }
            }
        }
        .frame(width: 68)
        .clipped()
    }

    private var orientationToggleDivider: some View {
        Divider()
            .frame(height: 24)
            .padding(.horizontal, 4)
    }

    @ViewBuilder private var orientationToggleButton: some View {
        let currentSubmode = ProKeyboardMouseView.ProSubmode(rawValue: proSubmodeRaw) ?? .keyboard
        if currentSubmode == .keyboard {
            Button {
                orientationManager.toggleOrientationWithInstruction()
            } label: {
                Image(systemName: orientationManager.isLandscape ? "rectangle.portrait.arrowtriangle.2.inout" : "rectangle.arrowtriangle.2.inout")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 34, height: 34)
            }
        }
    }

    private var topBarButtons: some View {
        HStack(spacing: 10) {
            if viewManager.currentView == .gamepad {
                // Gamepad right-side controls
                // Gyro mouse toggle
                Button {
                    withAnimation {
                        gyroMouseEnabled.toggle()
                        if gyroMouseEnabled {
                            gyroMouseManager.enable()
                        } else {
                            gyroMouseManager.disable()
                        }
                    }
                } label: {
                    Image(systemName: gyroMouseManager.isEnabled ? "gyroscope.fill" : "gyroscope")
                        .font(.system(size: 16))
                        .foregroundColor(gyroMouseManager.isEnabled ? .cyan : .secondary)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)

                bleButton
            } else {
                targetOSButton
                // Show KM Basic setup button between targetOS and BLE
                if viewManager.currentView == .keyboardMouseBasic {
                    kmBasicSetupButton
                }
                // Show KM Pro setup button between targetOS and BLE
                if viewManager.currentView == .keyboardMousePro {
                    kmProSetupButton
                }
                bleButton
            }
        }
        .onAppear {
            LogManager.shared.log("TopBarButtons appeared - Current view: \(viewManager.currentView.rawValue)", category: "UI")
        }
    }

    private var kmBasicSetupButton: some View {
        Button(action: { showSetupSheet = true }) {
            Image(systemName: "gearshape")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
                .foregroundColor(.gray)
        }
        .frame(width: 34, height: 34)
        .background(Color.clear)
        .buttonStyle(.plain)
        .popover(isPresented: $showSetupSheet, arrowEdge: .top) {
            NavigationView {
                Form {
                    KmBasicSettingsView()
                }
                .navigationTitle("Setup")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") { showSetupSheet = false }
                    }
                }
            }
            .frame(minWidth: 320, idealWidth: 380, minHeight: 450)
        }
    }

    private var kmProSetupButton: some View {
        Button(action: { showProSetupSheet = true }) {
            Image(systemName: "gearshape")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
                .foregroundColor(.gray)
        }
        .frame(width: 34, height: 34)
        .background(Color.clear)
        .buttonStyle(.plain)
        .popover(isPresented: $showProSetupSheet, arrowEdge: .top) {
            NavigationView {
                Form {
                    KmProSettingsView(keyboardManager: keyboardManager)
                }
                .navigationTitle("Pro Setup")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") { showProSetupSheet = false }
                    }
                }
            }
            .frame(minWidth: 320, idealWidth: 380, minHeight: 500)
        }
    }

    // MARK: - Gamepad Top Bar Buttons (left side, replaces hamburger menu)

    @ViewBuilder
    private var gamepadTopBarButtons: some View {
        // 1. Menu button (opens sidebar)
        Button {
            withAnimation {
                sidebarVisible = true
            }
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.gray)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)

        // 2. Edit mode toggle
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isGamepadEditMode.toggle()
            }
        } label: {
            Image(systemName: isGamepadEditMode ? "checkmark.circle.fill" : "square.and.pencil")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(isGamepadEditMode ? .blue : .secondary)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)

        // 3. Presets cycle button
        Button {
            cycleToNextPreset()
        } label: {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)

        // 4. Active preset chip
        Button {
            showPresetPicker = true
        } label: {
            HStack(spacing: 3) {
                Text(currentPresetDisplayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(UIColor.tertiarySystemBackground).opacity(0.85))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)

        // Edit mode buttons (shown only in edit mode)
        if isGamepadEditMode {
            Divider().frame(height: 24)

            // Background picker
            Button {
                showBackgroundPicker = true
            } label: {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)

            // Add module
            Button {
                showAddModulePicker = true
            } label: {
                Image(systemName: "plus.circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)

            // Mapping hints toggle
            Button {
                // TODO: Toggle key mapping hints visibility
            } label: {
                Image(systemName: "eye")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
        }
    }

    private var targetOSButton: some View {
        Button(action: {
            showTargetOSDialog = true
        }) {
            Image(aiSettings.targetOS.imageName)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
                .foregroundColor(.gray)
        }
        .frame(width: 34, height: 34)
        .background(Color.clear)
        .buttonStyle(.plain)
    }

    private var targetOSSelectionSheet: some View {
        ZStack {
            Color.black.opacity(0.36)
                .ignoresSafeArea()
                .onTapGesture {
                    showTargetOSDialog = false
                }

            VStack(spacing: 18) {
                Text("Target OS")
                    .font(.headline)
                    .foregroundColor(.primary)

                HStack(spacing: 24) {
                    ForEach(TargetOS.allCases, id: \.self) { os in
                        Button {
                            aiSettings.targetOS = os
                            showTargetOSDialog = false
                        } label: {
                            Image(os.imageName)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .foregroundColor(aiSettings.targetOS == os ? .white : .primary)
                                .frame(width: 32, height: 32)
                                .padding(12)
                                .background(
                                    Circle()
                                        .fill(aiSettings.targetOS == os ? Color.accentColor : Color(UIColor.secondarySystemFill))
                                )
                                .overlay(
                                    Circle()
                                        .stroke(aiSettings.targetOS == os ? Color.accentColor : Color.clear, lineWidth: 2)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)

                Button(action: {
                    showTargetOSDialog = false
                }) {
                    Text("Cancel")
                        .font(.headline)
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(UIColor.systemBackground))
                        .cornerRadius(14)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 16)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(24)
            .frame(maxWidth: 360)
            .shadow(color: Color.black.opacity(0.25), radius: 20, x: 0, y: 12)
        }
    }

    private var bleButton: some View {
        Button(action: {
            showPopup = true
        }) {
            Image(systemName: bleIconName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
                .foregroundColor(bleManager.connectionState == .connected ? themeManager.accentColor : .gray)
        }
        .frame(width: 34, height: 34)
        .background(Color.clear)
        .buttonStyle(.plain)
    }

    private var bleIconName: String {
        switch bleManager.connectionState {
        case .connected: return "antenna.radiowaves.left.and.right"
        case .connecting, .reconnecting: return "antenna.radiowaves.left.and.right"
        case .disconnected: return "antenna.radiowaves.left.and.right"
        }
    }
    
    private var sidebarSettingsButton: some View {
        Button(action: {
            showSettings = true
            withAnimation {
                sidebarVisible = false
            }
        }) {
            HStack {
                Image("ic_settings")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .foregroundColor(themeManager.accentColor)
                Text("Settings")
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 12)
            .background(Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var sidebarWelcomeGuideButton: some View {
        Button(action: {
            withAnimation {
                sidebarVisible = false
            }
            launchPanelManager.showLaunchPanelAgain()
        }) {
            HStack {
                Text("WELCOME & GUIDE")
                    .font(.headline)
                    .foregroundColor(themeManager.accentColor)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 12)
            .background(Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var sidebarReportBugButton: some View {
        let url = URL(string: "https://docs.google.com/forms/d/e/1FAIpQLScTnJF_Pj_iIMvu8tBPaY_-n45-ffADUFAr8Ws-f6_TckWVTQ/viewform?usp=publish-editor")!
        return Button(action: {
            withAnimation {
                sidebarVisible = false
            }
            UIApplication.shared.open(url)
        }) {
            HStack {
                Image("chat_error")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .foregroundColor(themeManager.accentColor)
                Text("Report a Bug")
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 12)
            .background(Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var sidebarSidebarLogo: some View {
        Image("openterface_wordmark")
            .resizable()
            .renderingMode(.original)
            .scaledToFit()
            .frame(width: 90, height: 18)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
    }

    private var sidebarVersionDisplay: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return Text("v\(version) (\(build))")
            .font(.caption2)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    private var sidebarModeSelectionButton: some View {
        Button(action: {
            viewManager.switchToMode(viewManager.currentMode == .basic ? .pro : .basic)
            withAnimation {
                sidebarVisible = false
            }
        }) {
            HStack {
                Image(systemName: viewManager.currentMode == .basic ? "gearshape.circle.fill" : "sparkles")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .foregroundColor(themeManager.accentColor)
                Text(viewManager.currentMode == .basic ? "Switch to Pro" : "Switch to Basic")
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 12)
            .background(Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var mainContent: some View {
        ZStack {
            switch viewManager.currentView {
            case .keyboardMouseBasic:
                BasicKeyboardMouseView(
                    mouseManager: mouseManager,
                    keyboardManager: keyboardManager,
                    orientationManager: orientationManager,
                    selectedSubmode: $basicSubmode
                )
                .id(viewManager.currentView)
                .onAppear { LogManager.shared.log("[ContentView] BasicKeyboardMouseView appeared", category: "UI", level: .success) }
            case .keyboardMousePro:
                ProKeyboardMouseView(
                    mouseManager: mouseManager,
                    keyboardManager: keyboardManager,
                    compositeKeyManager: keyboardManager.compositeKeyManager,
                    orientationManager: orientationManager,
                    proSubmode: Binding(
                        get: { ProKeyboardMouseView.ProSubmode(rawValue: proSubmodeRaw) ?? .keyboard },
                        set: { proSubmodeRaw = $0.rawValue }
                    )
                )
                .id(viewManager.currentView)
            case .gamepad:
                Group {
                    if let _ = presetRepository.activeDocument {
                        let docBinding = Binding(
                            get: { self.presetRepository.activeDocument ?? GamepadPresetDocument() },
                            set: { self.presetRepository.updateDocument($0) }
                        )
                        GamepadDynamicCanvas(
                            document: docBinding,
                            keyboardManager: keyboardManager,
                            mouseManager: mouseManager,
                            backgroundManager: backgroundManager,
                            isEditMode: isGamepadEditMode,
                            isPositionEditMode: false,
                            isKeyMappingMode: false,
                            onSaveDocument: { self.presetRepository.saveActiveDocument() }
                        )
                        .id("dynamic_\(presetRepository.activePresetId ?? "none")")
                        .task(id: presetRepository.activePresetId ?? "") {
                            // Sync preset's background settings to background manager
                            if let doc = presetRepository.activeDocument {
                                backgroundManager.loadFromLayout(doc.layout)
                            }
                        }
                    } else {
                        Text("No preset available")
                    }
                }
                .id(viewManager.currentView)
                .onAppear {
                    LogManager.shared.log("Gamepad view appeared, locking landscape orientation", category: "UI")
                    orientationManager.lockToLandscape()
                    if !orientationManager.isLandscape {
                        orientationManager.toggleOrientationWithInstruction()
                    }
                }
                .onChange(of: presetRepository.activePresetId) { newId in
                    LogManager.shared.log("Active preset changed to: \(newId ?? "none")", category: "Gamepad")
                }
                .fullScreenCover(isPresented: $showPresetPicker) {
                    PresetPickerView(
                        repository: presetRepository,
                        isPresented: $showPresetPicker
                    )
                }
                .sheet(isPresented: $showBackgroundPicker) {
                    if #available(iOS 16.0, *) {
                        BackgroundPickerView(
                            manager: backgroundManager,
                            isPresented: $showBackgroundPicker,
                            onSave: {
                                // Save background settings back to the preset document's layout
                                if var doc = presetRepository.activeDocument {
                                    backgroundManager.saveToLayout(&doc.layout)
                                    presetRepository.updateDocument(doc)
                                }
                            }
                        )
                    }
                }
                .sheet(isPresented: $showAddModulePicker) {
                    AddModulePicker(
                        isPresented: $showAddModulePicker,
                        onAdd: { moduleType in
                            addModule(ofType: moduleType)
                        }
                    )
                }
            case .numpad:
                NumPadView(keyboardManager: keyboardManager, orientationManager: orientationManager)
                    .id(viewManager.currentView)
            case .shortcutHub:
                ShortcutHubView(keyboardManager: keyboardManager)
                    .id(viewManager.currentView)
            case .macros:
                MacroView(keyboardManager: keyboardManager)
                    .id(viewManager.currentView)
            case .voiceInput:
                VoiceInputView(keyboardManager: keyboardManager)
                    .id(viewManager.currentView)
            case .presentation:
                PresentationView(
                    keyboardManager: keyboardManager,
                    mouseManager: mouseManager,
                    orientationManager: orientationManager
                )
                .id(viewManager.currentView)
            case .terminal:
                TerminalContainerView(bleManager: bleManager)
                    .id(viewManager.currentView)
            }
        }
        .onAppear {
            LogManager.shared.log("MainContent view type: \(viewManager.currentView.rawValue)", category: "UI")
            LogManager.shared.log("Frame: maxWidth=.infinity, maxHeight=.infinity", category: "UI")
        }
        .onTapGesture {
        }
        .onChange(of: viewManager.currentView) { newView in
            LogManager.shared.log("View switched to: \(newView.rawValue)", category: "UI")
            if newView == .gamepad {
                // Entering gamepad: enable game mode and clear stale key state
                // from any previous view (keyboard/mouse could leave modifiers or
                // pressed keys active).
                keyboardManager.releaseAllKeys()
                keyboardManager.switchToGameMode()
            } else {
                // Leaving gamepad: disable gyro and restore normal keyboard mode
                gyroMouseManager.disable()
                keyboardManager.switchToNormalMode()
            }
        }
        .onChange(of: gyroMouseSensitivity) { newValue in
            gyroMouseManager.sensitivity = newValue
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                mainContentView
                if sidebarVisible {
                    Color.black.opacity(0.25)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation {
                                sidebarVisible = false
                            }
                        }
                        .accessibilityHidden(true)
                    sidebarView(width: geometry.size.width * 2 / 3)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onEnded { value in
                        let startedAtLeftEdge = value.startLocation.x < 20
                        let movedRight = value.translation.width > 50
                        if startedAtLeftEdge && movedRight && !sidebarVisible {
                            withAnimation {
                                sidebarVisible = true
                            }
                        }
                    }
            )
            .background(Color(UIColor.systemBackground))
            .statusBarHidden(true)
            .onAppear {
                LogManager.shared.log("GEOMETRY DEBUG:", category: "UI")
                LogManager.shared.log("Screen size: \(geometry.size.width) x \(geometry.size.height)", category: "UI")
                LogManager.shared.log("Safe area: top=\(geometry.safeAreaInsets.top), bottom=\(geometry.safeAreaInsets.bottom), leading=\(geometry.safeAreaInsets.leading), trailing=\(geometry.safeAreaInsets.trailing)", category: "UI")
                LogManager.shared.log("Window scene: \(UIApplication.shared.connectedScenes.first)", category: "UI")
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                    LogManager.shared.log("Window size: \(windowScene.windows.first?.bounds.size ?? .zero)", category: "UI")
                    LogManager.shared.log("Screen bounds: \(UIScreen.main.bounds.size)", category: "UI")
                    LogManager.shared.log("Screen scale: \(UIScreen.main.scale)", category: "UI")
                }
            }
            .onChange(of: geometry.size) { newSize in
                LogManager.shared.log("Geometry changed: \(newSize.width) x \(newSize.height)", category: "UI")
            }
            .overlay(
                // Orientation instruction overlay
                Group {
                    if orientationManager.showOrientationInstruction {
                        VStack {
                            Image(systemName: "rotate.3d")
                                .font(.system(size: 40))
                                .foregroundColor(.orange)
                            Text(orientationManager.instructionText)
                                .font(.headline)
                                .multilineTextAlignment(.center)
                                .padding()
                        }
                        .padding(20)
                        .background(Color(UIColor.systemBackground).opacity(0.95))
                        .cornerRadius(15)
                        .shadow(radius: 10)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            )
            .overlay(
                // Clipboard detection prompt overlay
                ClipboardPromptView(
                    clipboardManager: clipboardManager,
                    keyboardManager: keyboardManager
                )
            )
            .sheet(isPresented: $showPopup) {
                ConnectionDialogView(bleManager: bleManager)
                    .onAppear {
                        if viewManager.currentView == .gamepad {
                            orientationManager.lockToLandscape()
                            if !orientationManager.isLandscape {
                                orientationManager.toggleOrientationWithInstruction()
                            }
                        }
                    }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .overlay(
                Group {
                    if showTargetOSDialog {
                        targetOSSelectionSheet
                    }
                }
            )
            .onChange(of: showPopup) { isPresented in
                if isPresented && viewManager.currentView == .gamepad {
                    orientationManager.lockToLandscape()
                    if !orientationManager.isLandscape {
                        orientationManager.toggleOrientationWithInstruction()
                    }
                }
            }
            .onAppear {
                bleManager.showPopupBinding = $showPopup
                mouseManager.bleManager = bleManager
                keyboardManager.bleManager = bleManager
                viewManager.setKeyboardManager(keyboardManager) // Set keyboard manager reference

                // Start clipboard monitoring
                clipboardManager.startMonitoring()
                
                // Auto-connect to Bluetooth on app startup (with delay to ensure BLE manager is ready)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    if bleManager.checkBluetoothPermission() {
                        bleManager.startScanning()
                        showPopup = true
                        LogManager.shared.log("Auto-starting Bluetooth scan on app launch", category: "BLE")
                    } else {
                        LogManager.shared.log("Bluetooth permission not granted", category: "BLE", level: .warning)
                    }
                }
                
                // If user selected a mode from launch panel, switch to it
                if !launchPanelManager.showLaunchPanel && launchPanelManager.selectedMode != .keyboardMouseBasic {
                    viewManager.switchToView(launchPanelManager.selectedMode)
                }
                
                viewManager.onViewChange = { viewType in
                    if viewType == .gamepad {
                        orientationManager.lockToLandscape()
                        // Only show instruction if not already landscape
                        if !orientationManager.isLandscape {
                            orientationManager.toggleOrientationWithInstruction()
                        }
                        // Restore gyro mouse state if previously enabled
                        if gyroMouseEnabled {
                            gyroMouseManager.enable()
                        }
                    } else if viewType == .presentation {
                        orientationManager.lockToPortrait()
                        // Stop gyro when leaving gamepad
                        gyroMouseManager.disable()
                    } else if viewType == .keyboardMousePro {
                        // Pro keyboard submode manages its own orientation —
                        // just unlock so the submode's logic takes over.
                        orientationManager.savedDeviceOrientation = nil
                        let submode = ProKeyboardMouseView.ProSubmode(rawValue: proSubmodeRaw) ?? .keyboard
                        if submode == .keyboard {
                            orientationManager.unlockOrientation()
                        } else {
                            orientationManager.lockToPortrait()
                        }
                    }
                    // .keyboardMouseBasic manages its own orientation per submode
                }
                // Initial setup if app launches directly into Gamepad view
                // Initial orientation based on view and submode
                if viewManager.currentView == .gamepad {
                    orientationManager.lockToLandscape()
                    keyboardManager.switchToGameMode()
                } else if viewManager.currentView == .keyboardMousePro {
                    let submode = ProKeyboardMouseView.ProSubmode(rawValue: proSubmodeRaw) ?? .keyboard
                    switch submode {
                    case .compose, .numpad:
                        orientationManager.lockToPortrait()
                    case .keyboard:
                        orientationManager.unlockOrientation()
                    }
                    // Set initial normal mode for other views
                    keyboardManager.switchToNormalMode()
                }
            }
            .onChange(of: launchPanelManager.showLaunchPanel) { isShowing in
                // When the panel is dismissed, navigate to whatever mode the user selected
                if !isShowing {
                    viewManager.switchToView(launchPanelManager.selectedMode)
                }
            }
            .onChange(of: proSubmodeRaw) { newValue in
                let submode = ProKeyboardMouseView.ProSubmode(rawValue: newValue) ?? .keyboard
                switch submode {
                case .compose, .numpad:
                    // Compose and Numpad are portrait-only — force rotation
                    orientationManager.lockToPortrait()
                case .keyboard:
                    // Restore the physical orientation that was saved before forcing portrait
                    orientationManager.restoreOrientation()
                }
            }
            .onChange(of: orientationManager.isLandscape) { isLandscape in
                // If in compose/numpad and device rotated to landscape, force back to portrait.
                // Only apply this guard when the current view is actually the Pro keyboard —
                // proSubmodeRaw is persisted via @AppStorage and keeps its last value even
                // after switching to other views (gamepad, basic keyboard, etc.), so checking
                // it alone would cause a stale portrait lock that overwrites landscape views.
                if isLandscape, viewManager.currentView == .keyboardMousePro {
                    let submode = ProKeyboardMouseView.ProSubmode(rawValue: proSubmodeRaw) ?? .keyboard
                    if submode == .compose || submode == .numpad {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            orientationManager.lockToPortrait()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Preset Cycling

    private func cycleToNextPreset() {
        let presets = presetRepository.presets
        guard !presets.isEmpty else { return }
        let activeId = presetRepository.activePresetId
        let idx = presets.firstIndex { $0.id == activeId } ?? 0
        let nextIdx = (idx + 1) % presets.count
        presetRepository.activatePreset(id: presets[nextIdx].id)
    }

    private var currentPresetDisplayName: String {
        if let doc = presetRepository.activeDocument {
            return doc.meta.displayName
        }
        return "No Preset"
    }

    // MARK: - Add Module

    private func addModule(ofType type: AddModuleType) {
        guard var doc = presetRepository.activeDocument else { return }
        var newModule: GamepadModule
        let existingIds = Set(doc.modules.map { $0.id })

        switch type {
        case .dpadStick:
            let existing = doc.modules.filter { $0.type == .dpad || $0.type == .analogStick }
            let num = existing.count + 1
            var id = "stick_left_\(num)"
            var n = num
            while existingIds.contains(id) {
                n += 1
                id = "stick_left_\(n)"
            }
            newModule = GamepadModule(
                id: id, type: .dpad,
                anchorX: 0.20, anchorY: 0.50,
                dpadVariant: "cross",
                stickUpKey: "W", stickLeftKey: "A", stickDownKey: "S", stickRightKey: "D"
            )
            newModule.derivedKey = "W"

        case .button:
            let existingButtons = doc.modules.filter { $0.type == .button }
            var num = existingButtons.count + 1
            var id = "button_\(num)"
            while existingIds.contains(id) {
                num += 1
                id = "button_\(num)"
            }
            newModule = GamepadModule(
                id: id, type: .button,
                anchorX: 0.50, anchorY: 0.55,
                hidKey: 40, derivedKey: "Enter", displayLabel: "Btn \(num)"
            )
            if let firstButton = doc.modules.first(where: { $0.type == .button }) {
                newModule.scale = firstButton.scale
            }

        case .touchpad:
            let existing = doc.modules.filter { $0.type == .touchpad }
            var num = existing.count + 1
            var id = "touchpad_\(num)"
            while existingIds.contains(id) {
                num += 1
                id = "touchpad_\(num)"
            }
            newModule = GamepadModule(
                id: id, type: .touchpad,
                anchorX: 0.50, anchorY: 0.35,
                widthNorm: 0.28, heightNorm: 0.28
            )

        case .scrollStrip:
            let existing = doc.modules.filter { $0.type == .scrollStrip }
            let num = existing.count + 1
            var id = "scroll_strip_\(num)"
            var n = num
            while existingIds.contains(id) {
                n += 1
                id = "scroll_strip_\(n)"
            }
            let baseX = 0.06 + Double(n - 1) * 0.10
            newModule = GamepadModule(
                id: id, type: .scrollStrip,
                anchorX: baseX, anchorY: 0.48,
                scrollStripSensitivity: 1.0,
                widthNorm: 0.10, heightNorm: 0.36
            )
            newModule.displayLabel = "Wheel"
        }

        var updatedDoc = doc
        updatedDoc.modules.append(newModule)
        presetRepository.updateDocument(updatedDoc)
        presetRepository.saveActiveDocument()
    }
}

#Preview {
    ContentView(launchPanelManager: LaunchPanelManager())
}
