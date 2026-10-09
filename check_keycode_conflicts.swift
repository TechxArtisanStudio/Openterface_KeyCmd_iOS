#!/usr/bin/env swift
import Foundation

// This script finds keys where keyCode is explicitly set to a different value than keyName
// which could cause conflicts with keys that naturally have that keyCode

let fileURL = URL(fileURLWithPath: "/Users/txa/project/Openterface_KeyCmd_iOS/KeyCmd/Managers/KeyboardLayoutBuilders.swift")
let content = try String(contentsOf: fileURL, encoding: .utf8)

let layoutFunctions = [
    "buildUsLayout", "buildUkLayout", "buildDeLayout", "buildFrLayout",
    "buildEsLayout", "buildItLayout", "buildPtLayout", "buildJpLayout",
    "buildCaLayout", "buildBeLayout", "buildChLayout", "buildNordicLayout"
]

let lines = content.components(separatedBy: "\n")

print("Checking for explicit keyCode assignments that might cause conflicts...\n")

for layoutName in layoutFunctions {
    guard let startIndex = lines.firstIndex(where: { $0.contains("func \(layoutName)") }) else {
        continue
    }

    var endIndex = lines.count
    for i in (startIndex + 1)..<lines.count {
        if lines[i].contains("private static func build") && i > startIndex {
            endIndex = i
            break
        }
    }

    let layoutContent = lines[startIndex..<endIndex].joined(separator: "\n")

    // Extract all key definitions
    // Pattern: KeyDefinition.key("keyName", "label", ..., keyCode: "keyCode", ...)
    let pattern = #"KeyDefinition\.(?:key|mod|special|jpSpecial)\("([^"]+)"[^)]*?keyCode:\s*"([^"]+)"[^)]*"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
    let matches = regex.matches(in: layoutContent, options: [], range: NSRange(layoutContent.startIndex..., in: layoutContent))

    var explicitKeyCodes: [String: String] = [:] // keyName -> keyCode

    for match in matches {
        if let keyNameRange = Range(match.range(at: 1), in: layoutContent),
           let keyCodeRange = Range(match.range(at: 2), in: layoutContent) {
            let keyName = String(layoutContent[keyNameRange])
            let keyCode = String(layoutContent[keyCodeRange])
            explicitKeyCodes[keyName] = keyCode
        }
    }

    // Also get keys without explicit keyCode (they default to keyName)
    let pattern2 = #"KeyDefinition\.(?:key|mod|special|jpSpecial)\("([^"]+)"[^)]*?(?:keyCode:\s*"[^"]+")?[^)]*"#
    guard let regex2 = try? NSRegularExpression(pattern: pattern2, options: []) else { continue }
    let matches2 = regex2.matches(in: layoutContent, options: [], range: NSRange(layoutContent.startIndex..., in: layoutContent))

    var allKeys: [String: String] = [:] // keyName -> actual keyCode (explicit or default)

    for match in matches2 {
        if let keyNameRange = Range(match.range(at: 1), in: layoutContent) {
            let keyName = String(layoutContent[keyNameRange])
            let keyCode = explicitKeyCodes[keyName] ?? keyName // use explicit if exists, otherwise default
            allKeys[keyName] = keyCode
        }
    }

    // Reverse map: keyCode -> [keyNames]
    var keyCodeMap: [String: [String]] = [:]
    for (keyName, keyCode) in allKeys {
        if keyCodeMap[keyCode] == nil {
            keyCodeMap[keyCode] = []
        }
        keyCodeMap[keyCode]?.append(keyName)
    }

    // Find keyCodes with multiple keyNames (potential conflicts)
    let conflicts = keyCodeMap.filter { $0.value.count > 1 }

    if !conflicts.isEmpty {
        print("\(layoutName):")
        for (keyCode, keyNames) in conflicts.sorted(by: { $0.key < $1.key }) {
            // Check if this conflict is due to explicit keyCode assignment
            var hasExplicitAssignment = false
            for keyName in keyNames {
                if explicitKeyCodes[keyName] != nil {
                    hasExplicitAssignment = true
                    break
                }
            }

            if hasExplicitAssignment {
                print("  keyCode='\(keyCode)': \(keyNames.joined(separator: ", ")) ← POTENTIAL CONFLICT")
            }
        }
        print()
    }
}
