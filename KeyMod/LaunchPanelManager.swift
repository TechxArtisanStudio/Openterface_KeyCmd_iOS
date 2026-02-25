//
//  LaunchPanelManager.swift
//  KeyMod
//
//  Created by GitHub Copilot on 2026/2/25.
//

import SwiftUI

class LaunchPanelManager: ObservableObject {
    @Published var showLaunchPanel = false
    @Published var selectedMode: ViewType = .keyboardMouse
    
    private let userDefaults = UserDefaults.standard
    private let hasSeenLaunchPanelKey = "HasSeenLaunchPanel"
    private let selectedModeKey = "LaunchPanelSelectedMode"
    
    init() {
        checkFirstLaunch()
        loadSelectedMode()
    }
    
    private func checkFirstLaunch() {
        let hasSeenPanel = userDefaults.bool(forKey: hasSeenLaunchPanelKey)
        if !hasSeenPanel {
            showLaunchPanel = true
        }
    }
    
    private func loadSelectedMode() {
        if let savedModeRawValue = userDefaults.string(forKey: selectedModeKey),
           let savedMode = ViewType(rawValue: savedModeRawValue) {
            selectedMode = savedMode
        }
    }
    
    func confirmSelection(_ mode: ViewType) {
        selectedMode = mode
        userDefaults.set(mode.rawValue, forKey: selectedModeKey)
        userDefaults.set(true, forKey: hasSeenLaunchPanelKey)
        showLaunchPanel = false
    }
    
    func skipLaunchPanel() {
        userDefaults.set(true, forKey: hasSeenLaunchPanelKey)
        showLaunchPanel = false
    }
    
    func showLaunchPanelAgain() {
        showLaunchPanel = true
    }
    
    func resetLaunchPanel() {
        userDefaults.removeObject(forKey: hasSeenLaunchPanelKey)
        showLaunchPanel = true
    }
}
