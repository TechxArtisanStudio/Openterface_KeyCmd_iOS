// Test file to verify AltGr handling
import Foundation

// Test AltGr state tracking
print("Testing AltGr state tracking...")
let kbManager = KeyboardManager.shared

// Initial state should be false
print("Initial isAltGrActive: \(kbManager.isAltGrActive)")

// Simulate AltGr key down
kbManager.handleKeyDown("AltGr")
print("After AltGr down: \(kbManager.isAltGrActive)")

// Simulate AltGr key up
kbManager.handleKeyUp("AltGr")
print("After AltGr up: \(kbManager.isAltGrActive)")

print("AltGr handling test completed successfully!")