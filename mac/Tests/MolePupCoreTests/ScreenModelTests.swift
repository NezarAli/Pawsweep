import Testing
@testable import MolePupCore

struct ScreenModelTests {
    // The main menu, as `mo` draws it (bin/mole show_main_menu).
    let mainMenu = [
        "",
        "  Mole  Deep clean and optimize your Mac.",
        "",
        "➤ 1. Clean        Free up disk space",
        "  2. Uninstall    Remove apps completely",
        "  3. Optimize     Refresh caches and services",
        "  4. Analyze      Explore disk usage",
        "  5. Status       Monitor system health",
        "",
        "↑↓  |  Enter  |  M More  |  V Version  |  T TouchID  |  Q Quit",
    ]

    // The banner above the main menu (show_brand_banner) is drawn with "|".
    @Test func testBannerIsNotAHintLine() {
        let screen = ScreenModel(texts: [
            " __  __       _",
            "|  \\/  | ___ | | ___",
            "| |\\/| |/ _ \\| |/ _ \\",
            "| |  | | (_) | |  __/  https://mole.fit",
            "|_|  |_|\\___/|_|\\___|  Deep clean and optimize your Mac.",
            "",
        ] + mainMenu.dropFirst(3))
        #expect(screen.hints.map(\.keyName) == ["↑", "↓", "Enter", "M", "V", "T", "Q"])
        #expect(screen.markerRow == 6)
    }

    @Test func testMainMenuMarkerListAndHints() {
        let screen = ScreenModel(texts: mainMenu)
        #expect(screen.markerRow == 3)
        #expect(screen.listRows == 3...7)
        #expect(screen.isMenu)
        #expect(screen.hintRows == [9])
        #expect(screen.hints.map(\.keyName) == ["↑", "↓", "Enter", "M", "V", "T", "Q"])
        #expect(screen.hints.map(\.label) == ["", "", "", "More", "Version", "TouchID", "Quit"])
        #expect(screen.hints[2].bytes == Keys.enter)
        #expect(screen.hints[0].bytes == Keys.up)
        #expect(!screen.isCheckboxRow(4))
    }

    // The analyzer's overview pads its numbers (" 1."), so items start one column further in.
    @Test func testAnalyzerOverviewWithPaddedNumbers() {
        let screen = ScreenModel(texts: [
            "Analyze Disk  (821.7 GB free)",
            "Select a location to explore:",
            "",
            " ▶  1. ████████████  --    |  System Library     51.5 GB+",
            "    2. █████████     --    |  User Library       39.6 GB+",
            "    3. █████         --    |  Applications       24.1 GB",
            "",
            "↑↓→ | Enter | R Refresh | O Open | P Preview | F File | Esc/Q Quit",
        ])
        #expect(screen.markerRow == 3)
        #expect(screen.listRows == 3...5)
        #expect(screen.hintRows == [7])
        #expect(screen.hints.last?.keyName == "Esc")
    }

    @Test func testClickingAHintFindsItsKey() {
        let screen = ScreenModel(texts: mainMenu)
        let line = mainMenu[9]
        let quitColumn = line.distance(from: line.startIndex, to: line.range(of: "Q Quit")!.lowerBound)
        #expect(screen.hint(atRow: 9, column: quitColumn)?.keyName == "Q")
        #expect(screen.hint(atRow: 9, column: quitColumn + 3)?.keyName == "Q")
        #expect(screen.hint(atRow: 9, column: 1)?.keyName == "↓")
        #expect(screen.hint(atRow: 9, column: 3) == nil, "the spaces around a separator press nothing")
        #expect(screen.hint(atRow: 4, column: 4) == nil)
    }

