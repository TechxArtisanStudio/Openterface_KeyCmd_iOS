#!/bin/bash
# Test script to verify keyboard fixes

echo "Testing keyboard fixes..."

# Check that the source files have been modified correctly
echo "Checking keyCode parameters in Japanese layout..."

# Check for ¥ key fix
if grep -q 'KeyDefinition.key("¥", "¥", shift: "|", keyCode: "\\\\")' /Users/txa/project/Openterface_KeyCmd_iOS/KeyCmd/Managers/KeyboardLayoutBuilders.swift; then
    echo "✓ ¥ key fix found"
else
    echo "✗ ¥ key fix NOT found"
fi

# Check for @ key fix
if grep -q 'KeyDefinition.key("@", "@", shift: "`", keyCode: "[")' /Users/txa/project/Openterface_KeyCmd_iOS/KeyCmd/Managers/KeyboardLayoutBuilders.swift; then
    echo "✓ @ key fix found"
else
    echo "✗ @ key fix NOT found"
fi

# Check for ^ key fix
if grep -q 'KeyDefinition.key("\^", "\^", shift: "~", keyCode: "-")' /Users/txa/project/Openterface_KeyCmd_iOS/KeyCmd/Managers/KeyboardLayoutBuilders.swift; then
    echo "✓ ^ key fix found"
else
    echo "✗ ^ key fix NOT found"
fi

# Check for : key fix
if grep -q 'KeyDefinition.key(":", ":", shift: "*", keyCode: "\"")' /Users/txa/project/Openterface_KeyCmd_iOS/KeyCmd/Managers/KeyboardLayoutBuilders.swift; then
    echo "✓ : key fix found"
else
    echo "✗ : key fix NOT found"
fi

# Check for ; key fix
if grep -q 'KeyDefinition.key(";", ";", shift: "+", keyCode: ";")' /Users/txa/project/Openterface_KeyCmd_iOS/KeyCmd/Managers/KeyboardLayoutBuilders.swift; then
    echo "✓ ; key fix found"
else
    echo "✗ ; key fix NOT found"
fi

# Check for Ro key fix
if grep -q 'KeyDefinition.special("Ro", label: "Ro", keyCode: "Ro")' /Users/txa/project/Openterface_KeyCmd_iOS/KeyCmd/Managers/KeyboardLayoutBuilders.swift; then
    echo "✓ Ro key fix found"
else
    echo "✗ Ro key fix NOT found"
fi

# Check for hidKeyName function
if grep -q 'private func hidKeyName(for keyName: String) -> String' /Users/txa/project/Openterface_KeyCmd_iOS/KeyCmd/View/BasicKeyboardMouseView.swift; then
    echo "✓ hidKeyName function found"
else
    echo "✗ hidKeyName function NOT found"
fi

echo "Testing complete."