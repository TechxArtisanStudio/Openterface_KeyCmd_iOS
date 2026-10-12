//
//  KeyboardLayoutBuilders.swift
  //  KeyMod
  //

  import Foundation
  import SwiftUI

  /// Windows/Linux keyboard layout builder
  struct WindowsLayoutBuilder {
      static func build(for locale: KeyboardLocale) -> KeyboardLayoutDefinition {
          do {
              return try KeyboardLayoutLoader.load(locale: locale, targetOS: .windows)
          } catch {
              // Fallback to US layout if specific locale layout fails
              return buildFallbackUSLayout()
          }
      }
  }

  /// macOS keyboard layout builder
  struct MacLayoutBuilder {
      static func build(for locale: KeyboardLocale) -> KeyboardLayoutDefinition {
          do {
              // Load from JSON first
              let baseLayout = try KeyboardLayoutLoader.load(locale: locale, targetOS: .macOS)

              // Apply macOS-specific label modifications
              return applyMacOSModifications(to: baseLayout)
          } catch {
              // Fallback to Windows layout for the same locale
              return WindowsLayoutBuilder.build(for: locale)
          }
      }

      /// Apply macOS-specific modifications to modifier key labels
      private static func applyMacOSModifications(to baseLayout: KeyboardLayoutDefinition) -> KeyboardLayoutDefinition {
          var modifiedRows = baseLayout.rows

          // Update the bottom modifier row for macOS
          // Change: Ctrl → Control, Win → ⌘, Alt → ⌥, Menu → fn
          if modifiedRows.count > 0 {
              let bottomRowIndex = modifiedRows.count - 1
              if bottomRowIndex >= 0 && bottomRowIndex < modifiedRows.count {
                  var bottomRow = modifiedRows[bottomRowIndex]
                  for i in 0..<bottomRow.count {
                      let keyName = bottomRow[i].keyName
                      switch keyName {
                      case "Ctrl", "LeftCtrl", "RightCtrl":
                          bottomRow[i] = KeyDefinition.mod(keyName, label: "⌃")
                      case "Win", "LeftWin", "RightWin":
                          bottomRow[i] = KeyDefinition.mod(keyName, label: "⌘")
                      case "Alt", "LeftAlt", "RightAlt":
                          bottomRow[i] = KeyDefinition.mod(keyName, label: "⌥")
                      case "Menu":
                          // macOS doesn't have a Menu key, relabel to fn
                          bottomRow[i] = KeyDefinition.mod(keyName, label: "fn")
                      default:
                          break
                      }
                  }
                  modifiedRows[bottomRowIndex] = bottomRow
              }
          }

          let metadata = LayoutMetadata(
              name: baseLayout.metadata.name.replacingOccurrences(of: "Windows", with: "macOS"),
              description: baseLayout.metadata.description,
              rowHeights: baseLayout.metadata.rowHeights,
              keySpacing: baseLayout.metadata.keySpacing,
              rowSpacing: baseLayout.metadata.rowSpacing,
              padding: baseLayout.metadata.padding,
              fixedKeyWidths: baseLayout.metadata.fixedKeyWidths,
              physicalStandard: baseLayout.metadata.physicalStandard,
              hasAltGr: baseLayout.metadata.hasAltGr
          )

          return KeyboardLayoutDefinition(
              locale: baseLayout.locale,
              targetOS: .macOS,
              rows: modifiedRows,
              metadata: metadata
          )
      }
  }

  /// Linux keyboard layout builder
  struct LinuxLayoutBuilder {
      static func build(for locale: KeyboardLocale) -> KeyboardLayoutDefinition {
          do {
              return try KeyboardLayoutLoader.load(locale: locale, targetOS: .linux)
          } catch {
              // Fallback to Windows layout for the same locale
              return WindowsLayoutBuilder.build(for: locale)
          }
      }
  }

  /// Trimmer-down US layout fallback that doesn't reference HID Usage IDs directly
  private func buildFallbackUSLayout() -> KeyboardLayoutDefinition {
      let rows: [KeyRow] = [
          // Function row
          [
              KeyDefinition.key("Esc", "Esc"),
              KeyDefinition.key("F1", "F1"),
              KeyDefinition.key("F2", "F2"),
              KeyDefinition.key("F3", "F3"),
              KeyDefinition.key("F4", "F4"),
              KeyDefinition.key("F5", "F5"),
              KeyDefinition.key("F6", "F6"),
              KeyDefinition.key("F7", "F7"),
              KeyDefinition.key("F8", "F8"),
              KeyDefinition.key("F9", "F9"),
              KeyDefinition.key("F10", "F10"),
              KeyDefinition.key("F11", "F11"),
              KeyDefinition.key("F12", "F12")
          ],
          // Number row
          [
              KeyDefinition.key("`", "`", shift: "~"),
              KeyDefinition.key("1", "1", shift: "!"),
              KeyDefinition.key("2", "2", shift: "@"),
              KeyDefinition.key("3", "3", shift: "#"),
              KeyDefinition.key("4", "4", shift: "$"),
              KeyDefinition.key("5", "5", shift: "%"),
              KeyDefinition.key("6", "6", shift: "^"),
              KeyDefinition.key("7", "7", shift: "&"),
              KeyDefinition.key("8", "8", shift: "*"),
              KeyDefinition.key("9", "9", shift: "("),
              KeyDefinition.key("0", "0", shift: ")"),
              KeyDefinition.key("-", "-", shift: "_"),
              KeyDefinition.key("=", "=", shift: "+"),
              KeyDefinition.key("Backspace", "Backspace")
          ],
          // QWERTY first row
          [
              KeyDefinition.key("Tab", "Tab"),
              KeyDefinition.key("q", "Q"),
              KeyDefinition.key("w", "W"),
              KeyDefinition.key("e", "E"),
              KeyDefinition.key("r", "R"),
              KeyDefinition.key("t", "T"),
              KeyDefinition.key("y", "Y"),
              KeyDefinition.key("u", "U"),
              KeyDefinition.key("i", "I"),
              KeyDefinition.key("o", "O"),
              KeyDefinition.key("p", "P"),
              KeyDefinition.key("[", "[", shift: "{"),
              KeyDefinition.key("]", "]", shift: "}"),
              KeyDefinition.key("\\", "\\", shift: "|")
          ],
          // ASDF second row
          [
              KeyDefinition.key("Caps", "Caps"),
              KeyDefinition.key("a", "a"),
              KeyDefinition.key("s", "s"),
              KeyDefinition.key("d", "d"),
              KeyDefinition.key("f", "f"),
              KeyDefinition.key("g", "g"),
              KeyDefinition.key("h", "h"),
              KeyDefinition.key("j", "j"),
              KeyDefinition.key("k", "k"),
              KeyDefinition.key("l", "l"),
              KeyDefinition.key(";", ";", shift: ":"),
              KeyDefinition.key("'", "'", shift: "\""),
              KeyDefinition.key("Enter", "Enter")
          ],
          // ZXCV third row
          [
              KeyDefinition.mod("Shift", width: 1.5),
              KeyDefinition.key("z", "z"),
              KeyDefinition.key("x", "x"),
              KeyDefinition.key("c", "c"),
              KeyDefinition.key("v", "v"),
              KeyDefinition.key("b", "b"),
              KeyDefinition.key("n", "n"),
              KeyDefinition.key("m", "m"),
              KeyDefinition.key(",", ",", shift: "<"),
              KeyDefinition.key(".", ".", shift: ">"),
              KeyDefinition.key("/", "/", shift: "?"),
              KeyDefinition.mod("Shift", width: 1.5),
              KeyDefinition.key("Up", "↑")
          ],
          // Bottom modifier row
          [
              KeyDefinition.mod("Ctrl"),
              KeyDefinition.mod("Win"),
              KeyDefinition.mod("Alt"),
              KeyDefinition.key("Space", " ", width: 6.0),
              KeyDefinition.mod("Alt"),
              KeyDefinition.mod("Win"),
              KeyDefinition.key("Menu", "Menu", keyCode: "App"),
              KeyDefinition.mod("Ctrl"),
              KeyDefinition.key("Left", "←"),
              KeyDefinition.key("Down", "↓"),
              KeyDefinition.key("Right", "→")
          ]
      ]

      let metadata = LayoutMetadata(
          name: "US QWERTY Windows",
          description: "Standard US QWERTY layout for Windows",
          rowHeights: [0.1, 0.1, 0.2, 0.2, 0.2, 0.2],
          keySpacing: 3,
          rowSpacing: 6,
          padding: LayoutPadding(top: 8, leading: 8, bottom: 8, trailing: 8),
          fixedKeyWidths: ["Space": 200],
          physicalStandard: .ansi
      )

      return KeyboardLayoutDefinition(
          locale: .us,
          targetOS: .windows,
          rows: rows,
          metadata: metadata
      )
  }
