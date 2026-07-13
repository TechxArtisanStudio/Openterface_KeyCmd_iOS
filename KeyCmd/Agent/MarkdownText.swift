import SwiftUI
import UIKit

/// Lightweight markdown renderer — headings (h1–h7), tables, paragraphs with inline formatting.
/// `AttributedString(markdown:)` only handles inline; this adds block-level parsing on top.
struct MarkdownText: View {
    let text: String

    private enum Block {
        case heading(level: Int, content: String)
        case table(rows: [[String]])
        case bulletList(items: [String])
        case numberedList(items: [String])
        case paragraph(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parse(text).enumerated()), id: \.offset) { _, block in
                render(block)
            }
        }
    }

    @ViewBuilder
    private func render(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let content):
            Text(attributed(content))
                .font(headingFont(level))
                .fontWeight(level <= 2 ? .bold : .semibold)

        case .table(let rows):
            tableGrid(rows)

        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•").font(.body)
                        Text(attributed(item)).font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case .numberedList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(idx + 1).")
                            .font(.body)
                            .monospacedDigit()
                        Text(attributed(item))
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case .paragraph(let content):
            Text(attributed(content))
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Parse

    private func parse(_ text: String) -> [Block] {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        var blocks: [Block] = []
        var i = 0

        while i < lines.count {
            let line = String(lines[i])
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let heading = parseHeading(trimmed) {
                blocks.append(heading)
                i += 1
            } else if let bullet = parseBullet(trimmed) {
                // Collect contiguous bullet lines
                var items = [bullet]
                i += 1
                while i < lines.count {
                    let next = String(lines[i]).trimmingCharacters(in: .whitespaces)
                    if let item = parseBullet(next) {
                        items.append(item)
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.bulletList(items: items))
            } else if let numbered = parseNumbered(trimmed) {
                var items = [numbered]
                i += 1
                while i < lines.count {
                    let next = String(lines[i]).trimmingCharacters(in: .whitespaces)
                    if let item = parseNumbered(next) {
                        items.append(item)
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.numberedList(items: items))
            } else if trimmed.contains("|") {
                var rows = parseTableRows(from: lines, start: i)
                if !rows.isEmpty {
                    rows = rows.filter { !isSeparatorRow($0) }
                    if !rows.isEmpty {
                        blocks.append(.table(rows: rows))
                    }
                    i += rawTableRowCount(lines: lines, start: i)
                } else {
                    blocks.append(.paragraph(trimmed))
                    i += 1
                }
            } else if trimmed.isEmpty {
                i += 1
            } else {
                blocks.append(.paragraph(trimmed))
                i += 1
            }
        }
        return blocks
    }

    private func parseHeading(_ line: String) -> Block? {
        // `#+` followed by space (or end of string)
        var level = 0
        for ch in line {
            if ch == "#" { level += 1 } else { break }
        }
        guard level >= 1 && level <= 7 else { return nil }
        if line.count == level { return .heading(level: level, content: "") }
        guard line.index(line.startIndex, offsetBy: level) < line.endIndex,
              line[line.index(line.startIndex, offsetBy: level)] == " " else { return nil }
        let content = String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces)
        return .heading(level: level, content: content)
    }

    // MARK: - List parsers

    /// Matches `- text`, `* text`, `+ text` (with optional leading indent).
    private func parseBullet(_ line: String) -> String? {
        // Strip leading whitespace (indent)
        let stripped = line.trimmingCharacters(in: .whitespaces)
        guard !stripped.isEmpty else { return nil }
        let first = stripped[stripped.startIndex]
        guard first == "-" || first == "*" || first == "+" else { return nil }
        let rest = String(stripped.dropFirst()).trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? nil : rest
    }

    /// Matches `1. text`, `2. text`, etc.
    private func parseNumbered(_ line: String) -> String? {
        let stripped = line.trimmingCharacters(in: .whitespaces)
        guard !stripped.isEmpty else { return nil }
        // Match `^\d+\. `
        guard let dotRange = stripped.firstIndex(of: "."),
              dotRange > stripped.startIndex,
              let after = stripped.index(dotRange, offsetBy: 1, limitedBy: stripped.endIndex),
              after < stripped.endIndex else { return nil }
        let numPart = stripped[..<dotRange]
        guard numPart.allSatisfy({ $0.isNumber }) else { return nil }
        let afterChar = stripped[after]
        guard afterChar == " " || afterChar == "\t" else { return nil }
        let content = stripped[after...].trimmingCharacters(in: .whitespaces)
        return content.isEmpty ? nil : content
    }

    /// Consume contiguous `|…|` lines starting at `start`, return split cells.
    private func parseTableRows(from lines: [Substring], start: Int) -> [[String]] {
        var rows: [[String]] = []
        var i = start
        while i < lines.count {
            let raw = String(lines[i]).trimmingCharacters(in: .whitespaces)
            guard raw.hasPrefix("|") || raw.contains("|") else { break }
            // A markdown table row must have at least one `|`; cells are the splits between pipes
            let cells = splitTableRow(raw)
            guard !cells.isEmpty else { break }
            rows.append(cells)
            i += 1
        }
        return rows
    }

    /// How many contiguous table-shaped lines start at `start`.
    private func rawTableRowCount(lines: [Substring], start: Int) -> Int {
        var count = 0
        var i = start
        while i < lines.count {
            let raw = String(lines[i]).trimmingCharacters(in: .whitespaces)
            guard raw.contains("|") else { break }
            count += 1
            i += 1
        }
        return count
    }

    private func splitTableRow(_ row: String) -> [String] {
        var s = row
        if s.hasPrefix("|") { s.removeFirst() }
        if s.hasSuffix("|") { s.removeLast() }
        return s.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private func isSeparatorRow(_ cells: [String]) -> Bool {
        !cells.allSatisfy { $0.isEmpty } &&
            cells.allSatisfy { cell in
                let trimmed = cell.trimmingCharacters(in: .whitespaces)
                return trimmed.allSatisfy { "-: ".contains($0) } && trimmed.contains("-")
            }
    }

    // MARK: - Render helpers

    @ViewBuilder
    private func tableGrid(_ rows: [[String]]) -> some View {
        if let header = rows.first {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                        Text(attributed(cell))
                            .font(.subheadline.weight(.semibold))
                    }
                }
                Divider().gridCellColumns(header.count)
                ForEach(Array(rows.dropFirst().enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(attributed(cell))
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(UIColor.secondarySystemBackground))
            )
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title
        case 2: return .title2
        case 3: return .title3
        case 4: return .headline
        case 5: return .subheadline
        case 6: return .footnote
        default: return .caption
        }
    }

    private func attributed(_ s: String) -> AttributedString {
        // inline-only markdown (bold/italic/code/links) — block structure handled above
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
    }
}
