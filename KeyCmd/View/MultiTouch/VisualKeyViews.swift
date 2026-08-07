import SwiftUI

/// Visual-only modifier key view. Renders the key appearance including
/// pressed/locked state but does NOT handle touches.
struct ModifierKeyVisual: View {
    let key: String
    let displayText: String
    @ObservedObject var keyboardManager: KeyboardManager
    @ObservedObject var themeManager: ThemeManager
    let isPressed: Bool
    let isLocked: Bool

    var body: some View {
        Text(displayText)
            .font(.system(size: 12, weight: .bold))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isPressed || isLocked ? themeManager.accentColor : Self.functionKeyBg)
            .cornerRadius(6)
            .foregroundColor(isPressed || isLocked ? Self.keyLabelPressed : Self.keyLabelIdle)
    }

    static let functionKeyBg = Color(.secondarySystemBackground)
    static let keyLabelPressed = Color.white
    static let keyLabelIdle = Color.primary
}

/// Visual-only regular key view. Renders the key appearance including
/// pressed state but does NOT handle touches.
struct KeyVisual: View {
    let content: AnyView
    let isPressed: Bool
    @ObservedObject var themeManager: ThemeManager

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isPressed ? themeManager.accentColor : Color(.secondarySystemBackground))
            .cornerRadius(6)
            .foregroundColor(isPressed ? Color.white : Color.primary)
    }
}
