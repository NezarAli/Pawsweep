// Pawsweep: a minimal Mac interface for Mole (https://github.com/tw93/Mole).
// It runs Mole itself, unchanged, and adds the mouse. Not affiliated with Mole.

import AppKit
import SwiftUI

@main
struct PawsweepApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var session = Session()

    var body: some Scene {
        Window("Pawsweep", id: "main") {
            ContentView(session: session)
                .frame(minWidth: 860, minHeight: 540)
                .onAppear { appDelegate.session = session }
        }
        .defaultSize(width: 1120, height: 740)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Pawsweep") { AppDelegate.showAbout(moleVersion: session.mole?.version) }
            }
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Mole") {
                ForEach(Array(MoleCommand.all.filter { $0.group == .main }.enumerated()), id: \.element.id) { index, command in
                    Button(command.title) { session.select(command.id) }
                        .keyboardShortcut(KeyEquivalent(Character(String(index))), modifiers: .command)
                }
                Divider()
                Button("Run Again") { session.runAgain() }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Interrupt (Ctrl+C)") { session.interrupt() }
                    .keyboardShortcut(".", modifiers: .command)
                Divider()
                Toggle("Dry Run", isOn: $session.dryRun)
                    .keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var session: Session?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // `swift run` starts a bare executable; give it a Dock icon and a menu bar.
        if Bundle.main.bundleIdentifier == nil {
            NSApp.setActivationPolicy(.regular)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    @MainActor
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let session else { return .terminateNow }
        if session.isBusy {
            let alert = NSAlert()
            alert.messageText = "Quit while \(session.current.title) is working?"
            alert.informativeText = "Pawsweep will stop it the way Ctrl+C does in Terminal."
            alert.addButton(withTitle: "Quit")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        }
        session.shutdown()
        return .terminateNow
    }

    static func showAbout(moleVersion: String?) {
        let credits = """
        Pawsweep is a minimal Mac interface for Mole, the open-source command-line Mac cleaner by tw93 and its contributors (github.com/tw93/Mole). It runs Mole \(moleVersion ?? "") unchanged and lets you use it with the mouse.

        Pawsweep is an unofficial community project. It is not affiliated with or endorsed by the Mole project, and "Mole" is the Mole project's trademark.

        License: GPL-3.0. Source: github.com/NezarAli/Pawsweep (the mac folder). The terminal is SwiftTerm by Miguel de Icaza (MIT).
        """
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let text = NSAttributedString(string: credits, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: style,
        ])
        NSApp.orderFrontStandardAboutPanel(options: [.credits: text])
        NSApp.activate(ignoringOtherApps: true)
    }
}
