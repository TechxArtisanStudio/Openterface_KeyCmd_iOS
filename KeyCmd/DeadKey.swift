import Foundation

/// 死键类型 - 支持完整的 Unicode 组合字符输入
/// 参考：docs/superpowers/specs/keyboard-layout-json-schema.md §4.1
enum DeadKey: String, Codable, CaseIterable, Sendable {
    case acute       // ´  acute + e = é
    case grave       // `  grave + e = è
    case circumflex  // ^  circumflex + e = ê
    case diaeresis   // ¨  diaeresis + e = ë
    case tilde       // ~  tilde + n = ñ
    case ring        // °  ring + a = å
    case caron       // ˇ  caron + c = č
    case macron      // ¯  macron + a = ā
    case breve       // ˘  breve + a = ă
    case dotAbove    // ˙  dotAbove + z = ż
    case cedilla     // ¸  cedilla + c = ç
    case ogonek      // ˛  ogonek + a = ą
    case doubleAcute // ˝  doubleAcute + o = ő

    /// 死键显示符号（用于 UI 标识）
    var symbol: String {
        switch self {
        case .acute:       return "´"
        case .grave:       return "`"
        case .circumflex:  return "^"
        case .diaeresis:   return "¨"
        case .tilde:       return "~"
        case .ring:        return "°"
        case .caron:       return "ˇ"
        case .macron:      return "¯"
        case .breve:       return "˘"
        case .dotAbove:    return "˙"
        case .cedilla:     return "¸"
        case .ogonek:      return "˛"
        case .doubleAcute: return "˝"
        }
    }

    /// Unicode 组合字符（Combining Diacritical Marks）
    /// 用于与基础字符组合生成带音符号的字符
    var combiningCharacter: Character {
        switch self {
        case .acute:       return "\u{0301}" // ◌́
        case .grave:       return "\u{0300}" // ◌̀
        case .circumflex:  return "\u{0302}" // ◌̂
        case .diaeresis:   return "\u{0308}" // ◌̈
        case .tilde:       return "\u{0303}" // ◌̃
        case .ring:        return "\u{030A}" // ◌̊
        case .caron:       return "\u{030C}" // ◌̌
        case .macron:      return "\u{0304}" // ◌̄
        case .breve:       return "\u{0306}" // ◌̆
        case .dotAbove:    return "\u{0307}" // ◌̇
        case .cedilla:     return "\u{0327}" // ◌̧
        case .ogonek:      return "\u{0328}" // ◌̨
        case .doubleAcute: return "\u{030B}" // ◌̋
        }
    }

    /// 将死键与基础字符组合 → 组合字符
    /// 使用 Unicode 标准组合规则（NFC 规范化等价）
    /// 只有当组合后有对应的预组合字符时才返回，否则返回 nil
    func combine(with baseChar: Character) -> Character? {
        let base = baseChar.lowercased().first!
        // 使用组合字符而不是显示符号
        let combined = "\(base)\(combiningCharacter)"

        // 使用 NSString 的 precomposedStringWithCanonicalMapping 进行标准组合
        let precomposed = (combined as NSString).precomposedStringWithCanonicalMapping

        // 检查是否成功预组合 - 如果长度仍然是 2 个 Unicode 标量，说明没有预组合形式
        let precomposedScalars = precomposed.unicodeScalars.count
        if precomposedScalars == 1 {
            // 成功预组合为单个字符
            return precomposed.first
        } else {
            // 没有预组合形式，返回 nil
            return nil
        }
    }
}