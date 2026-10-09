//
//  KeyboardLayoutManager.swift
//  KeyMod
//
//  Keyboard layout manager — singleton that provides the correct keyboard layout
//  for the current TargetOS + KeyboardLocale combination. All layouts are
//  lazily built and cached.
//

import Foundation
import SwiftUI

/// Keyboard layout manager - Singleton pattern
/// Responsible for providing the correct keyboard layout based on targetOS + keyboardLocale
final class KeyboardLayoutManager: ObservableObject {
    static let shared = KeyboardLayoutManager()

    // MARK: - Constants

    private static let keyboardLocaleKey = "AISettings.keyboardLocale"
    private static let keyboardAutoDetectKey = "AISettings.keyboardAutoDetect"

    // MARK: - Published Properties

    /// The currently active layout
    @Published private(set) var currentLayout: KeyboardLayoutDefinition

    /// Currently selected keyboard locale
    @Published var currentKeyboardLocale: KeyboardLocale {
        didSet {
            guard currentKeyboardLocale != oldValue else { return }
            UserDefaults.standard.set(currentKeyboardLocale.rawValue, forKey: Self.keyboardLocaleKey)
            refreshCurrentLayout()
        }
    }

    /// Whether auto-detection is enabled
    @Published var autoDetectLocale: Bool {
        didSet {
            UserDefaults.standard.set(autoDetectLocale, forKey: Self.keyboardAutoDetectKey)
            if autoDetectLocale {
                let detected = KeyboardLocale.fromSystemLocale()
                if detected != currentKeyboardLocale {
                    currentKeyboardLocale = detected
                }
            }
        }
    }

    // MARK: - Private Properties

    private var layoutCache: [String: KeyboardLayoutDefinition] = [:]
    private let logger = LogManager.shared
    private let prefs = KmBasicKeyboardPrefs.shared

    // MARK: - Init

    private init() {
        // Restore saved layout settings
        let savedLocaleRaw = UserDefaults.standard.string(forKey: Self.keyboardLocaleKey)
        let savedSavedLocale = savedLocaleRaw.flatMap { KeyboardLocale(rawValue: $0) } ?? .us
        let savedAutoDetect = UserDefaults.standard.object(forKey: Self.keyboardAutoDetectKey) as? Bool

        // If auto-detection is enabled and no saved settings, use system locale
        let resolvedLocale: KeyboardLocale
        if savedAutoDetect == true && savedLocaleRaw == nil {
            resolvedLocale = KeyboardLocale.fromSystemLocale()
        } else {
            resolvedLocale = savedSavedLocale
        }

        let targetOS = AISettings.shared.targetOS

        // Initialize all stored properties first
        self.currentKeyboardLocale = resolvedLocale
        self.autoDetectLocale = savedAutoDetect ?? false
        self.currentLayout = Self.createLayout(for: targetOS, locale: resolvedLocale)

        logger.log("KeyboardLayoutManager initialized: \(resolvedLocale.rawValue) layout for \(targetOS.rawValue)", category: "Keyboard")

        loadAllLayouts()
        observeSettingsChanges()
    }

    // MARK: - Public API

    /// Get all supported layouts
    var supportedLocales: [KeyboardLocale] { KeyboardLocale.allCases }

    /// Get layout for specified OS and Locale (with caching)
    func layout(for targetOS: TargetOS, locale: KeyboardLocale) -> KeyboardLayoutDefinition {
        let key = Self.cacheKey(targetOS, locale)
        if let cached = layoutCache[key] {
            return cached
        }
        let layout = Self.createLayout(for: targetOS, locale: locale)
        layoutCache[key] = layout
        return layout
    }

    /// Currently active layout (based on current settings)
    var activeLayout: KeyboardLayoutDefinition {
        currentLayout
    }

