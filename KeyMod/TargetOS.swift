//
//  TargetOS.swift
//  KeyMod
//
//  Created on 2026/2/28.
//

import Foundation

/// The operating system running on the target (controlled) machine.
enum TargetOS: String, CaseIterable, Codable {
    case windows = "windows"
    case macOS   = "macOS"
    case linux   = "linux"

    /// Full display name shown in Settings.
    var displayName: String {
        switch self {
        case .windows: return "Windows"
        case .macOS:   return "macOS"
        case .linux:   return "Linux"
        }
    }

    /// Short label used in the compact sidebar picker.
    var shortName: String {
        switch self {
        case .windows: return "Win"
        case .macOS:   return "Mac"
        case .linux:   return "Linux"
        }
    }

    /// SF Symbol name representing the target OS.
    var systemImage: String {
        switch self {
        case .windows: return "pc"
        case .macOS:   return "laptopcomputer"
        case .linux:   return "terminal"
        }
    }

    /// Plain resource name (no extension, no directory) for the OS-specific command prompt section.
    /// Used with Bundle flat lookup — Xcode copies resources without preserving folder structure.
    var commandPromptResourceName: String {
        switch self {
        case .windows: return "command_windows"
        case .macOS:   return "command_macos"
        case .linux:   return "command_linux"
        }
    }

    /// Full path used as documentation reference (not used for bundle lookup).
    var commandPromptResource: String {
        return "Prompts/" + commandPromptResourceName
    }
}
