//
//  ViewManager.swift
//  KeyMod
//
//  Created by System on 2025/6/21.
//

import SwiftUI

/// Matches Android's Basic vs Pro mode distinction
enum ViewMode: String, CaseIterable, Identifiable {
    case basic = "Basic"
    case pro = "Pro"

    var id: String { rawValue }

    /// Sub-navigation views for each mode
    var views: [ViewType] {
        switch self {
        case .basic:
            return [.keyboardMouseBasic, .keyboardMousePro, .presentation, .gamepad, .shortcutHub, .macros, .voiceInput]
        case .pro:
            return [.keyboardMouseBasic, .keyboardMousePro, .presentation, .gamepad, .shortcutHub, .macros, .voiceInput]
        }
    }
}

enum ViewType: String, CaseIterable {
    case keyboardMouseBasic = "Keyboard & Mouse"
    case keyboardMousePro = "Keyboard & Mouse Pro"
    case gamepad = "Gamepad"
    case numpad = "Numpad"
    case shortcutHub = "Shortcuts"
    case macros = "Macros"
    case voiceInput = "Voice Input"
    case presentation = "Presentation"

    var iconName: String {
        switch self {
        case .keyboardMouseBasic, .keyboardMousePro:
            return "keyboard"
        case .gamepad:
            return "gamecontroller"
        case .numpad:
            return "grid.circle"
        case .shortcutHub:
            return "square.grid.2x2"
        case .macros:
            return "square.and.pencil"
        case .voiceInput:
            return "mic.circle"
        case .presentation:
            return "play.rectangle"
        }
    }

    var mode: ViewMode {
        switch self {
        case .keyboardMouseBasic, .gamepad, .numpad, .macros, .voiceInput:
            return .basic
        case .keyboardMousePro, .shortcutHub, .presentation:
            return .pro
        }
    }

    static func fromStoredRawValue(_ rawValue: String) -> ViewType? {
        if let viewType = ViewType(rawValue: rawValue) {
            return viewType
        }

        switch rawValue {
        case "Blender Shortcuts", "KiCAD Shortcuts":
            return .shortcutHub
        default:
            return nil
        }
    }
}

class ViewManager: ObservableObject {
    @Published var currentView: ViewType = .keyboardMouseBasic
    @Published var currentMode: ViewMode = .basic {
        didSet {
            UserDefaults.standard.set(currentMode.rawValue, forKey: "viewMode")
            // When mode changes, switch to the first view in that mode
            if let firstView = currentMode.views.first {
                currentView = firstView
            }
        }
    }
    var onViewChange: ((ViewType) -> Void)?
    var keyboardManager: KeyboardManager?

    private let userDefaults = UserDefaults.standard
    private let lastViewKey = "LastSelectedView"
    private let modeKey = "viewMode"

    init() {
        loadLastView()
    }

    private func loadLastView() {
        // Load saved mode
        if let savedModeRaw = userDefaults.string(forKey: modeKey),
           let savedMode = ViewMode(rawValue: savedModeRaw) {
            currentMode = savedMode
        }

        // Load saved view
        currentView = .keyboardMouseBasic
        /*
        if let savedViewRawValue = userDefaults.string(forKey: lastViewKey),
           let savedView = ViewType.fromStoredRawValue(savedViewRawValue) {
            currentView = savedView
        }
        */
    }

    private func saveCurrentView() {
        userDefaults.set(currentView.rawValue, forKey: lastViewKey)
    }

    func switchToView(_ viewType: ViewType) {
        // Update mode to match the view
        currentMode = viewType.mode

        currentView = viewType
        saveCurrentView()

        // Automatically switch keyboard mode based on view
        if let keyboardManager = keyboardManager {
            if viewType == .gamepad {
                keyboardManager.switchToGameMode()
            } else {
                keyboardManager.switchToNormalMode()
            }
        }

        onViewChange?(viewType)
    }

    func switchToMode(_ mode: ViewMode) {
        if currentMode == mode { return }
        currentMode = mode
        // Switch to the keyboard view of the new mode
        switch mode {
        case .basic:
            switchToView(.keyboardMouseBasic)
        case .pro:
            switchToView(.keyboardMousePro)
        }
    }

    func setKeyboardManager(_ keyboardManager: KeyboardManager) {
        self.keyboardManager = keyboardManager
    }
}
