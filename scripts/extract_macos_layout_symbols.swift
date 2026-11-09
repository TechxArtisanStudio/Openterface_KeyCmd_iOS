// Extracts ground-truth key symbols from macOS system keyboard layouts.
//
// For every com.apple.keylayout.* input source, translates each virtual
// keycode in four modifier states (plain / shift / option / shift+option)
// via UCKeyTranslate and prints one JSON object per layout:
//   { "layoutID": ..., "name": ..., "keys": { "<vk>": [plain, shift, option, shiftOption] },
//     "dead": { "<vk>": [bool, bool, bool, bool] } }
//
// Dead keys are resolved by following the dead key with a space, which yields
// the standalone accent character shown on the physical keycap.
//
// Usage: swift scripts/extract_macos_layout_symbols.swift > /tmp/macos_layouts.json

import Carbon
import CoreServices
import Foundation

func property(_ source: TISInputSource, _ key: CFString) -> String? {
    guard let ptr = TISGetInputSourceProperty(source, key) else { return nil }
    return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
}

// Classic Mac modifier bits; UCKeyTranslate wants (bits >> 8) & 0xFF.
let modifierStates: [(String, UInt32)] = [
    ("plain", 0),
    ("shift", UInt32(shiftKey) >> 8),
    ("option", UInt32(optionKey) >> 8),
    ("shiftOption", UInt32(shiftKey | optionKey) >> 8),
]

func translate(_ layoutData: Data, vk: UInt16, modifier: UInt32, keyboardType: UInt32) -> (String, Bool) {
    var deadKeyState: UInt32 = 0
    var chars = [UniChar](repeating: 0, count: 8)
    var length: Int = 0
    let status = layoutData.withUnsafeBytes { raw -> OSStatus in
        let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress!
        return UCKeyTranslate(layout, vk, UInt16(kUCKeyActionDown), modifier,
                              keyboardType, UInt32(kUCKeyTranslateNoDeadKeysBit),
                              &deadKeyState, 8, &length, &chars)
    }
    guard status == noErr else { return ("", false) }
    if length == 0 && deadKeyState != 0 {
        // Dead key: press space to resolve to the standalone accent.
        var spaceChars = [UniChar](repeating: 0, count: 8)
        var spaceLength: Int = 0
        let spaceStatus = layoutData.withUnsafeBytes { raw -> OSStatus in
            let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress!
            return UCKeyTranslate(layout, 49, UInt16(kUCKeyActionDown), 0,
                                  keyboardType, 0,
                                  &deadKeyState, 8, &spaceLength, &spaceChars)
        }
        if spaceStatus == noErr && spaceLength > 0 {
            return (String(utf16CodeUnits: spaceChars, count: Int(spaceLength)), true)
        }
        return ("", true)
    }
    guard length > 0 else { return ("", false) }
    return (String(utf16CodeUnits: chars, count: Int(length)), false)
}

let filter = [kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String] as CFDictionary
guard let sources = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource] else {
    fputs("Failed to list input sources\n", stderr)
    exit(1)
}

let keyboardType = UInt32(LMGetKbdType())
var results: [[String: Any]] = []

for source in sources {
    guard let id = property(source, kTISPropertyInputSourceID),
          id.hasPrefix("com.apple.keylayout.") else { continue }
    guard let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { continue }
    let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
    let name = property(source, kTISPropertyLocalizedName) ?? id

    var keys: [String: [String]] = [:]
    var dead: [String: [Bool]] = [:]
    for vk in UInt16(0)...UInt16(127) {
        var outputs: [String] = []
        var deadFlags: [Bool] = []
        var hasOutput = false
        for (_, modifier) in modifierStates {
            let (out, isDead) = translate(data, vk: vk, modifier: modifier, keyboardType: keyboardType)
            if !out.isEmpty { hasOutput = true }
            outputs.append(out)
            deadFlags.append(isDead)
        }
        if hasOutput {
            keys[String(vk)] = outputs
            dead[String(vk)] = deadFlags
        }
    }
    results.append(["layoutID": id, "name": name, "keyboardType": keyboardType, "keys": keys, "dead": dead])
}

let json = try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys])
FileHandle.standardOutput.write(json)
FileHandle.standardOutput.write("\n".data(using: .utf8)!)