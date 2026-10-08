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

/// 键盘布局管理器 - 单例模式
/// 负责根据 targetOS + keyboardLocale 提供正确的键盘布局
final class KeyboardLayoutManager: ObservableObject {
    static let shared = KeyboardLayoutManager()

    // MARK: - Constants

    private static let keyboardLocaleKey = "AISettings.keyboardLocale"
    private static let keyboardAutoDetectKey = "AISettings.keyboardAutoDetect"

    // MARK: - Published Properties

    /// 当前激活的布局
    @Published private(set) var currentLayout: KeyboardLayoutDefinition

    /// 当前选择的键盘布局区域
    @Published var currentKeyboardLocale: KeyboardLocale {
        didSet {
            guard currentKeyboardLocale != oldValue else { return }
            UserDefaults.standard.set(currentKeyboardLocale.rawValue, forKey: Self.keyboardLocaleKey)
            refreshCurrentLayout()
        }
    }

    /// 是否启用自动检测
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
        // 恢复保存的布局设置
        let savedLocaleRaw = UserDefaults.standard.string(forKey: Self.keyboardLocaleKey)
        let savedSavedLocale = savedLocaleRaw.flatMap { KeyboardLocale(rawValue: $0) } ?? .us
        let savedAutoDetect = UserDefaults.standard.object(forKey: Self.keyboardAutoDetectKey) as? Bool

        // 如果启用了自动检测且没有保存的设置，使用系统 locale
        let resolvedLocale: KeyboardLocale
        if savedAutoDetect == true && savedLocaleRaw == nil {
            resolvedLocale = KeyboardLocale.fromSystemLocale()
        } else {
            resolvedLocale = savedSavedLocale
        }

        let targetOS = AISettings.shared.targetOS

        // 先初始化所有存储属性
        self.currentKeyboardLocale = resolvedLocale
        self.autoDetectLocale = savedAutoDetect ?? false
        self.currentLayout = Self.createLayout(for: targetOS, locale: resolvedLocale)

        logger.log("KeyboardLayoutManager initialized: \(resolvedLocale.rawValue) layout for \(targetOS.rawValue)", category: "Keyboard")

        loadAllLayouts()
        observeSettingsChanges()
    }

    // MARK: - Public API

    /// 获取所有支持的布局
    var supportedLocales: [KeyboardLocale] { KeyboardLocale.allCases }

    /// 获取指定OS和Locale的布局（带缓存）
    func layout(for targetOS: TargetOS, locale: KeyboardLocale) -> KeyboardLayoutDefinition {
        let key = Self.cacheKey(targetOS, locale)
        if let cached = layoutCache[key] {
            return cached
        }
        let layout = Self.createLayout(for: targetOS, locale: locale)
        layoutCache[key] = layout
        return layout
    }

    /// 当前激活的布局（基于当前设置）
    var activeLayout: KeyboardLayoutDefinition {
        currentLayout
    }

    /// 预加载所有布局组合
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

    /// 获取当前活动布局名称
    var activeLayoutName: String {
        currentLayout.metadata.name
    }

    /// 缓存统计
    var cacheStats: String {
        "\(layoutCache.count) layouts cached"
    }

    // MARK: - Layout Creation

    private static func cacheKey(_ os: TargetOS, _ locale: KeyboardLocale) -> String {
        "\(os.rawValue)_\(locale.rawValue)"
    }

    /// 创建指定OS和Locale的布局（委托给对应的构建器）
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
        // 同步预加载当前 targetOS 下常用 locale 的布局
        let priorityLocales: [KeyboardLocale] = [.us, .uk, .de, .fr, .jp, .cn]
        for locale in priorityLocales {
            _ = layout(for: AISettings.shared.targetOS, locale: locale)
        }
    }

    private func observeSettingsChanges() {
        // 监听 targetOS 变化以更新布局
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
    /// 键盘布局发生变化时发送
    static let keyboardLayoutChanged = Notification.Name("KeyboardLayoutChanged")
    /// 键盘区域设置发生变化时发送
    static let keyboardLocaleChanged = Notification.Name("KeyboardLocaleChanged")
}

// MARK: - AISettings Extension

extension AISettings {
    /// 键盘布局区域的便捷访问
    var keyboardLocale: KeyboardLocale {
        get {
            KeyboardLayoutManager.shared.currentKeyboardLocale
        }
        set {
            KeyboardLayoutManager.shared.currentKeyboardLocale = newValue
        }
    }

    /// 是否自动检测键盘布局的便捷访问
    var keyboardAutoDetect: Bool {
        get {
            KeyboardLayoutManager.shared.autoDetectLocale
        }
        set {
            KeyboardLayoutManager.shared.autoDetectLocale = newValue
        }
    }
}