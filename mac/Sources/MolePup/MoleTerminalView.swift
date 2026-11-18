// The terminal Mole runs in, plus the mouse.
//
// Mole only reads keys, so a click becomes the keys a person would press:
// - a click on a key hint ("Space Select", "Q Quit") presses that key;
// - a click on a list row presses ↑ or ↓ until the selection arrow is on that row,
//   watching the screen after each press, then toggles a checkbox row with Space;
// - a double-click on a plain row (the main menu) presses Enter;
// - the scroll wheel over a list presses ↑ and ↓.
// Anywhere else a click selects text as in Terminal.

import AppKit
import MolePupCore
import os
import SwiftTerm

/// `log stream --level debug --predicate 'subsystem == "io.github.nezarali.molepup"'`
let mouseLog = Logger(subsystem: "io.github.nezarali.molepup", category: "mouse")

final class MoleTerminalView: LocalProcessTerminalView {
    /// Called when the visible text changes.
    var onScreenChange: ((ScreenModel) -> Void)?

    private var watchTimer: Timer?
    private var lastTexts: [String] = []
    private var actionTail: Task<Void, Never>?
    private var pendingActions = 0
    private var pressIsOurs = false
    private var lastPressKey = ""
    private var lastPressWasOurs = false
    private var scrollAccumulator: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        nativeBackgroundColor = NSColor(srgbRed: 0.106, green: 0.110, blue: 0.122, alpha: 1)
        nativeForegroundColor = NSColor(srgbRed: 0.894, green: 0.898, blue: 0.910, alpha: 1)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    var isRunning: Bool { process?.running == true }

    // MARK: - Reading the screen

    func readScreen() -> ScreenModel {
        let snapshot = terminalStateSnapshot()
        return ScreenModel(rows: snapshot.visibleRows.map { ScreenRow(text: $0.text, cellWidths: $0.cellWidths) })
    }

    private func visibleTexts() -> [String] {
        visibleRowsText(0..<terminalDimensions.rows)
    }

