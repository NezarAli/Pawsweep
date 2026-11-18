// Reads what Mole is showing, so a mouse can drive it.
//
// Mole draws every interactive screen the same way: a list whose selected row
// starts with an arrow (➤ in the shell menus, ▶ in the disk analyzer), and a
// gray line of key hints such as "↑↓  |  Space Select  |  Enter Confirm  |  Q Quit".
// This file finds both in the visible text. It changes nothing in Mole.

import Foundation

/// One visible terminal row: its text, and the display width of each cell.
/// A wide glyph's trailing cell has width 0 and no character in `text`.
public struct ScreenRow: Sendable, Equatable {
    public let text: String
    public let cellWidths: [Int]

    public init(text: String, cellWidths: [Int] = []) {
        self.text = text
        self.cellWidths = cellWidths
    }
}

/// A key the screen offers, parsed from its hint line.
public struct HintKey: Sendable, Equatable, Identifiable {
    /// What the key cap shows: "Space", "Q", "↑".
    public let keyName: String
    /// What the key does, as the hint words it: "Select". Empty for bare keys such as "Enter".
    public let label: String
    /// The bytes a terminal sends for this key.
    public let bytes: [UInt8]
    /// Where the hint is drawn, so a click on it presses the key.
    public let row: Int
    public let columns: Range<Int>

    public var id: String { "\(row):\(columns.lowerBound):\(keyName)" }

    public init(keyName: String, label: String, bytes: [UInt8], row: Int, columns: Range<Int>) {
        self.keyName = keyName
        self.label = label
        self.bytes = bytes
        self.row = row
        self.columns = columns
    }
}

public enum Keys {
    public static let up: [UInt8] = [0x1B, 0x5B, 0x41]
    public static let down: [UInt8] = [0x1B, 0x5B, 0x42]
    public static let right: [UInt8] = [0x1B, 0x5B, 0x43]
    public static let left: [UInt8] = [0x1B, 0x5B, 0x44]
    public static let enter: [UInt8] = [0x0D]
    public static let space: [UInt8] = [0x20]
    public static let escape: [UInt8] = [0x1B]
    public static let backspace: [UInt8] = [0x7F]
    public static let tab: [UInt8] = [0x09]
    public static let interrupt: [UInt8] = [0x03]
}

public struct ScreenModel: Sendable {
    public let rows: [ScreenRow]
    /// Keys offered by the hint lines, in the order they are drawn.
    public let hints: [HintKey]
    public let hintRows: Set<Int>
    /// The row of the selected list item, when exactly one row is marked.
    public let markerRow: Int?
    /// The rows of the list the marker sits in.
    public let listRows: ClosedRange<Int>?

    /// The arrows Mole uses to mark the selected row.
    static let markers: Set<Character> = ["➤", "▶"]
    static let checkboxes: Set<Character> = ["●", "○"]

    public init(rows: [ScreenRow]) {
        self.rows = rows
        let cells = rows.map(Self.cells(of:))

        var hints: [HintKey] = []
        var hintRows = Set<Int>()
        for (index, rowCells) in cells.enumerated() {
            let continuesHints = hintRows.contains(index - 1)
            if let keys = Self.parseHintLine(rowCells, row: index, continuation: continuesHints) {
                hints += keys
                hintRows.insert(index)
            }
        }
        self.hints = hints
        self.hintRows = hintRows

        var candidates: [(row: Int, textColumn: Int)] = []
        for (index, rowCells) in cells.enumerated() where !hintRows.contains(index) {
            if let column = Self.textColumnAfterMarker(rowCells) {
                candidates.append((index, column))
            }
        }
        if candidates.count == 1, let marker = candidates.first {
            markerRow = marker.row
            let isItem: (Int) -> Bool = { row in
                guard row >= 0, row < cells.count, !hintRows.contains(row) else { return false }
                return row == marker.row || Self.isUnselectedItem(cells[row], textColumn: marker.textColumn)
            }
            var top = marker.row
            while isItem(top - 1) { top -= 1 }
            var bottom = marker.row
            while isItem(bottom + 1) { bottom += 1 }
            listRows = top...bottom
        } else {
            markerRow = nil
            listRows = nil
        }
    }

