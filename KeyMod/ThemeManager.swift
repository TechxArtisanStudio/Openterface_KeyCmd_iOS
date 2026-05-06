import Foundation
import SwiftUI

/// Theme manager matching Android's 8 color families (ThemeManager.java).
/// Provides accent colors, container colors, and dark mode support.
class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    // Color family names matching Android ThemeManager.FAMILY_*
    enum ColorFamily: String, CaseIterable, Identifiable {
        case orange, blue, green, pink, purple, red, teal, indigo

        var id: String { rawValue }
        var displayName: String { rawValue.capitalized }

        var accentColor: Color {
            switch self {
            case .orange:  return Color(hex: 0xFF8C00)
            case .blue:    return Color(hex: 0x2196F3)
            case .green:   return Color(hex: 0x4CAF50)
            case .pink:    return Color(hex: 0xE91E63)
            case .purple:  return Color(hex: 0x9C27B0)
            case .red:     return Color(hex: 0xF44336)
            case .teal:    return Color(hex: 0x009688)
            case .indigo:  return Color(hex: 0x3F51B5)
            }
        }

        var containerColor: Color {
            switch self {
            case .orange:  return Color(hex: 0xFFF3E0)
            case .blue:    return Color(hex: 0xE3F2FD)
            case .green:   return Color(hex: 0xE8F5E9)
            case .pink:    return Color(hex: 0xFCE4EC)
            case .purple:  return Color(hex: 0xF3E5F5)
            case .red:     return Color(hex: 0xFFEBEE)
            case .teal:    return Color(hex: 0xE0F2F1)
            case .indigo:  return Color(hex: 0xE8EAF6)
            }
        }
    }

    @Published var colorFamily: ColorFamily {
        didSet { UserDefaults.standard.set(colorFamily.rawValue, forKey: "theme_color_family") }
    }

    @Published var followSystem: Bool {
        didSet { UserDefaults.standard.set(followSystem, forKey: "theme_follow_system") }
    }

    @Published var modeOverride: ThemeMode {
        didSet { UserDefaults.standard.set(modeOverride.rawValue, forKey: "theme_mode_override") }
    }

    enum ThemeMode: String, CaseIterable {
        case light, dark
        var displayName: String { rawValue.capitalized }
    }

    private init() {
        let savedFamily = UserDefaults.standard.string(forKey: "theme_color_family") ?? "orange"
        colorFamily = ColorFamily(rawValue: savedFamily) ?? .orange
        followSystem = UserDefaults.standard.object(forKey: "theme_follow_system") as? Bool ?? false
        let savedMode = UserDefaults.standard.string(forKey: "theme_mode_override") ?? "dark"
        modeOverride = ThemeMode(rawValue: savedMode) ?? .dark

        // Apply dark mode if not following system
        if !followSystem {
            applyThemeMode(modeOverride)
        }
    }

    /// Apply the selected theme mode to the app.
    private func applyThemeMode(_ mode: ThemeMode) {
        #if os(iOS)
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else { return }
        window.overrideUserInterfaceStyle = mode == .dark ? .dark : .light
        #endif
    }

    /// Called when followSystem changes.
    func updateAppearance() {
        if followSystem {
            #if os(iOS)
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first else { return }
            window.overrideUserInterfaceStyle = .unspecified
            #endif
        } else {
            applyThemeMode(modeOverride)
        }
    }

    // MARK: - Accent Colors (matching Android color XML values)

    /// Primary accent color for the selected family.
    var accentColor: Color {
        switch colorFamily {
        case .orange:  return Color(hex: 0xFF8C00)
        case .blue:    return Color(hex: 0x2196F3)
        case .green:   return Color(hex: 0x4CAF50)
        case .pink:    return Color(hex: 0xE91E63)
        case .purple:  return Color(hex: 0x9C27B0)
        case .red:     return Color(hex: 0xF44336)
        case .teal:    return Color(hex: 0x009688)
        case .indigo:  return Color(hex: 0x3F51B5)
        }
    }

    /// Container/accented background color (lighter tint).
    var containerColor: Color {
        switch colorFamily {
        case .orange:  return Color(hex: 0xFFF3E0)
        case .blue:    return Color(hex: 0xE3F2FD)
        case .green:   return Color(hex: 0xE8F5E9)
        case .pink:    return Color(hex: 0xFCE4EC)
        case .purple:  return Color(hex: 0xF3E5F5)
        case .red:     return Color(hex: 0xFFEBEE)
        case .teal:    return Color(hex: 0xE0F2F1)
        case .indigo:  return Color(hex: 0xE8EAF6)
        }
    }

    /// On-container foreground color (dark text on container background).
    var onContainerColor: Color {
        switch colorFamily {
        case .orange:  return Color(hex: 0x6D3A00)
        case .blue:    return Color(hex: 0x0D47A1)
        case .green:   return Color(hex: 0x1B5E20)
        case .pink:    return Color(hex: 0x880E4F)
        case .purple:  return Color(hex: 0x4A148C)
        case .red:     return Color(hex: 0xB71C1C)
        case .teal:    return Color(hex: 0x004D40)
        case .indigo:  return Color(hex: 0x1A237E)
        }
    }
}

extension Color {
    init(hex: UInt) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: 1.0
        )
    }
}
