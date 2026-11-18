// Runs one Mole command at a time in the terminal, and tracks what it shows.

import AppKit
import PawsweepCore
import SwiftTerm

@MainActor
final class Session: NSObject, ObservableObject, LocalProcessTerminalViewDelegate {
    enum RunState: Equatable {
        case starting
        case running
        case finished(Int32?)
    }

    /// The sidebar's selection. Changing it runs that command (see `select`).
    @Published var selection: MoleCommand.ID? = MoleCommand.home.id
    @Published private(set) var current: MoleCommand = .home
    @Published private(set) var state: RunState = .starting
    @Published var dryRun = false
    /// What the bar and the busy check need from the screen. Published only when
    /// they change: a live screen such as Status redraws many times a second.
    @Published private(set) var hints: [HintKey] = []
    @Published private(set) var screenIsMenu = false
    /// Set to ask before stopping a running command for another one.
    @Published var confirmSwitch: MoleCommand?

    let container = TerminalContainerView()
    let mole = MoleInstallation.find()
    private var terminal: MoleTerminalView?
    private var environment: [String]?
    private var nextCommand: MoleCommand?
    private var started = false

    /// Keys for the bar under the terminal: the screen's own hints, else a few common ones.
    var barKeys: [HintKey] {
        var seen = Set<String>()
        let keys = hints.isEmpty ? current.fallbackKeys : hints
        return keys.filter { seen.insert($0.keyName + "|" + $0.label).inserted }
    }

    /// Switching away needs a yes when a command is busy (not sitting in a menu).
    var isBusy: Bool {
        state == .running && !screenIsMenu && !current.isReadOnly
    }

    func start() {
        guard !started else { return }
        started = true
        Task {
            environment = await ShellEnvironment.load()
            launch(current)
        }
    }

    // MARK: - Choosing commands

    /// The sidebar picked a command.
    func select(_ id: MoleCommand.ID?) {
        guard let command = MoleCommand.find(id) else { return }
        // Already on its way (run() moves the selection before the old command ends).
        if command == nextCommand { return }
        if command == current, !isFinished { return }
        if isBusy, command != current {
            confirmSwitch = command
            selection = current.id
            return
        }
        run(command)
    }

    var isFinished: Bool {
        if case .finished = state { return true }
        return false
    }

    func run(_ command: MoleCommand) {
        if let terminal, terminal.isRunning {
            nextCommand = command
            selection = command.id
            stop(terminal)
        } else {
            launch(command)
        }
    }

    func runAgain() { run(current) }

    func confirmPendingSwitch() {
        guard let command = confirmSwitch else { return }
        confirmSwitch = nil
        run(command)
    }

    /// Like pressing Ctrl+C in Terminal.
    func interrupt() {
        terminal?.send(Keys.interrupt)
        container.focusTerminal()
    }

    func press(_ bytes: [UInt8]) {
        terminal?.press(bytes)
        container.focusTerminal()
    }

    /// Before the app quits.
    func shutdown() {
        if let terminal, terminal.isRunning { stop(terminal) }
    }

    // MARK: - Processes

    /// Ctrl+C first, as a person would; SIGTERM if Mole is still running after
    /// two seconds; SIGKILL after five.
    private func stop(_ terminal: MoleTerminalView) {
        terminal.send(Keys.interrupt)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak terminal] in
            guard let terminal, terminal.isRunning else { return }
            terminal.process.terminate()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak terminal] in
            guard let terminal, terminal.isRunning else { return }
            let pid = terminal.process.shellPid
            if pid > 0 { kill(pid, SIGKILL) }
        }
    }

    private func launch(_ command: MoleCommand) {
        terminal?.stopWatching()
        let view = MoleTerminalView(frame: container.bounds)
        view.processDelegate = self
        view.onScreenChange = { [weak self, weak view] model in
            guard let self, let view, view === self.terminal else { return }
            self.update(from: model)
        }
        terminal = view
        current = command
        selection = command.id
        state = .starting
        update(from: ScreenModel(texts: []))
        let dryRun = self.dryRun

        container.show(view) { [weak self] view in
            guard let self else { return }
            guard let mole = self.mole else {
                view.feed(text: "Pawsweep could not find its copy of Mole.\r\n"
                    + "Download Pawsweep again from https://github.com/NezarAli/Pawsweep/releases\r\n")
                self.state = .finished(1)
                return
            }
            view.startProcess(executable: "/bin/bash",
                              args: [mole.entry.path] + command.arguments(dryRun: dryRun),
                              environment: self.environment,
                              currentDirectory: NSHomeDirectory())
            view.startWatching()
            self.state = .running
        }
    }

    private func update(from model: ScreenModel) {
        if model.hints != hints { hints = model.hints }
        if model.isMenu != screenIsMenu { screenIsMenu = model.isMenu }
    }

    // MARK: - LocalProcessTerminalViewDelegate

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        guard source === terminal else { return }
        terminal?.stopWatching()
        if let next = nextCommand {
            nextCommand = nil
            launch(next)
        } else {
            state = .finished(exitCode)
        }
    }
}