    /// Resolve display key name to HID key name using current layout
    func hidKeyName(for keyName: String) -> String {
        if keyName == "Esc" { return "Escape" }
        let keyDef = currentLayout.keyDefinition(for: keyName)
        let resolved = keyDef?.keyCode ?? keyName
        if keyName == "¥" || keyName == "\\" || keyName == "@" || keyName == "^" || keyName == ":" {
            print("DEBUG LayoutManager hidKeyName: keyName=\(keyName), keyDef=\(keyDef != nil ? "found" : "nil"), keyCode=\(keyDef?.keyCode ?? "nil"), resolved=\(resolved)")
        }
        return resolved
    }

    /// Preload all layout combinations
    func preloadAllLayouts() {
        DispatchQueue.global(qos: .utility).async {
            for os in TargetOS.allCases {
                for locale in KeyboardLocale.allCases {
                    _ = self.layout(for: os, locale: locale)
                }
            }
            self.logger.log("All keyboard layouts preloaded", category: "Keyboard")
        }
    }

    /// Get current active layout name
    var activeLayoutName: String {
        currentLayout.metadata.name
    }

    /// Cache statistics
    var cacheStats: String {
        "\(layoutCache.count) layouts cached"
    }

    // MARK: - Layout Creation

    private static func cacheKey(_ os: TargetOS, _ locale: KeyboardLocale) -> String {
        "\(os.rawValue)_\(locale.rawValue)"
    }

    /// Create layout for specified OS and Locale (delegated to corresponding builder)
    static func createLayout(for targetOS: TargetOS, locale: KeyboardLocale) -> KeyboardLayoutDefinition {
        switch targetOS {
        case .windows:
            return WindowsLayoutBuilder.build(for: locale)
        case .macOS:
            return MacLayoutBuilder.build(for: locale)
        case .linux:
            return LinuxLayoutBuilder.build(for: locale)
        }
    }

    // MARK: - Private Methods

    private func loadAllLayouts() {
        // Preload commonly used locales for current targetOS
        let priorityLocales: [KeyboardLocale] = [.us, .uk, .de, .fr, .jp, .cn]
        for locale in priorityLocales {
            _ = layout(for: AISettings.shared.targetOS, locale: locale)
        }
    }

    private func observeSettingsChanges() {
        // Observe targetOS changes to update layout
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTargetOSChanged),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }

    @objc private func handleTargetOSChanged() {
        let currentOS = AISettings.shared.targetOS
        let layoutOS = currentLayout.targetOS
        if currentOS != layoutOS {
            refreshCurrentLayout()
        }
    }

    private func refreshCurrentLayout() {
        let newLayout = layout(for: AISettings.shared.targetOS, locale: currentKeyboardLocale)
        currentLayout = newLayout
        logger.log("Keyboard layout refreshed: \(currentKeyboardLocale.rawValue) for \(AISettings.shared.targetOS.rawValue)", category: "Keyboard")
        objectWillChange.send()
        notifyLayoutChanged()
    }

    private func notifyLayoutChanged() {
        NotificationCenter.default.post(
            name: .keyboardLayoutChanged,
            object: self,
            userInfo: ["layout": currentLayout]
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Sent when keyboard layout changes
    static let keyboardLayoutChanged = Notification.Name("KeyboardLayoutChanged")
    /// Sent when keyboard locale setting changes
    static let keyboardLocaleChanged = Notification.Name("KeyboardLocaleChanged")
}

// MARK: - AISettings Extension

extension AISettings {
    /// Convenient access to keyboard locale setting
    var keyboardLocale: KeyboardLocale {
        get {
            KeyboardLayoutManager.shared.currentKeyboardLocale
        }
        set {
            KeyboardLayoutManager.shared.currentKeyboardLocale = newValue
        }
    }

    /// Convenient access to keyboard auto-detection setting
    var keyboardAutoDetect: Bool {
        get {
            KeyboardLayoutManager.shared.autoDetectLocale
        }
        set {
            KeyboardLayoutManager.shared.autoDetectLocale = newValue
        }
    }
}