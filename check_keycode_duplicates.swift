#!/usr/bin/env swift
import Foundation

// This script checks for keys with the same keyCode within each layout

let fileURL = URL(fileURLWithPath: "/Users/txa/project/Openterface_KeyCmd_iOS/KeyCmd/Managers/KeyboardLayoutBuilders.swift")
let content = try String(contentsOf: fileURL, encoding: .utf8)

let layoutFunctions = [
    "buildUsLayout", "buildUkLayout", "buildDeLayout", "buildFrLayout",
    "buildEsLayout", "buildItLayout", "buildPtLayout", "buildJpLayout",
    "buildCaLayout", "buildBeLayout", "buildChLayout", "buildNordicLayout"
]

let lines = content.components(separatedBy: "\n")

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

    // Extract key definitions with keyCode
    // Pattern: KeyDefinition.key("keyName", "label", ..., keyCode: "keyCode")
    let pattern = #"KeyDefinition\.(?:key|mod|special|jpSpecial)\("([^"]+)"[^)]*?(?:keyCode:\s*"([^"]+)")?"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
    let matches = regex.matches(in: layoutContent, options: [], range: NSRange(layoutContent.startIndex..., in: layoutContent))

    var keyCodeMap: [String: [String]] = [:] // keyCode -> [keyNames]

    for match in matches {
        if let keyNameRange = Range(match.range(at: 1), in: layoutContent) {
            let keyName = String(layoutContent[keyNameRange])

            var keyCode = keyName // default keyCode is the keyName itself
            if match.range(at: 2).location != NSNotFound,
               let keyCodeRange = Range(match.range(at: 2), in: layoutContent) {
                keyCode = String(layoutContent[keyCodeRange])
            }

            if keyCodeMap[keyCode] == nil {
                keyCodeMap[keyCode] = []
            }
            keyCodeMap[keyCode]?.append(keyName)
        }
    }

    // Find keyCodes with multiple keyNames
    let duplicates = keyCodeMap.filter { $0.value.count > 1 }

    if !duplicates.isEmpty {
        print("\n\(layoutName) - Keys with same keyCode:")
        for (keyCode, keyNames) in duplicates.sorted(by: { $0.key < $1.key }) {
            print("  keyCode='\(keyCode)': \(keyNames.joined(separator: ", "))")
        }
    }
}
