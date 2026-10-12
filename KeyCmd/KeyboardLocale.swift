//
//  KeyboardLocale.swift
//  KeyMod
//
//  Keyboard layout locales for different countries/regions.
//  Matches physical keyboard layouts (ANSI, ISO, JIS, etc.)
//

import Foundation
#if os(macOS)
import Carbon
#endif

/// 键盘布局区域枚举 - 表示不同国家/地区的物理键盘布局
enum KeyboardLocale: String, CaseIterable, Codable, Identifiable {
    case us       = "US"       // 美式 QWERTY (ANSI)
    case uk       = "UK"       // 英式 QWERTY (ISO)
    case de       = "DE"       // 德式 QWERTZ (ISO)
    case fr       = "FR"       // 法式 AZERTY (ISO)
    case es       = "ES"       // 西班牙语 QWERTY (ISO)
    case it       = "IT"       // 意大利语 QWERTY (ISO)
    case pt       = "PT"       // 葡萄牙语 QWERTY (ISO)
    case jp       = "JP"       // 日式 JIS
    case cn       = "CN"       // 中文美式（标准美式键盘）
    case ca       = "CA"       // 加拿大法语/英语 (ISO)
    case au       = "AU"       // 澳大利亚（同UK ISO）
    case be       = "BE"       // 比利时 AZERTY (ISO)
    case ch       = "CH"       // 瑞士 QWERTZ (ISO)
    case nordic   = "NORDIC"   // 北欧（瑞典/挪威/丹麦/芬兰 ISO）

    var id: String { rawValue }

    /// 显示名称
    var displayName: String {
        switch self {
        case .us:      return "English (US)"
        case .uk:      return "English (UK)"
        case .de:      return "Deutsch (DE)"
        case .fr:      return "Français (FR)"
        case .es:      return "Español (ES)"
        case .it:      return "Italiano (IT)"
        case .pt:      return "Português (PT)"
        case .jp:      return "日本語 (JP)"
        case .cn:      return "中文 (US)"
        case .ca:      return "Canada (CA)"
        case .au:      return "Australia (AU)"
        case .be:      return "Belgique (BE)"
        case .ch:      return "Schweiz (CH)"
        case .nordic:  return "Nordic (NO/SE/DK/FI)"
        }
    }

    /// 简短标识（用于UI）
    var shortName: String { rawValue }

    /// 物理键盘标准类型
    var physicalStandard: PhysicalStandard {
        switch self {
        case .us, .cn:     return .ansi
        case .jp:          return .jis
        default:           return .iso
        }
    }

    /// 关联的系统locale标识符
    var localeIdentifiers: [String] {
        switch self {
        case .us:      return ["en-US", "en"]
        case .uk:      return ["en-GB", "en-IE"]
        case .de:      return ["de-DE", "de-AT", "de-CH"]
        case .fr:      return ["fr-FR", "fr-BE", "fr-CA", "fr-CH"]
        case .es:      return ["es-ES", "es-MX", "es-AR"]
        case .it:      return ["it-IT", "it-CH"]
        case .pt:      return ["pt-PT", "pt-BR"]
        case .jp:      return ["ja-JP"]
        case .cn:      return ["zh-Hans", "zh-Hant", "zh-CN", "zh-TW", "zh-HK"]
        case .ca:      return ["en-CA", "fr-CA"]
        case .au:      return ["en-AU"]
        case .be:      return ["nl-BE", "fr-BE"]
        case .ch:      return ["de-CH", "fr-CH", "it-CH"]
        case .nordic:  return ["sv-SE", "no-NO", "da-DK", "fi-FI"]
        }
    }

    /// 根据系统locale自动检测
    static func fromSystemLocale() -> KeyboardLocale {
        let currentLocale = Locale.current
        let identifier = currentLocale.identifier

        // 精确匹配
        for locale in KeyboardLocale.allCases {
            if locale.localeIdentifiers.contains(identifier) {
                return locale
            }
        }

        // 语言代码匹配（支持 iOS 16+ 新 API）
        let langCode: String?
        if #available(iOS 16.0, macOS 13.0, *) {
            langCode = currentLocale.language.languageCode?.identifier
        } else {
            langCode = currentLocale.languageCode
        }

        if let langCode = langCode {
            for locale in KeyboardLocale.allCases {
                if locale.localeIdentifiers.contains(where: { $0.hasPrefix(langCode + "-") || $0 == langCode }) {
                    return locale
                }
            }
        }

