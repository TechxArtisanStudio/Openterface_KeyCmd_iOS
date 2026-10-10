import Foundation
@testable import KeyCmd

// Quick verification test
let keyA = KeyDefinition.key("A", "A")
print("Key A: hidUsageID = \(keyA.hidUsageID), rawValue = \(keyA.hidUsageValue)")
// Expected: .keyboardA, 0x04

let keyQ = KeyDefinition.key("Q", "Q")
print("Key Q: hidUsageID = \(keyQ.hidUsageID), rawValue = \(keyQ.hidUsageValue)")
// Expected: .keyboardQ, 0x14

let shiftKey = KeyDefinition.mod("Shift")
print("Shift key: hidUsageID = \(shiftKey.hidUsageID), rawValue = \(shiftKey.hidUsageValue)")
// Expected: .keyboardLeftShift (default), 0xE1