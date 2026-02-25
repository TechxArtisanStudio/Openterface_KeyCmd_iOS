//
//  ViewManager.swift
//  KeyMod
//
//  Created by System on 2025/6/21.
//

import SwiftUI

enum ViewType: String, CaseIterable {
    case keyboardMouse = "Keyboard & Mouse"
    case gamepad = "Gamepad"
    case numpad = "Numpad"
    case blenderShortcuts = "Blender Shortcuts"
    case kicadShortcuts = "KiCAD Shortcuts"
    case macros = "Macros"
    
    var iconName: String {
        switch self {
        case .keyboardMouse:
            return "keyboard"
        case .gamepad:
            return "gamecontroller"
        case .numpad:
            return "grid.circle"
        case .blenderShortcuts:
            return "cube.box"
        case .kicadShortcuts:
            return "cpu"
        case .macros:
            return "square.and.pencil"
        }
    }
}

class ViewManager: ObservableObject {
    @Published var currentView: ViewType = .keyboardMouse
    var onViewChange: ((ViewType) -> Void)?
    var keyboardManager: KeyboardManager?
    
    private let userDefaults = UserDefaults.standard
    private let lastViewKey = "LastSelectedView"
    
    init() {
        loadLastView()
    }
    
    private func loadLastView() {
        if let savedViewRawValue = userDefaults.string(forKey: lastViewKey),
           let savedView = ViewType(rawValue: savedViewRawValue) {
            currentView = savedView
        }
    }
    
    private func saveCurrentView() {
        userDefaults.set(currentView.rawValue, forKey: lastViewKey)
    }
    
    func switchToView(_ viewType: ViewType) {
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
    
    func setKeyboardManager(_ keyboardManager: KeyboardManager) {
        self.keyboardManager = keyboardManager
    }
}
