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
    @State private var showPopup = false
    @State private var sidebarVisible = false
    @State private var showSettings = false
    @State private var showSetupSheet = false
    @State private var showProSetupSheet = false
    @State private var isGamepadEditMode = false
    @State private var showPresetPicker = false
    @State private var showBackgroundPicker = false
    @State private var showAddModulePicker = false
    @StateObject private var presetRepository = GamepadPresetRepository()
    @StateObject private var backgroundManager = GamepadBackgroundManager()
    @StateObject private var gyroMouseManager: GyroMouseManager
    @AppStorage("gyroMouseEnabled") private var gyroMouseEnabled = false
    @AppStorage("gyroMouseSensitivity") private var gyroMouseSensitivity: Double = 1.0
    @State private var basicSubmode: BasicKeyboardMouseView.Submode = .keyboard
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
    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarHeader
            modifiersDisplay
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    sidebarNavigation
                    sidebarSettingsButton
                    sidebarWelcomeGuideButton
                    sidebarSidebarLogo
                    sidebarVersionDisplay
                }
            }
        }
        .frame(width: 180)
        .background(Color(UIColor.secondarySystemBackground))
        .transition(.move(edge: .leading))
    }
    
    private var sidebarHeader: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Button(action: {
                    withAnimation {
                        sidebarVisible.toggle()
                    }
                }) {
                    Image(systemName: "ellipsis")
                        .rotationEffect(.degrees(90))
                        .font(.title2)
                        .foregroundColor(.primary)
                }
                .buttonStyle(PlainButtonStyle())
                Text("KeyMod")
                    .font(.headline)
                    .foregroundColor(.primary)
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
                        .foregroundColor(.blue)
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
                    Image(systemName: viewType.iconName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                        .foregroundColor(viewManager.currentView == viewType ? .green : .blue)
                    Text(viewType.rawValue)
                        .font(.body)
                        .foregroundColor(viewManager.currentView == viewType ? .green : .primary)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(viewManager.currentView == viewType ? Color.green.opacity(0.15) : Color.clear)
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .id(viewManager.currentMode) // Force re-render when mode changes
    }
    
    // MARK: - Main Content View
    private var mainContentView: some View {
        VStack(spacing: 0) {
            topBar
                .onAppear {
                    print("🔝 TopBar appeared")
                }
            mainContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.all, edges: [.bottom, .leading, .trailing])
                .onAppear {
                    print("📱 MainContent appeared")
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            print("📦 MainContentView frame: maxWidth=.infinity, maxHeight=.infinity")
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
                        Image(systemName: "ellipsis")
                            .rotationEffect(.degrees(90))
                            .font(.title2)
                            .foregroundColor(.primary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .padding(.leading, 12)
                    if orientationManager.isLandscape && viewManager.currentView == .keyboardMouseBasic {
                        BasicKeyboardMouseView(
                            mouseManager: mouseManager,
                            keyboardManager: keyboardManager,
                            orientationManager: orientationManager,
                            selectedSubmode: $basicSubmode
                        ).landscapeTabBar
                    }
                    if viewManager.currentView == .keyboardMousePro {
                        proSubmodeSelector
                    }
                }
            }
            Spacer()
            topBarButtons
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(height: 50)
        .background(
            GeometryReader { geo in
                Color(UIColor.secondarySystemBackground)
                    .onAppear {
                        let globalFrame = geo.frame(in: .global)
                        print("🔝 TopBar global frame: origin=\(globalFrame.origin) size=\(globalFrame.size)")
                    }
            }
        )
        .zIndex(100)
        .onAppear {
            print("🔝 TopBar rendered with height: 50")
        }
    }

    @ViewBuilder private var proSubmodeSelector: some View {
        let current = ProKeyboardMouseView.ProSubmode(rawValue: proSubmodeRaw) ?? .keyboard
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                Button { proSubmodeRaw = ProKeyboardMouseView.ProSubmode.keyboard.rawValue } label: {
                    Image(systemName: "keyboard")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(current == .keyboard ? .purple : .secondary)
                        .frame(width: 34, height: 34)
                }
                Button { proSubmodeRaw = ProKeyboardMouseView.ProSubmode.compose.rawValue } label: {
                    Image(systemName: "pencil.and.outline")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(current == .compose ? .purple : .secondary)
                        .frame(width: 34, height: 34)
                }
                Button { proSubmodeRaw = ProKeyboardMouseView.ProSubmode.numpad.rawValue } label: {
                    Image(systemName: "0.square")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(current == .numpad ? .purple : .secondary)
                        .frame(width: 34, height: 34)
                }
            }
        }
        .frame(width: 68)
        .clipped()
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
                    Image(systemName: gyroMouseManager.isEnabled ? "motion.sensor.fill" : "motion.sensor")
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
            print("🎯 TopBarButtons appeared - Current view: \(viewManager.currentView.rawValue)")
        }
    }

    private var kmBasicSetupButton: some View {
        VStack(spacing: 2) {
            Button(action: { showSetupSheet = true }) {
                Image(systemName: "gearshape")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .foregroundColor(.gray)
            }
            .frame(width: 34, height: 34)
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
            Text("Setup")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var kmProSetupButton: some View {
        VStack(spacing: 2) {
            Button(action: { showProSetupSheet = true }) {
                Image(systemName: "gearshape")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .foregroundColor(.gray)
            }
            .frame(width: 34, height: 34)
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
            Text("Setup")
                .font(.caption2)
                .foregroundColor(.secondary)
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
                .foregroundColor(.primary)
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
        VStack(spacing: 2) {
            Menu {
                ForEach(TargetOS.allCases, id: \.self) { os in
                    Button(action: {
                        aiSettings.targetOS = os
                    }) {
                        HStack {
                            Label(os.displayName, systemImage: os.systemImage)
                            if aiSettings.targetOS == os {
                                Spacer()
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: aiSettings.targetOS.systemImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .foregroundColor(.purple)
            }
            .frame(width: 34, height: 34)
            .background(Color.clear)
            Text(aiSettings.targetOS.shortName)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var bleButton: some View {
        VStack(spacing: 2) {
            Button(action: {
                if bleManager.checkBluetoothPermission() {
                    bleManager.startScanning()
                    showPopup = true
                    print("Scanning for Bluetooth devices...")
                } else {
                    print("Bluetooth permission not granted")
                }
            }) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .foregroundColor(bleManager.connectedDevices.isEmpty ? .blue : .green)
            }
            .frame(width: 34, height: 34)
            .background(Color.clear)
            if let rssi = bleManager.currentRSSI {
                Text("\(rssi.intValue) dBm")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            print("📡 BLEButton rendered")
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
                Image(systemName: "gearshape.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .foregroundColor(.gray)
                Text("Settings")
                    .font(.body)
                    .foregroundColor(.primary)
            }
            .padding(.vertical, 10)
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
                Image(systemName: "book.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .foregroundColor(.blue)
                Text("Welcome & Guide")
                    .font(.body)
                    .foregroundColor(.primary)
            }
            .padding(.vertical, 10)
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
                    .foregroundColor(.blue)
                Text(viewManager.currentMode == .basic ? "Switch to Pro" : "Switch to Basic")
                    .font(.body)
                    .foregroundColor(.primary)
            }
            .padding(.vertical, 10)
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
                .onAppear { print("🟢 [ContentView] BasicKeyboardMouseView appeared") }
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
                    print("🎮 Gamepad view appeared, locking landscape orientation")
                    orientationManager.lockToLandscape()
                    if !orientationManager.isLandscape {
                        orientationManager.toggleOrientationWithInstruction()
                    }
                }
                .onChange(of: presetRepository.activePresetId) { newId in
                    print("🔄 Active preset changed to: \(newId ?? "none")")
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
            }
        }
        .onAppear {
            print("🎮 MainContent view type: \(viewManager.currentView.rawValue)")
            print("   Frame: maxWidth=.infinity, maxHeight=.infinity")
        }
        .onTapGesture {
        }
        .onChange(of: viewManager.currentView) { newView in
            print("🔄 View switched to: \(newView.rawValue)")
            if newView != .gamepad {
                // Stop gyro when leaving gamepad view
                gyroMouseManager.disable()
            }
        }
        .onChange(of: gyroMouseSensitivity) { newValue in
            gyroMouseManager.sensitivity = newValue
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                if sidebarVisible {
                    sidebarView
                }
                mainContentView
            }
            .background(Color(UIColor.systemBackground))
            .statusBarHidden(true)
            .onAppear {
                print("📐 GEOMETRY DEBUG:")
                print("  Screen size: \(geometry.size.width) x \(geometry.size.height)")
                print("  Safe area: top=\(geometry.safeAreaInsets.top), bottom=\(geometry.safeAreaInsets.bottom), leading=\(geometry.safeAreaInsets.leading), trailing=\(geometry.safeAreaInsets.trailing)")
                print("  Window scene: \(UIApplication.shared.connectedScenes.first)")
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                    print("  Window size: \(windowScene.windows.first?.bounds.size ?? .zero)")
                    print("  Screen bounds: \(UIScreen.main.bounds.size)")
                    print("  Screen scale: \(UIScreen.main.scale)")
                }
            }
            .onChange(of: geometry.size) { newSize in
                print("🔄 Geometry changed: \(newSize.width) x \(newSize.height)")
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
                List(bleManager.discoveredDevices, id: \.0.identifier) { device, rssi in
                    VStack(alignment: .leading) {
                        Text(device.name ?? "Unknown Device")
                            .font(.headline)
                            .foregroundColor(bleManager.connectedDevices.contains(device.identifier) ? .green : .primary)
                        Text("RSSI: \(rssi.stringValue)")
                            .font(.footnote)
                            .foregroundColor(.blue)
                        Text("UUID: \(device.identifier.uuidString)")
                            .font(.footnote)
                            .foregroundColor(.gray)
                    }
                    .onTapGesture {
                        bleManager.connectToDevice(device)
                    }
                }
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
                        print("🔵 Auto-starting Bluetooth scan on app launch")
                    } else {
                        print("⚠️ Bluetooth permission not granted")
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
                // If in compose/numpad and device rotated to landscape, force back to portrait
                if isLandscape {
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

        switch type {
        case .dpadStick:
            // Android: stick_left, type=DPAD, variant=cross, WASD keys (HID: W=26, A=4, S=22, D=7)
            let id = "stick_left"
            newModule = GamepadModule(
                id: id, type: .dpad,
                anchorX: 0.20, anchorY: 0.50,
                dpadVariant: "cross",
                stickUpKey: "W", stickLeftKey: "A", stickDownKey: "S", stickRightKey: "D"
            )
            // Derive key from default Up key
            newModule.derivedKey = "W"

        case .button:
            // Android: button_N, hidKey=40 (Enter), displayLabel="Btn"
            let existingButtons = doc.modules.filter { $0.type == .button }
            let nextNum = existingButtons.count + 1
            newModule = GamepadModule(
                id: "button_\(nextNum)", type: .button,
                anchorX: 0.50, anchorY: 0.55,
                hidKey: 40, derivedKey: "Enter", displayLabel: "Btn"
            )
            // Match scale of existing buttons if any
            if let firstButton = doc.modules.first(where: { $0.type == .button }) {
                newModule.scale = firstButton.scale
            }

        case .touchpad:
            // Android: touchpad_N, widthNorm=0.28, heightNorm=0.28
            let existing = doc.modules.filter { $0.type == .touchpad }
            let num = existing.count + 1
            newModule = GamepadModule(
                id: "touchpad_\(num)", type: .touchpad,
                anchorX: 0.50, anchorY: 0.35,
                widthNorm: 0.28, heightNorm: 0.28
            )

        case .scrollStrip:
            // Android: scroll_strip_N, widthNorm=0.10, heightNorm=0.36, displayLabel="Wheel"
            let existing = doc.modules.filter { $0.type == .scrollStrip }
            let num = existing.count + 1
            let baseX = 0.06 + Double(num - 1) * 0.10
            newModule = GamepadModule(
                id: "scroll_strip_\(num)", type: .scrollStrip,
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