    func startWatching() {
        watchTimer?.invalidate()
        let timer = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkForChanges() }
        }
        RunLoop.main.add(timer, forMode: .common)
        watchTimer = timer
    }

    func stopWatching() {
        checkForChanges()
        watchTimer?.invalidate()
        watchTimer = nil
    }

    private func checkForChanges() {
        let texts = visibleTexts()
        guard texts != lastTexts else { return }
        lastTexts = texts
        onScreenChange?(readScreen())
    }

    // MARK: - Keys

    func press(_ bytes: [UInt8]) {
        enqueue { view in view.send(bytes) }
    }

    /// Runs one mouse action at a time, so a click never interleaves with the
    /// arrow presses of the click before it.
    private func enqueue(_ action: @escaping @MainActor (MoleTerminalView) async -> Void) {
        let previous = actionTail
        pendingActions += 1
        actionTail = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }
            await action(self)
            self.pendingActions -= 1
        }
    }

    /// Waits until the screen changes and then stays still for a moment (a whole
    /// redraw). Returns false when nothing changed before the timeout.
    private func waitForRedraw(from before: [String], timeout: TimeInterval) async -> Bool {
        let start = Date()
        var last = before
        var changedAt: Date?
        while Date().timeIntervalSince(start) < timeout {
            try? await Task.sleep(nanoseconds: 12_000_000)
            let now = visibleTexts()
            if now != last {
                last = now
                changedAt = Date()
            } else if let changedAt, Date().timeIntervalSince(changedAt) >= 0.05 {
                return true
            }
        }
        return changedAt != nil
    }

    /// Presses ↑ or ↓ until the selection arrow is on `target`. Stops when the
    /// list stops moving, or moves past the row (a row inside a multi-line item).
    private func moveSelection(toRow target: Int) async -> Bool {
        var stalls = 0
        for _ in 0..<150 {
            var screen = readScreen()
            if screen.markerRow == nil {
                // Caught mid-redraw: give it a moment once.
                _ = await waitForRedraw(from: screen.rows.map(\.text), timeout: 0.15)
                screen = readScreen()
            }
            guard screen.isMenu, let marker = screen.markerRow else { return false }
            if marker == target { return true }

            send(marker < target ? Keys.down : Keys.up)
            if !(await waitForRedraw(from: screen.rows.map(\.text), timeout: 0.6)) {
                // Some menus drop keys that arrive while they redraw; try once more.
                stalls += 1
                if stalls > 1 { return false }
                continue
            }
            guard let moved = readScreen().markerRow else { continue }
            if moved == target { return true }
            let passed = (moved - target).signum() != (marker - target).signum()
            if passed || abs(moved - target) >= abs(marker - target) { return false }
        }
        return false
    }

    // MARK: - Mouse

    /// The terminal cell under the pointer, measured the way SwiftTerm draws it.
    private func cell(for event: NSEvent) -> (row: Int, column: Int)? {
        let dimensions = terminalDimensions
        guard dimensions.rows > 0, dimensions.cols > 0 else { return nil }
        let optimal = getOptimalFrameSize()
        var scrollerWidth: CGFloat = 0
        if let scroller = subviews.compactMap({ $0 as? NSScroller }).first,
           !scroller.isHidden, scroller.scrollerStyle == .legacy {
            scrollerWidth = NSScroller.scrollerWidth(for: scroller.controlSize, scrollerStyle: .legacy)
        }
        let cellWidth = (optimal.width - scrollerWidth) / CGFloat(dimensions.cols)
        let cellHeight = optimal.height / CGFloat(dimensions.rows)
        guard cellWidth > 0, cellHeight > 0 else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        let column = Int(point.x / cellWidth)
        let row = Int((frame.height - point.y) / cellHeight)
        guard row >= 0, row < dimensions.rows, column >= 0, column < dimensions.cols else { return nil }
        return (row, column)
    }

    override func mouseDown(with event: NSEvent) {
        // The same press can arrive twice (seen with synthesized clicks); acting on
        // it twice would press Space twice and leave a checkbox as it was.
        // Synthesized events may all carry the same timestamp, so a duplicate must
        // also match the click count and position.
        let pressKey = "\(event.timestamp)|\(event.clickCount)|\(event.locationInWindow)"
        if pressKey == lastPressKey {
            pressIsOurs = lastPressWasOurs
            return
        }
        lastPressKey = pressKey
        pressIsOurs = false
        defer { lastPressWasOurs = pressIsOurs }
        guard isRunning, !event.modifierFlags.contains(.option), let cell = cell(for: event) else {
            return super.mouseDown(with: event)
        }
        let screen = readScreen()

        if let hint = screen.hint(atRow: cell.row, column: cell.column) {
            pressIsOurs = true
            window?.makeFirstResponder(self)
            press(hint.bytes)
            return
        }

        if screen.isMenu, screen.isListRow(cell.row) {
            pressIsOurs = true
            window?.makeFirstResponder(self)
            let isCheckbox = screen.isCheckboxRow(cell.row)
            let clicks = event.clickCount
            let target = cell.row
            mouseLog.debug("click row \(target) clicks \(clicks) checkbox \(isCheckbox) marker \(screen.markerRow ?? -1) at \(event.timestamp)")
            enqueue { view in
                let reached = await view.moveSelection(toRow: target)
                mouseLog.debug("moved to row \(target): \(reached)")
                guard reached else { return }
                // Some synthesized clicks (accessibility tools) report a click count of 0.
                if isCheckbox, clicks <= 1 {
                    view.send(Keys.space)
                } else if !isCheckbox, clicks == 2 {
                    view.send(Keys.enter)
                }
            }
            return
        }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if !pressIsOurs { super.mouseDragged(with: event) }
    }

    override func mouseUp(with event: NSEvent) {
        if pressIsOurs {
            pressIsOurs = false
        } else {
            super.mouseUp(with: event)
        }
    }

    /// Over a list, the wheel moves the selection; elsewhere it scrolls as usual.
    /// (SwiftTerm's scrollWheel cannot be overridden, so the container's event
    /// monitor calls this first.)
    func handleScroll(_ event: NSEvent) -> Bool {
        guard isRunning else { return false }
        let screen = readScreen()
        guard screen.isMenu else {
            scrollAccumulator = 0
            return false
        }
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 18
        scrollAccumulator += delta
        let step: CGFloat = 18
        while abs(scrollAccumulator) >= step {
            let key = scrollAccumulator > 0 ? Keys.up : Keys.down
            scrollAccumulator += scrollAccumulator > 0 ? -step : step
            guard pendingActions < 3 else { continue }
            enqueue { view in
                let before = view.visibleTexts()
                view.send(key)
                _ = await view.waitForRedraw(from: before, timeout: 0.3)
            }
        }
        return true
    }
}

/// Holds the current terminal, starts its process once it has a real size
/// (Mole lays out for the size it starts with), and routes the scroll wheel.
final class TerminalContainerView: NSView {
    private(set) var terminal: MoleTerminalView?
    private var pendingLaunch: ((MoleTerminalView) -> Void)?
    private var scrollMonitor: Any?

    func show(_ terminal: MoleTerminalView, launch: @escaping (MoleTerminalView) -> Void) {
        self.terminal?.removeFromSuperview()
        self.terminal = terminal
        terminal.frame = bounds
        terminal.autoresizingMask = [.width, .height]
        addSubview(terminal)
        pendingLaunch = launch
        launchIfReady()
    }

    override func layout() {
        super.layout()
        terminal?.frame = bounds
        launchIfReady()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
        if window != nil {
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let terminal = self.terminal, event.window === self.window else { return event }
                let point = terminal.convert(event.locationInWindow, from: nil)
                guard terminal.bounds.contains(point) else { return event }
                return terminal.handleScroll(event) ? nil : event
            }
        }
        launchIfReady()
    }

    func focusTerminal() {
        guard let terminal else { return }
        window?.makeFirstResponder(terminal)
    }

    private func launchIfReady() {
        guard let terminal, let launch = pendingLaunch, window != nil,
              bounds.width > 200, bounds.height > 120 else { return }
        pendingLaunch = nil
        DispatchQueue.main.async { [weak self] in
            launch(terminal)
            self?.focusTerminal()
        }
    }
}