    /// For tests and plain text: every character one cell wide.
    public init(texts: [String]) {
        self.init(rows: texts.map { ScreenRow(text: $0) })
    }

    /// A list with a hint line is on screen, so clicks and the scroll wheel move the selection.
    public var isMenu: Bool { markerRow != nil && !hints.isEmpty }

    public func hint(atRow row: Int, column: Int) -> HintKey? {
        hints.first { $0.row == row && $0.columns.contains(column) }
    }

    public func isListRow(_ row: Int) -> Bool {
        listRows?.contains(row) ?? false
    }

    /// The row is a checkbox item ("● name" or "○ name"), toggled with Space.
    public func isCheckboxRow(_ row: Int) -> Bool {
        guard row >= 0, row < rows.count else { return false }
        var characters = Substring(rows[row].text).drop { $0 == " " }
        if let first = characters.first, Self.markers.contains(first) {
            characters = characters.dropFirst().drop { $0 == " " }
        }
        guard let first = characters.first else { return false }
        return Self.checkboxes.contains(first)
    }

    // MARK: - Cells

    struct Cell {
        let character: Character
        let column: Int
        let width: Int
    }

    /// Pairs each character with the column it is drawn at.
    static func cells(of row: ScreenRow) -> [Cell] {
        let characters = Array(row.text)
        let widths = row.cellWidths.filter { $0 > 0 }
        let useWidths = widths.count == characters.count
        var column = 0
        var result: [Cell] = []
        result.reserveCapacity(characters.count)
        for (index, character) in characters.enumerated() {
            let width = useWidths ? widths[index] : 1
            result.append(Cell(character: character, column: column, width: width))
            column += width
        }
        return result
    }

    // MARK: - Selected row

    /// For a row that starts (after spaces) with "➤ " or "▶ ", the column where its
    /// text begins after the marker.
    static func textColumnAfterMarker(_ cells: [Cell]) -> Int? {
        guard let index = cells.firstIndex(where: { $0.character != " " }),
              markers.contains(cells[index].character) else { return nil }
        let next = index + 1
        guard next < cells.count, cells[next].character == " " else { return nil }
        guard let text = cells[next...].firstIndex(where: { $0.character != " " }) else { return nil }
        return cells[text].column
    }

    /// An unselected item's text starts where the selected item's text does
    /// ("➤ 1. Clean" / "  2. Uninstall"; " ▶  1. Library" / "    2. Projects").
    static func isUnselectedItem(_ cells: [Cell], textColumn: Int) -> Bool {
        guard let index = cells.firstIndex(where: { $0.character != " " }) else { return false }
        return cells[index].column == textColumn
    }

    // MARK: - Hint lines

    struct Segment {
        let text: String
        let cells: [Cell]
    }

    /// Splits a row at "|" into trimmed segments that keep their cells.
    static func segments(_ cells: [Cell]) -> [Segment] {
        var result: [Segment] = []
        var current: [Cell] = []
        func flush() {
            let trimmed = Array(current.drop { $0.character == " " }.reversed().drop { $0.character == " " }.reversed())
            if !trimmed.isEmpty {
                result.append(Segment(text: String(trimmed.map(\.character)), cells: trimmed))
            }
            current = []
        }
        for cell in cells {
            if cell.character == "|" { flush() } else { current.append(cell) }
        }
        flush()
        return result
    }

    /// A row is a hint line when it has at least two segments that read as keys and
    /// those are at least half of its segments. App rows such as
    /// "Photoshop  4.20GB | 2mo ago" do not qualify. A row right under a hint line
    /// continues it when every segment reads as a key (Mole wraps long hint lines).
    static func parseHintLine(_ cells: [Cell], row: Int, continuation: Bool) -> [HintKey]? {
        // Mole spaces its separators ("Enter  |  Q Quit"); ASCII art such as the
        // banner's "|_|  |_|\___/" does not.
        for (index, cell) in cells.enumerated() where cell.character == "|" {
            let spacedBefore = index == 0 || cells[index - 1].character == " "
            let spacedAfter = index == cells.count - 1 || cells[index + 1].character == " "
            if !spacedBefore || !spacedAfter { return nil }
        }
        let segments = segments(cells)
        guard !segments.isEmpty else { return nil }
        var keys: [HintKey] = []
        var parsedSegments = 0
        for segment in segments {
            let parsed = parseSegment(segment, row: row)
            if !parsed.isEmpty {
                parsedSegments += 1
                keys += parsed
            }
        }
        let isLine = segments.count >= 2 && parsedSegments >= 2 && parsedSegments * 2 >= segments.count
        let isContinuation = continuation && parsedSegments == segments.count
        return (isLine || isContinuation) ? keys : nil
    }

