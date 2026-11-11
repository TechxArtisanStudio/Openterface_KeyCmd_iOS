//
//  KeyboardLayoutBuilders.swift
  //  KeyMod
  //

  import Foundation
  import SwiftUI

  /// Windows/Linux keyboard layout builder
  struct WindowsLayoutBuilder {
      static func build(
          for locale: KeyboardLocale,
          physicalStandard: KeyboardLocale.PhysicalStandard? = nil
      ) -> KeyboardLayoutDefinition {
          do {
              return addFnLayerKey(to: try KeyboardLayoutLoader.load(
                  locale: locale,
                  targetOS: .windows,
                  physicalStandard: physicalStandard
              ))
          } catch {
              // Fallback to US layout if specific locale layout fails
              return buildFallbackUSLayout()
          }
      }

      /// PC keyboard files only list physically printed keys, but this app needs
      /// an Fn key to reach the media/function layer. Fn is a local layer toggle
      /// (like the Mac layout's fn), so inject it without disturbing the JSON.
      private static func addFnLayerKey(to layout: KeyboardLayoutDefinition) -> KeyboardLayoutDefinition {
          var rows = layout.rows
          guard let bottomIndex = rows.indices.last,
                !rows[bottomIndex].contains(where: { $0.keyName == "Fn" })
          else { return layout }

          let fnKey = KeyDefinition(keyName: "Fn", label: "fn", hidUsageID: .keyboardFn)
          // Surface-style placement: between the left Control and Windows keys.
          let insertionIndex = rows[bottomIndex].firstIndex { $0.keyName == "LeftCtrl" }
              .map { $0 + 1 } ?? 0
          rows[bottomIndex].insert(fnKey, at: insertionIndex)

          return KeyboardLayoutDefinition(
              locale: layout.locale,
              targetOS: layout.targetOS,
              rows: rows,
              metadata: layout.metadata
          )
      }
  }

  /// macOS keyboard layout builder
  struct MacLayoutBuilder {
      static func build(
          for locale: KeyboardLocale,
          physicalStandard: KeyboardLocale.PhysicalStandard? = nil
      ) -> KeyboardLayoutDefinition {
          do {
              // Load from JSON first
              let baseLayout = try KeyboardLayoutLoader.load(
                  locale: locale,
                  targetOS: .macOS,
                  physicalStandard: physicalStandard
              )

              // Apply macOS-specific label modifications
              return applyMacOSModifications(to: baseLayout)
          } catch {
              // Fallback to Windows layout for the same locale
              return WindowsLayoutBuilder.build(for: locale, physicalStandard: physicalStandard)
          }
      }

      /// Apply macOS-specific modifications to modifier key labels
      private static func applyMacOSModifications(to baseLayout: KeyboardLayoutDefinition) -> KeyboardLayoutDefinition {
          var modifiedRows = baseLayout.rows

          // Rebuild the bottom row in Apple order: fn, Control, Option,
          // Command, Space, Command, Option. Relabelling in place would keep
          // the PC order and put Command where the Windows key sits.
          if let bottomRowIndex = modifiedRows.indices.last {
              // Relabel only: the HID usage ID and key type stay authoritative,
              // otherwise every relabelled modifier would become 0x04.
              func relabel(_ key: KeyDefinition) -> KeyDefinition {
                  let label: String
                  switch key.keyName {
                  case "Ctrl", "LeftCtrl", "RightCtrl":
                      label = "⌃"
                  case "Win", "LeftWin", "RightWin":
                      label = "⌘"
                  case "Alt", "LeftAlt":
                      label = "⌥"
                  case "RightAlt":
                      // Preserve "AltGr" label if it's actually an AltGr key
                      label = (key.label == "AltGr") ? "AltGr" : "⌥"
                  case "Menu":
                      // macOS doesn't have a Menu key, show fn instead
                      label = "fn"
                  default:
                      return key
                  }
                  return KeyDefinition(
                      keyName: key.keyName,
                      label: label,
                      shiftLabel: key.shiftLabel,
                      altGrLabel: key.altGrLabel,
                      keyCode: key.keyCode,
                      hidUsageID: key.hidUsageID,
                      keyType: key.keyType,
                      deadKey: key.deadKey,
                      widthMultiplier: key.widthMultiplier,
                      heightMultiplier: key.heightMultiplier
                  )
              }

              let labeledRow = modifiedRows[bottomRowIndex].map(relabel)
              // Apple JIS puts the 英数/かな keys immediately around Space; other
              // layouts keep the ANSI order. Keep the order data-driven so the
              // JSON stays the authoring source.
              var appleOrder = ["Fn", "LeftCtrl", "LeftAlt", "LeftWin"]
              if labeledRow.contains(where: { $0.keyName == "英数" }) {
                  appleOrder.append("英数")
              }
              appleOrder.append("Space")
              if labeledRow.contains(where: { $0.keyName == "かな" }) {
                  appleOrder.append("かな")
              }
              appleOrder.append(contentsOf: ["RightWin", "RightAlt", "RightCtrl"])
              // Anything else in the row is the arrow cluster and JIS-specific keys.
              let pcModifierKeys: Set<String> = [
                  "LeftCtrl", "LeftWin", "LeftAlt", "Space",
                  "RightAlt", "RightWin", "Fn", "RightCtrl"
              ]

              var reordered: [KeyDefinition] = []
              var placed: Set<String> = []
              for name in appleOrder {
                  // Apple's fn key reuses the PC Menu slot, and most layouts still
                  // carry that name; match the slot so it never falls off the row.
                  let isFnSlot: (KeyDefinition) -> Bool = {
                      $0.keyName == "Fn" || $0.keyName == "Menu"
                  }
                  guard let key = labeledRow.first(where: name == "Fn" ? isFnSlot: { $0.keyName == name }) else {
                      continue
                  }
                  reordered.append(key)
                  placed.insert(key.keyName)
              }
              reordered.append(contentsOf: labeledRow.filter {
                  !pcModifierKeys.contains($0.keyName) && !placed.contains($0.keyName)
              })
              modifiedRows[bottomRowIndex] = reordered
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
      static func build(
          for locale: KeyboardLocale,
          physicalStandard: KeyboardLocale.PhysicalStandard? = nil
      ) -> KeyboardLayoutDefinition {
          do {
              return try KeyboardLayoutLoader.load(
                  locale: locale,
                  targetOS: .linux,
                  physicalStandard: physicalStandard
              )
          } catch {
              // Fallback to Windows layout for the same locale
              return WindowsLayoutBuilder.build(for: locale, physicalStandard: physicalStandard)
          }
      }
  }

  /// US QWERTY fallback used only when the bundled JSON layouts cannot be
  /// loaded. Every key carries its real HID usage ID so a missing resource
  /// degrades to a working US keyboard instead of sending 0x04 for every key.
  private func buildFallbackUSLayout() -> KeyboardLayoutDefinition {
      let rows: [KeyRow] = [
          // Function row
          [
              KeyDefinition.key("Esc", "Esc", hid: .keyboardEscape),
              KeyDefinition.key("F1", "F1", hid: .keyboardF1),
              KeyDefinition.key("F2", "F2", hid: .keyboardF2),
              KeyDefinition.key("F3", "F3", hid: .keyboardF3),
              KeyDefinition.key("F4", "F4", hid: .keyboardF4),
              KeyDefinition.key("F5", "F5", hid: .keyboardF5),
              KeyDefinition.key("F6", "F6", hid: .keyboardF6),
              KeyDefinition.key("F7", "F7", hid: .keyboardF7),
              KeyDefinition.key("F8", "F8", hid: .keyboardF8),
              KeyDefinition.key("F9", "F9", hid: .keyboardF9),
              KeyDefinition.key("F10", "F10", hid: .keyboardF10),
              KeyDefinition.key("F11", "F11", hid: .keyboardF11),
              KeyDefinition.key("F12", "F12", hid: .keyboardF12)
          ],
          // Number row
          [
              KeyDefinition.key("`", "`", shift: "~", hid: .keyboardGraveAccent),
              KeyDefinition.key("1", "1", shift: "!", hid: .keyboard1),
              KeyDefinition.key("2", "2", shift: "@", hid: .keyboard2),
              KeyDefinition.key("3", "3", shift: "#", hid: .keyboard3),
              KeyDefinition.key("4", "4", shift: "$", hid: .keyboard4),
              KeyDefinition.key("5", "5", shift: "%", hid: .keyboard5),
              KeyDefinition.key("6", "6", shift: "^", hid: .keyboard6),
              KeyDefinition.key("7", "7", shift: "&", hid: .keyboard7),
              KeyDefinition.key("8", "8", shift: "*", hid: .keyboard8),
              KeyDefinition.key("9", "9", shift: "(", hid: .keyboard9),
              KeyDefinition.key("0", "0", shift: ")", hid: .keyboard0),
              KeyDefinition.key("-", "-", shift: "_", hid: .keyboardMinus),
              KeyDefinition.key("=", "=", shift: "+", hid: .keyboardEqual),
              KeyDefinition.special("Backspace", hid: .keyboardBackspace)
          ],
          // QWERTY first row
          [
              KeyDefinition.special("Tab", hid: .keyboardTab),
              KeyDefinition.key("q", "Q", hid: .keyboardQ),
              KeyDefinition.key("w", "W", hid: .keyboardW),
              KeyDefinition.key("e", "E", hid: .keyboardE),
              KeyDefinition.key("r", "R", hid: .keyboardR),
              KeyDefinition.key("t", "T", hid: .keyboardT),
              KeyDefinition.key("y", "Y", hid: .keyboardY),
              KeyDefinition.key("u", "U", hid: .keyboardU),
              KeyDefinition.key("i", "I", hid: .keyboardI),
              KeyDefinition.key("o", "O", hid: .keyboardO),
              KeyDefinition.key("p", "P", hid: .keyboardP),
              KeyDefinition.key("[", "[", shift: "{", hid: .keyboardLeftBracket),
              KeyDefinition.key("]", "]", shift: "}", hid: .keyboardRightBracket),
              KeyDefinition.key("\\", "\\", shift: "|", hid: .keyboardBackslash)
          ],
          // ASDF second row
          [
              KeyDefinition.special("Caps", hid: .keyboardCapsLock),
              KeyDefinition.key("a", "a", hid: .keyboardA),
              KeyDefinition.key("s", "s", hid: .keyboardS),
              KeyDefinition.key("d", "d", hid: .keyboardD),
              KeyDefinition.key("f", "f", hid: .keyboardF),
              KeyDefinition.key("g", "g", hid: .keyboardG),
              KeyDefinition.key("h", "h", hid: .keyboardH),
              KeyDefinition.key("j", "j", hid: .keyboardJ),
              KeyDefinition.key("k", "k", hid: .keyboardK),
              KeyDefinition.key("l", "l", hid: .keyboardL),
              KeyDefinition.key(";", ";", shift: ":", hid: .keyboardSemicolon),
              KeyDefinition.key("'", "'", shift: "\"", hid: .keyboardQuote),
              KeyDefinition.special("Enter", hid: .keyboardEnter)
          ],
          // ZXCV third row
          [
              KeyDefinition.mod("Shift", hid: .keyboardLeftShift, width: 1.5),
              KeyDefinition.key("z", "z", hid: .keyboardZ),
              KeyDefinition.key("x", "x", hid: .keyboardX),
              KeyDefinition.key("c", "c", hid: .keyboardC),
              KeyDefinition.key("v", "v", hid: .keyboardV),
              KeyDefinition.key("b", "b", hid: .keyboardB),
              KeyDefinition.key("n", "n", hid: .keyboardN),
              KeyDefinition.key("m", "m", hid: .keyboardM),
              KeyDefinition.key(",", ",", shift: "<", hid: .keyboardComma),
              KeyDefinition.key(".", ".", shift: ">", hid: .keyboardPeriod),
              KeyDefinition.key("/", "/", shift: "?", hid: .keyboardSlash),
              KeyDefinition.mod("Shift", hid: .keyboardRightShift, width: 1.5),
              KeyDefinition.special("Up", label: "↑", hid: .keyboardUpArrow)
          ],
          // Bottom modifier row
          [
              KeyDefinition.mod("Ctrl", hid: .keyboardLeftCtrl),
              KeyDefinition(keyName: "Fn", label: "fn", hidUsageID: .keyboardFn),
              KeyDefinition.mod("Win", hid: .keyboardLeftGUI),
              KeyDefinition.mod("Alt", hid: .keyboardLeftAlt),
              KeyDefinition.key("Space", " ", hid: .keyboardSpace, width: 6.0),
              KeyDefinition.mod("AltGr", hid: .keyboardRightAlt),
              KeyDefinition.mod("Win", hid: .keyboardRightGUI),
              KeyDefinition.special("Menu", keyCode: "App", hid: .keyboardApplication),
              KeyDefinition.mod("Ctrl", hid: .keyboardRightCtrl),
              KeyDefinition.special("Left", label: "←", hid: .keyboardLeftArrow),
              KeyDefinition.special("Down", label: "↓", hid: .keyboardDownArrow),
              KeyDefinition.special("Right", label: "→", hid: .keyboardRightArrow)
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
