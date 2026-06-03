//
//  LanguageManager.swift
//  KeyMod
//
//  Manages in-app language override without requiring an app restart.
//  Changing the language updates a published `locale` that is injected into
//  the SwiftUI environment at the root, causing all Text(LocalizedStringKey)
//  views to re-render immediately with translations from the matching .lproj.
//
//  Supported languages: English, 简体中文, 繁體中文, Français, 日本語, 한국어.
//

import Foundation

final class LanguageManager: ObservableObject {

    static let shared = LanguageManager()

    /// Sentinel value meaning "use the device system language".
    static let followSystem = "system"

    // MARK: - Model

    struct AppLanguage: Identifiable, Hashable {
        /// BCP-47 language tag or `LanguageManager.followSystem`.
        let id: String
        /// Display name shown in the UI (always in the target language).
        let displayName: String
    }

    static let supported: [AppLanguage] = [
        AppLanguage(id: followSystem,  displayName: "Follow System"),
        AppLanguage(id: "en",          displayName: "English"),
        AppLanguage(id: "zh-Hans",     displayName: "简体中文"),
        AppLanguage(id: "zh-Hant",     displayName: "繁體中文"),
        AppLanguage(id: "fr",          displayName: "Français"),
        AppLanguage(id: "ja",          displayName: "日本語"),
        AppLanguage(id: "ko",          displayName: "한국어"),
    ]

    // MARK: - State

    /// The locale injected into the SwiftUI environment. Changing this triggers
    /// an immediate UI refresh — no restart needed.
    @Published var locale: Locale = .current

    @Published var selectedLanguageId: String {
        didSet {
            locale = _locale(for: selectedLanguageId)
            UserDefaults.standard.set(selectedLanguageId, forKey: "app_language")
        }
    }

    // MARK: - Init

    private init() {
        let saved = UserDefaults.standard.string(forKey: "app_language")
            ?? LanguageManager.followSystem
        selectedLanguageId = saved
        locale = _locale(for: saved)
    }

    // MARK: - Public helpers

    var selectedLanguage: AppLanguage {
        LanguageManager.supported.first { $0.id == selectedLanguageId }
            ?? LanguageManager.supported[0]
    }

    // MARK: - Private

    private func _locale(for id: String) -> Locale {
        id == LanguageManager.followSystem ? .current : Locale(identifier: id)
    }
}
