import Foundation

/// Terminal preferences: font size, terminal dimensions, scrollback size.
/// Persisted in UserDefaults.
class TerminalPrefs {
    static let shared = TerminalPrefs()

    private let defaults = UserDefaults.standard

    private let fontSizeKey = "terminal_font_size"
    private let rowsKey = "terminal_rows"
    private let colsKey = "terminal_cols"
    private let scrollbackKey = "terminal_scrollback"

    var fontSize: CGFloat {
        get {
            let val = defaults.float(forKey: fontSizeKey)
            return val > 0 ? CGFloat(val) : 14
        }
        set { defaults.set(Float(newValue), forKey: fontSizeKey) }
    }

    var hasFontSizeOverride: Bool {
        defaults.object(forKey: fontSizeKey) != nil
    }

    var terminalRows: Int {
        defaults.object(forKey: rowsKey) != nil ? defaults.integer(forKey: rowsKey) : 24
    }

    var terminalCols: Int {
        defaults.object(forKey: colsKey) != nil ? defaults.integer(forKey: colsKey) : 80
    }

    var scrollbackSize: Int {
        defaults.object(forKey: scrollbackKey) != nil ? defaults.integer(forKey: scrollbackKey) : 2000
    }
}
