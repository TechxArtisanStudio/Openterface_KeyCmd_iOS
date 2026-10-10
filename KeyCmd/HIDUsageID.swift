// KeyCmd/HIDUsageID.swift
import Foundation

/// USB HID Usage IDs (Usage Page 0x07: Keyboard/Keypad)
/// 参考：USB HID Usage Tables 1.12
enum HIDUsageID: UInt8, CaseIterable, Codable {
    // 字母键 (0x04 - 0x1D)
    case keyboardA = 0x04
    case keyboardB = 0x05
    case keyboardC = 0x06
    case keyboardD = 0x07
    case keyboardE = 0x08
    case keyboardF = 0x09
    case keyboardG = 0x0A
    case keyboardH = 0x0B
    case keyboardI = 0x0C
    case keyboardJ = 0x0D
    case keyboardK = 0x0E
    case keyboardL = 0x0F
    case keyboardM = 0x10
    case keyboardN = 0x11
    case keyboardO = 0x12
    case keyboardP = 0x13
    case keyboardQ = 0x14
    case keyboardR = 0x15
    case keyboardS = 0x16
    case keyboardT = 0x17
    case keyboardU = 0x18
    case keyboardV = 0x19
    case keyboardW = 0x1A
    case keyboardX = 0x1B
    case keyboardY = 0x1C
    case keyboardZ = 0x1D

    // 数字键 (0x1E - 0x27)
    case keyboard1 = 0x1E
    case keyboard2 = 0x1F
    case keyboard3 = 0x20
    case keyboard4 = 0x21
    case keyboard5 = 0x22
    case keyboard6 = 0x23
    case keyboard7 = 0x24
    case keyboard8 = 0x25
    case keyboard9 = 0x26
    case keyboard0 = 0x27

    // 控制键 (0x28 - 0x39)
    case keyboardEnter = 0x28
    case keyboardEscape = 0x29
    case keyboardBackspace = 0x2A
    case keyboardTab = 0x2B
    case keyboardSpace = 0x2C
    case keyboardMinus = 0x2D
    case keyboardEqual = 0x2E
    case keyboardLeftBracket = 0x2F
    case keyboardRightBracket = 0x30
    case keyboardBackslash = 0x31
    case keyboardNonUSHash = 0x32
    case keyboardSemicolon = 0x33
    case keyboardQuote = 0x34
    case keyboardGraveAccent = 0x35
    case keyboardComma = 0x36
    case keyboardPeriod = 0x37
    case keyboardSlash = 0x38
    case keyboardCapsLock = 0x39

    // 功能键 (0x3A - 0x45)
    case keyboardF1 = 0x3A
    case keyboardF2 = 0x3B
    case keyboardF3 = 0x3C
    case keyboardF4 = 0x3D
    case keyboardF5 = 0x3E
    case keyboardF6 = 0x3F
    case keyboardF7 = 0x40
    case keyboardF8 = 0x41
    case keyboardF9 = 0x42
    case keyboardF10 = 0x43
    case keyboardF11 = 0x44
    case keyboardF12 = 0x45

    // 导航和编辑键 (0x49 - 0x52)
    case keyboardInsert = 0x49
    case keyboardHome = 0x4A
    case keyboardPageUp = 0x4B
    case keyboardDelete = 0x4C
    case keyboardEnd = 0x4D
    case keyboardPageDown = 0x4E
    case keyboardRightArrow = 0x4F
    case keyboardLeftArrow = 0x50
    case keyboardDownArrow = 0x51
    case keyboardUpArrow = 0x52

    // 应用键 (0x65)
    case keyboardApplication = 0x65  // Menu key

    // 修饰键 (0xE0 - 0xE7)
    case keyboardLeftCtrl = 0xE0
    case keyboardLeftShift = 0xE1
    case keyboardLeftAlt = 0xE2
    case keyboardLeftGUI = 0xE3
    case keyboardRightCtrl = 0xE4
    case keyboardRightShift = 0xE5
    case keyboardRightAlt = 0xE6  // AltGr
    case keyboardRightGUI = 0xE7

    // 日语特殊键 (0x87 - 0x92)
    case keyboardInternational1 = 0x87  // Ro
    case keyboardInternational2 = 0x88  // かな
    case keyboardInternational3 = 0x89  // 変換
    case keyboardInternational4 = 0x8A  // 無変換
    case keyboardInternational5 = 0x8B  // katakana/hiragana
    case keyboardInternational6 = 0x8C  // Reserved for future use
    case keyboardInternational7 = 0x8D  // Reserved for future use
    case keyboardInternational8 = 0x8E  // Reserved for future use
    case keyboardInternational9 = 0x8F  // Reserved for future use
    case keyboardLANG1 = 0x90           // Hangul/English toggle
    case keyboardLANG2 = 0x91           // Hanja conversion
    case keyboardLANG3 = 0x92           // Reserved for future use
}