    // The app picker (lib/ui/menu_paginated.sh): checkbox rows, and rows that contain "|".
    @Test func testCheckboxListWithPipesInRows() {
        let screen = ScreenModel(texts: [
            "Select Apps to Remove  1/3 selected",
            "",
            "➤ ● Photoshop 2024                4.20GB | 2mo ago",
            "  ○ IntelliJ IDEA                 2.80GB | 3d ago",
            "  ○ Premiere Pro                  3.40GB | 2w ago",
            "",
            "↑↓ | Space Select | A All | Enter Save | Q Cancel | S Size | O ↑ | / Search | h/l Page",
        ])
        #expect(screen.markerRow == 2)
        #expect(screen.listRows == 2...4)
        #expect(screen.hintRows == [6], "app rows with a | are not hint lines")
        #expect(screen.isCheckboxRow(2))
        #expect(screen.isCheckboxRow(3))
        #expect(screen.hints.map(\.keyName) == ["↑", "↓", "Space", "A", "Enter", "Q", "S", "O", "/", "h", "l"])
        #expect(screen.hints.first { $0.keyName == "l" }?.label == "Next page")
        #expect(screen.hints.first { $0.keyName == "/" }?.bytes == Array("/".utf8))
    }

    // The disk analyzer (cmd/analyze): marker after one space, Go-style hints.
    @Test func testAnalyzerList() {
        let screen = ScreenModel(texts: [
            "Analyze Disk  ~/",
            "",
            " ▶ 1. Library        42.1 GB",
            "   2. Projects       30.0 GB",
            "   3. Downloads       8.2 GB",
            "",
            "↑↓←→ | Enter | R Refresh | O Open | P Preview | F File | Esc Back | Q/Ctrl+C Quit",
        ])
        #expect(screen.markerRow == 2)
        #expect(screen.listRows == 2...4)
        #expect(screen.hints.map(\.keyName) == ["↑", "↓", "←", "→", "Enter", "R", "O", "P", "F", "Esc", "Q"])
        #expect(screen.hints.last?.label == "Quit")
    }

    // Clean's output uses ➤ for section headers; with several on screen and no hints,
    // nothing is a menu, so clicks fall through to text selection.
    @Test func testCleanOutputIsNotAMenu() {
        let screen = ScreenModel(texts: [
            "➤ User essentials",
            "  ✓ User app cache · 18 items, 2.4GB",
            "➤ Browsers",
            "  ✓ Safari cache · 24 items, 642.1MB",
        ])
        #expect(screen.markerRow == nil)
        #expect(!screen.isMenu)
        #expect(screen.hints.isEmpty)
    }

    @Test func testOneSectionHeaderWithoutHintsIsNotAMenu() {
        let screen = ScreenModel(texts: ["➤ User essentials", "  ✓ Trash · emptied, 9 items"])
        #expect(screen.markerRow == 0)
        #expect(!screen.isMenu)
    }

    @Test func testFilterHintsKeepTheirKeysAndSkipProse() {
        let screen = ScreenModel(texts: ["Type to filter  |  Enter Apply  |  Esc Clear  |  Ctrl+C Quit"])
        #expect(screen.hints.map(\.keyName) == ["Enter", "Esc", "⌃C"])
        #expect(screen.hints.last?.bytes == [0x03])
    }

    @Test func testWrappedHintLineContinues() {
        let screen = ScreenModel(texts: [
            "↑↓ | Space Select | Enter Save | Q Cancel",
            "/ Search",
            "/ is not a key here",
        ])
        #expect(screen.hintRows == [0, 1])
        #expect(screen.hints.last?.keyName == "/")
    }

    @Test func testWideGlyphsShiftColumns() {
        // "✓" drawn two cells wide: everything after it sits one column later.
        let text = "↑↓ | ✓ Done | Q Quit"
        let row = ScreenRow(text: text, cellWidths: Array(repeating: 1, count: 5) + [2, 0] + Array(repeating: 1, count: 14))
        let screen = ScreenModel(rows: [row])
        let quit = screen.hints.first { $0.keyName == "Q" }
        #expect(quit?.columns.lowerBound == 15)
        #expect(screen.hints.map(\.keyName) == ["↑", "↓", "Q"])
    }
}
