import CoreGraphics
import SwiftUI

/// Describes the keyboard layout as a grid of key names with sizing metadata.
/// The touch container uses this to compute key frames without depending on SwiftUI layout.
struct KeyboardLayoutDescription {
    let rows: [[String]]
    let containerSize: CGSize
    let rowSpacing: CGFloat
    let keySpacing: CGFloat
    let padding: EdgeInsets
    /// Explicit heights for specific row indices. Rows not listed share remaining height equally.
    let fixedRowHeights: [CGFloat]
    /// Explicit widths for specific key names (e.g., "Space" → 200pt).
    let fixedKeyWidths: [String: CGFloat]

    init(
        rows: [[String]],
        containerSize: CGSize,
        rowSpacing: CGFloat,
        keySpacing: CGFloat,
        padding: EdgeInsets,
        fixedRowHeights: [CGFloat],
        fixedKeyWidths: [String: CGFloat]
    ) {
        self.rows = rows
        self.containerSize = containerSize
        self.rowSpacing = rowSpacing
        self.keySpacing = keySpacing
        self.padding = padding
        self.fixedRowHeights = fixedRowHeights
        self.fixedKeyWidths = fixedKeyWidths
    }
}

/// Stores key registrations and performs coordinate-based hit-testing.
/// Thread-safe: all access is on the main thread (UI touch events).
final class KeyFrameRegistry {
    private var registrations: [KeyRegistration] = []

    func register(_ registration: KeyRegistration) {
        registrations.append(registration)
    }

    func clear() {
        registrations.removeAll()
    }

    /// Returns the key at the given point, or nil if no key contains the point.
    /// If multiple keys overlap, the last registered key wins.
    func hitTest(_ point: CGPoint) -> KeyRegistration? {
        // Iterate in reverse so later registrations (drawn on top) take priority
        for reg in registrations.reversed() {
            if reg.frame.contains(point) {
                return reg
            }
        }
        return nil
    }

    /// All currently registered keys.
    var allKeys: [KeyRegistration] { registrations }
}

extension KeyFrameRegistry {
    /// Compute key frames from a layout description and register all keys.
    /// - Parameters:
    ///   - layout: The keyboard layout description.
    ///   - keyTypeResolver: Closure that maps a key name to its KeyType.
    func computeFrames(from layout: KeyboardLayoutDescription, keyTypeResolver: (String) -> KeyType) {
        clear()

        let contentOriginX = layout.padding.leading
        let contentOriginY = layout.padding.top
        let contentWidth = layout.containerSize.width - layout.padding.leading - layout.padding.trailing
        let contentHeight = layout.containerSize.height - layout.padding.top - layout.padding.bottom

        // Compute row heights
        let totalRowSpacing = CGFloat(max(0, layout.rows.count - 1)) * layout.rowSpacing
        let fixedHeightSum = layout.fixedRowHeights.reduce(0, +)
        let flexibleRowCount = layout.rows.count - layout.fixedRowHeights.count
        let flexibleRowHeight: CGFloat
        if flexibleRowCount > 0 {
            flexibleRowHeight = max(0, contentHeight - totalRowSpacing - fixedHeightSum) / CGFloat(flexibleRowCount)
        } else {
            flexibleRowHeight = 0
        }

        var currentY = contentOriginY
        for (rowIdx, row) in layout.rows.enumerated() {
            let rowHeight: CGFloat
            if rowIdx < layout.fixedRowHeights.count {
                rowHeight = layout.fixedRowHeights[rowIdx]
            } else {
                rowHeight = flexibleRowHeight
            }

            // Compute key widths for this row
            let totalKeySpacing = CGFloat(max(0, row.count - 1)) * layout.keySpacing
            var fixedWidthSum: CGFloat = 0
            var flexibleKeyCount = 0
            for keyName in row {
                if let fixedWidth = layout.fixedKeyWidths[keyName] {
                    fixedWidthSum += fixedWidth
                } else {
                    flexibleKeyCount += 1
                }
            }
            let flexibleKeyWidth: CGFloat
            if flexibleKeyCount > 0 {
                flexibleKeyWidth = max(0, contentWidth - totalKeySpacing - fixedWidthSum) / CGFloat(flexibleKeyCount)
            } else {
                flexibleKeyWidth = 0
            }

            var currentX = contentOriginX
            for keyName in row {
                let keyWidth: CGFloat
                if let fixedWidth = layout.fixedKeyWidths[keyName] {
                    keyWidth = fixedWidth
                } else {
                    keyWidth = flexibleKeyWidth
                }

                let frame = CGRect(x: currentX, y: currentY, width: keyWidth, height: rowHeight)
                let keyType = keyTypeResolver(keyName)
                register(KeyRegistration(
                    keyId: "\(rowIdx)-\(keyName)",
                    keyName: keyName,
                    keyType: keyType,
                    frame: frame
                ))

                currentX += keyWidth + layout.keySpacing
            }

            currentY += rowHeight + layout.rowSpacing
        }
    }
}
