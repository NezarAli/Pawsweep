// The Mole commands the sidebar offers: the same ones `mo --help` lists,
// minus `update`, `remove` and `completion`, which belong to a terminal install
// (Pawsweep updates by downloading a new release).

import Foundation
import PawsweepCore

struct MoleCommand: Identifiable, Hashable {
    enum Group: String, CaseIterable {
        case main = "Mole"
        case more = "More Tools"
        case settings = "Settings"
    }

    let id: String
    let title: String
    let summary: String
    let symbol: String
    let arguments: [String]
    let group: Group
    /// Takes `--dry-run`, so the toolbar's Dry Run switch applies.
    var supportsDryRun = false
    /// Only shows information, so switching away needs no confirmation.
    var isReadOnly = false

    /// What a terminal user would type.
    var commandLine: String { (["mo"] + arguments).joined(separator: " ") }

    func arguments(dryRun: Bool) -> [String] {
        dryRun && supportsDryRun ? arguments + ["--dry-run"] : arguments
    }

    /// Keys to show when the screen draws no hint line of its own.
    var fallbackKeys: [HintKey] {
        func key(_ name: String, _ label: String, _ bytes: [UInt8]) -> HintKey {
            HintKey(keyName: name, label: label, bytes: bytes, row: -1, columns: 0..<0)
        }
        if id == "status" {
            // cmd/status reads lowercase keys only.
            return [key("q", "Quit", Array("q".utf8)), key("k", "Cat", Array("k".utf8)), key("c", "CPU cores", Array("c".utf8))]
        }
        return [
            key("Enter", "", Keys.enter), key("Space", "", Keys.space), key("↑", "", Keys.up),
            key("↓", "", Keys.down), key("Esc", "", Keys.escape),
        ]
    }

    static let home = MoleCommand(id: "home", title: "Home", summary: "Mole's main menu", symbol: "house",
                                  arguments: [], group: .main)

    static let all: [MoleCommand] = [
        home,
        MoleCommand(id: "clean", title: "Clean", summary: "Free up disk space", symbol: "sparkles",
                    arguments: ["clean"], group: .main, supportsDryRun: true),
        MoleCommand(id: "uninstall", title: "Uninstall", summary: "Remove apps completely", symbol: "trash",
                    arguments: ["uninstall"], group: .main, supportsDryRun: true),
        MoleCommand(id: "optimize", title: "Optimize", summary: "Refresh caches and services", symbol: "bolt",
                    arguments: ["optimize"], group: .main, supportsDryRun: true),
        MoleCommand(id: "analyze", title: "Analyze", summary: "Explore disk usage", symbol: "chart.pie",
                    arguments: ["analyze"], group: .main),
        MoleCommand(id: "status", title: "Status", summary: "Monitor system health", symbol: "speedometer",
                    arguments: ["status"], group: .main, isReadOnly: true),

        MoleCommand(id: "purge", title: "Purge", summary: "Clean project build artifacts", symbol: "hammer",
                    arguments: ["purge"], group: .more, supportsDryRun: true),
        MoleCommand(id: "installer", title: "Installers", summary: "Find and remove installer files",
                    symbol: "shippingbox", arguments: ["installer"], group: .more, supportsDryRun: true),
        MoleCommand(id: "slim", title: "Slim", summary: "Remove Intel code from universal apps", symbol: "scissors",
                    arguments: ["slim"], group: .more, supportsDryRun: true),
        MoleCommand(id: "history", title: "History", summary: "Review past cleanup activity",
                    symbol: "clock.arrow.circlepath", arguments: ["history"], group: .more, isReadOnly: true),

        MoleCommand(id: "clean-whitelist", title: "Protected Caches", summary: "Caches Clean leaves alone",
                    symbol: "lock.shield", arguments: ["clean", "--whitelist"], group: .settings),
        MoleCommand(id: "optimize-whitelist", title: "Protected Maintenance",
                    summary: "Optimize items to skip", symbol: "checklist",
                    arguments: ["optimize", "--whitelist"], group: .settings),
        MoleCommand(id: "purge-paths", title: "Project Folders", summary: "Where Purge looks for projects",
                    symbol: "folder.badge.gearshape", arguments: ["purge", "--paths"], group: .settings),
        MoleCommand(id: "touchid", title: "Touch ID for sudo", summary: "Approve admin steps with Touch ID",
                    symbol: "touchid", arguments: ["touchid"], group: .settings),
        MoleCommand(id: "help", title: "Help", summary: "Every command and option", symbol: "questionmark.circle",
                    arguments: ["--help"], group: .settings, isReadOnly: true),
    ]

    static func find(_ id: MoleCommand.ID?) -> MoleCommand? {
        all.first { $0.id == id }
    }
}
