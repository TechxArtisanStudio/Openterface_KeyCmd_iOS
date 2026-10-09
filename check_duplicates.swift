#!/usr/bin/env swift
import Foundation

// This script checks for duplicate key names in keyboard layouts

// Read the KeyboardLayoutBuilders.swift file
let fileURL = URL(fileURLWithPath: "/Users/txa/project/Openterface_KeyCmd_iOS/KeyCmd/Managers/KeyboardLayoutBuilders.swift")
let content = try String(contentsOf: fileURL, encoding: .utf8)

// Extract key definitions using regex
let pattern = #"KeyDefinition\.key\("([^"]+)"#
let regex = try NSRegularExpression(pattern: pattern, options: [])
let matches = regex.matches(in: content, options: [], range: NSRange(content.startIndex..., in: content))

var keyNames: [String] = []
for match in matches {
    if let range = Range(match.range(at: 1), in: content) {
        let keyName = String(content[range])
        keyNames.append(keyName)
    }
}

// Count occurrences
var counts: [String: Int] = [:]
for key in keyNames {
    counts[key] = (counts[key] ?? 0) + 1
}

// Find duplicates
let duplicates = counts.filter { $0.value > 1 }

print("Total keys: \(keyNames.count)")
print("Unique keys: \(counts.count)")
print("\nDuplicate key names:")
for (key, count) in duplicates.sorted(by: { $0.key < $1.key }) {
    print("  \(key): \(count) times")
}