    /// "Space Select" → Space labelled "Select"; "↑↓" → two arrow keys; "h/l Page" → two page keys.
    static func parseSegment(_ segment: Segment, row: Int) -> [HintKey] {
        let text = segment.text
        let tokenEnd = text.firstIndex(of: " ") ?? text.endIndex
        let token = String(text[..<tokenEnd])
        let label = text[tokenEnd...].trimmingCharacters(in: .whitespaces)
        // Hint labels are one or two words ("Select", "Next page", "Del 3"); longer text is prose.
        guard label.split(separator: " ").count <= 2 else { return [] }
        let tokenCells = Array(segment.cells.prefix(token.count))
        guard let first = segment.cells.first, let last = segment.cells.last else { return [] }
        let wholeSegment = first.column..<(last.column + last.width)

        // Arrows: one key per glyph, each clickable where it is drawn.
        if !token.isEmpty, token.allSatisfy({ arrowBytes[$0] != nil }) {
            return tokenCells.compactMap { cell in
                guard let bytes = arrowBytes[cell.character] else { return nil }
                return HintKey(keyName: String(cell.character), label: "", bytes: bytes,
                               row: row, columns: cell.column..<(cell.column + cell.width))
            }
        }

        // Paginated menus: "h/l Page".
        if token == "h/l", tokenCells.count == 3 {
            return [
                HintKey(keyName: "h", label: "Previous page", bytes: Array("h".utf8), row: row,
                        columns: tokenCells[0].column..<(tokenCells[0].column + 1)),
                HintKey(keyName: "l", label: "Next page", bytes: Array("l".utf8), row: row,
                        columns: tokenCells[2].column..<(tokenCells[2].column + 1)),
            ]
        }

        if let key = parseKeyToken(token) {
            return [HintKey(keyName: key.name, label: label, bytes: key.bytes, row: row, columns: wholeSegment)]
        }

        // "Q/Ctrl+C Quit", "Esc/Q Quit": the first key is the one to press.
        if token.count > 1, token.contains("/") {
            let first = String(token.split(separator: "/").first ?? "")
            if let key = parseKeyToken(first) {
                return [HintKey(keyName: key.name, label: label, bytes: key.bytes, row: row, columns: wholeSegment)]
            }
        }
        return []
    }

    static let arrowBytes: [Character: [UInt8]] = [
        "↑": Keys.up, "↓": Keys.down, "←": Keys.left, "→": Keys.right,
    ]

    static func parseKeyToken(_ token: String) -> (name: String, bytes: [UInt8])? {
        switch token {
        case "Enter", "Return": return ("Enter", Keys.enter)
        case "Space": return ("Space", Keys.space)
        case "Esc": return ("Esc", Keys.escape)
        case "Tab": return ("Tab", Keys.tab)
        case "Backspace", "Delete", "Del", "⌫": return ("⌫", Keys.backspace)
        default: break
        }
        if token.hasPrefix("Ctrl+"), token.count == 6, let letter = token.last,
           letter.isASCII, letter.isLetter, let ascii = letter.uppercased().first?.asciiValue {
            return ("⌃\(letter.uppercased())", [ascii & 0x1F])
        }
        // A letter, digit, "/" or "?", in the case the hint shows it
        // (Mole reads "R" and "r" differently in places).
        if token.count == 1, let character = token.first, character.isASCII,
           character.isLetter || character.isNumber || character == "/" || character == "?",
           let ascii = character.asciiValue {
            return (token, [ascii])
        }
        return nil
    }
}
