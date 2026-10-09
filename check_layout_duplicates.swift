#!/usr/bin/env swift
import Foundation

// This script checks for duplicate key names within each keyboard layout

let fileURL = URL(fileURLWithPath: "/Users/txa/project/Openterface_KeyCmd_iOS/KeyCmd/Managers/KeyboardLayoutBuilders.swift")
let content = try String(contentsOf: fileURL, encoding: .utf8)

// Split content into layout functions
let layoutFunctions = [
    "buildUsLayout", "buildUkLayout", "buildDeLayout", "buildFrLayout",
    "buildEsLayout", "buildItLayout", "buildPtLayout", "buildJpLayout",
    "buildCaLayout", "buildBeLayout", "buildChLayout", "buildNordicLayout"
]

let lines = content.components(separatedBy: "\n")

for layoutName in layoutFunctions {
    // Find the function start
    guard let startIndex = lines.firstIndex(where: { $0.contains("func \(layoutName)") }) else {
        continue
    }

    // Find the function end (next "func" or end of file)
    var endIndex = lines.count
    for i in (startIndex + 1)..<lines.count {
        if lines[i].contains("private static func build") && i > startIndex {
            endIndex = i
            break
        }
    }

    let layoutContent = lines[startIndex..<endIndex].joined(separator: "\n")

    // Extract key definitions
    let pattern = #"KeyDefinition\.(?:key|mod|special|jpSpecial)\("([^"]+)"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
    let matches = regex.matches(in: layoutContent, options: [], range: NSRange(layoutContent.startIndex..., in: layoutContent))

    var keyNames: [String] = []
    for match in matches {
        if let range = Range(match.range(at: 1), in: layoutContent) {
            let keyName = String(layoutContent[range])
            keyNames.append(keyName)
        }
    }

    // Count occurrences
    var counts: [String: Int] = [:]
    for key in keyNames {
        counts[key] = (counts[key] ?? 0) + 1
    }

    // Find duplicates within this layout
    let duplicates = counts.filter { $0.value > 1 }

    if !duplicates.isEmpty {
        print("\n\(layoutName):")
        for (key, count) in duplicates.sorted(by: { $0.key < $1.key }) {
            print("  '\(key)': \(count) times")
        }
    }
}
