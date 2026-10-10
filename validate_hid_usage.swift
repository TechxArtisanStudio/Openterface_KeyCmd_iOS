#!/usr/bin/env swift

import Foundation
import KeyCmd

// Test HIDUsageID values directly
print("Testing HIDUsageID enum values...")

// Test letter keys
assert(HIDUsageID.keyboardA.rawValue == 0x04, "keyboardA should be 0x04")
assert(HIDUsageID.keyboardZ.rawValue == 0x1D, "keyboardZ should be 0x1D")
print("✓ Letter key values test passed")

// Test number keys
assert(HIDUsageID.keyboard1.rawValue == 0x1E, "keyboard1 should be 0x1E")
assert(HIDUsageID.keyboard0.rawValue == 0x27, "keyboard0 should be 0x27")
print("✓ Number key values test passed")

// Test modifier keys
assert(HIDUsageID.keyboardLeftCtrl.rawValue == 0xE0, "keyboardLeftCtrl should be 0xE0")
assert(HIDUsageID.keyboardRightAlt.rawValue == 0xE6, "keyboardRightAlt should be 0xE6")
print("✓ Modifier key values test passed")

// Test Japanese keys
assert(HIDUsageID.keyboardInternational1.rawValue == 0x87, "keyboardInternational1 should be 0x87")
assert(HIDUsageID.keyboardInternational5.rawValue == 0x8B, "keyboardInternational5 should be 0x8B")
print("✓ Japanese key values test passed")

// Test that all cases are present
let allCases = HIDUsageID.allCases
print("✓ Total HIDUsageID cases: \(allCases.count)")
assert(allCases.count > 80, "Should have more than 80 cases")

print("\n🎉 All tests passed!")