        // 区域代码匹配（支持 iOS 16+ 新 API）
        let regionCode: String?
        if #available(iOS 16.0, macOS 13.0, *) {
            regionCode = currentLocale.region?.identifier
        } else {
            regionCode = currentLocale.regionCode
        }

        if let regionCode = regionCode {
            switch regionCode {
            case "US": return .us
            case "GB", "IE": return .uk
            case "DE", "AT": return .de
            case "FR": return .fr
            case "ES", "MX", "AR": return .es
            case "IT": return .it
            case "PT", "BR": return .pt
            case "JP": return .jp
            case "CN", "TW", "HK": return .cn
            case "CA": return .ca
            case "AU": return .au
            case "BE": return .be
            case "CH": return .ch
            case "SE", "NO", "DK", "FI": return .nordic
            default: break
            }
        }

        return .us // 默认回退
    }

    /// 检测当前活动的键盘布局
    /// - Returns: 检测到的键盘布局，如果检测失败则返回 nil
    static func detectActiveKeyboardLayout() -> KeyboardLocale? {
        #if os(iOS)
        // iOS: 使用系统语言偏好检测键盘布局
        // Note: UITextInputMode.activeInputMode is deprecated, use system preferences instead
        if let preferredLanguage = Locale.preferredLanguages.first {
            return mapLanguageCodeToLocale(preferredLanguage)
        }
        #elseif os(macOS)
        // macOS: 使用 TIS API 检测当前输入源
        if let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() {
            if let layoutIdPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
                let layoutId = Unmanaged<CFString>.fromOpaque(layoutIdPtr).takeUnretainedValue() as String
                return mapInputSourceIDToLocale(layoutId)
            }
        }
        #endif

        return nil
    }

    /// 将语言代码映射到 KeyboardLocale
    /// - Parameter languageCode: 语言代码（如 "en-US", "de-DE"）
    /// - Returns: 对应的 KeyboardLocale
    private static func mapLanguageCodeToLocale(_ languageCode: String?) -> KeyboardLocale? {
        guard let code = languageCode else { return nil }

        let langCode = code.components(separatedBy: "-").first ?? code

        switch langCode {
        case "en":
            if code.contains("GB") || code.contains("UK") { return .uk }
            else if code.contains("AU") { return .au }
            else if code.contains("CA") { return .ca }
            return .us
        case "de": return .de
        case "fr":
            if code.contains("BE") { return .be }
            if code.contains("CA") { return .ca }
            if code.contains("CH") { return .ch }
            return .fr
        case "es": return .es
        case "it": return .it
        case "pt": return .pt
        case "ja": return .jp
        case "zh": return .cn
        case "sv", "no", "da", "fi": return .nordic
        case "nl":
            if code.contains("BE") { return .be }
            return .us
        default: return .us
        }
    }

    /// 将 macOS 输入源 ID 映射到 KeyboardLocale
    /// - Parameter inputSourceID: 输入源 ID（如 "com.apple.keylayout.US"）
    /// - Returns: 对应的 KeyboardLocale
    private static func mapInputSourceIDToLocale(_ inputSourceID: String) -> KeyboardLocale? {
        if inputSourceID.contains("US") { return .us }
        if inputSourceID.contains("German") { return .de }
        if inputSourceID.contains("French") {
            if inputSourceID.contains("Belgian") { return .be }
            if inputSourceID.contains("Canadian") { return .ca }
            if inputSourceID.contains("Swiss") { return .ch }
            return .fr
        }
        if inputSourceID.contains("Spanish") { return .es }
        if inputSourceID.contains("Italian") { return .it }
        if inputSourceID.contains("Portuguese") { return .pt }
        if inputSourceID.contains("Japanese") { return .jp }
        if inputSourceID.contains("Chinese") { return .cn }
        if inputSourceID.contains("British") { return .uk }
        if inputSourceID.contains("Nordic") { return .nordic }
        if inputSourceID.contains("Swiss") { return .ch }
        if inputSourceID.contains("Belgian") { return .be }
        if inputSourceID.contains("Australian") { return .au }
        if inputSourceID.contains("Canadian") { return .ca }
        if inputSourceID.contains("Swedish") { return .nordic }
        if inputSourceID.contains("Norwegian") { return .nordic }
        if inputSourceID.contains("Danish") { return .nordic }
        if inputSourceID.contains("Finnish") { return .nordic }
        return nil
    }

    /// 物理键盘标准
    enum PhysicalStandard: String, Codable {
        case ansi = "ANSI"  // 美国标准，Enter键横向，左Shift较长
        case iso  = "ISO"   // 国际标准，Enter键倒L形，左Shift较短，多一个键
        case jis  = "JIS"   // 日本标准，空格键更短，多出几个键
    }
}

// MARK: - TargetOS Extension

extension KeyboardLocale {
    /// 获取该区域的默认目标操作系统
    var preferredTargetOS: TargetOS {
        switch self {
        case .us, .cn, .jp: return .macOS
        case .uk, .au, .ca: return .windows
        case .de, .fr, .es, .it, .pt, .be, .ch, .nordic: return .linux
        }
    }
}