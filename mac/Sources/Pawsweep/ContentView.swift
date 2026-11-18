import AppKit
import PawsweepCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var session: Session

    var body: some View {
        NavigationSplitView {
            Sidebar(session: session)
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 280)
        } detail: {
            VStack(spacing: 0) {
                TerminalHost(container: session.container)
                    .background(Color(nsColor: NSColor(srgbRed: 0.106, green: 0.110, blue: 0.122, alpha: 1)))
                Divider()
                KeyBar(session: session)
            }
            .navigationTitle(session.current.title)
            .navigationSubtitle(subtitle)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Toggle(isOn: $session.dryRun) {
                        Label("Dry Run", systemImage: "eye")
                    }
                    .toggleStyle(.button)
                    .help("Preview only: Clean, Uninstall, Optimize, Purge, Installers and Slim run with --dry-run and change nothing")

                    Button {
                        session.runAgain()
                    } label: {
                        Label("Run Again", systemImage: "arrow.clockwise")
                    }
                    .help("Run \(session.current.commandLine) again")
                }
            }
        }
        .onChange(of: session.selection) { id in
            session.select(id)
        }
        .onAppear { session.start() }
        .alert(item: $session.confirmSwitch) { command in
            Alert(
                title: Text("Stop \(session.current.title)?"),
                message: Text("\(session.current.title) is still working. Pawsweep will stop it the way Ctrl+C does in Terminal, then open \(command.title)."),
                primaryButton: .destructive(Text("Stop and Open \(command.title)")) { session.confirmPendingSwitch() },
                secondaryButton: .cancel()
            )
        }
    }

    private var subtitle: String {
        var parts = [session.current.commandLine]
        if session.dryRun, session.current.supportsDryRun { parts.append("dry run") }
        return parts.joined(separator: " · ")
    }
}

struct Sidebar: View {
    @ObservedObject var session: Session

    var body: some View {
        List(selection: $session.selection) {
            ForEach(MoleCommand.Group.allCases, id: \.self) { group in
                Section(group.rawValue) {
                    ForEach(MoleCommand.all.filter { $0.group == group }) { command in
                        Label(command.title, systemImage: command.symbol)
                            .help("\(command.commandLine) — \(command.summary)")
                            .tag(command.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                if let version = session.mole?.version {
                    Text("Mole \(version)")
                }
                Text("Unofficial app, not affiliated with Mole")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }
}

/// The terminal's AppKit view inside SwiftUI.
struct TerminalHost: NSViewRepresentable {
    let container: TerminalContainerView

    func makeNSView(context: Context) -> TerminalContainerView { container }

    func updateNSView(_ nsView: TerminalContainerView, context: Context) {}
}

/// The keys the current screen offers, as buttons; or, once a command ends, what to do next.
struct KeyBar: View {
    @ObservedObject var session: Session

    var body: some View {
        HStack(spacing: 10) {
            if case .finished(let code) = session.state {
                finished(code)
            } else {
                keys
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 40)
        .background(.bar)
    }

    private var keys: some View {
        Group {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(session.barKeys) { key in
                        Button {
                            session.press(key.bytes)
                        } label: {
                            KeyLabel(key: key)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            Spacer(minLength: 8)
            Button {
                session.interrupt()
            } label: {
                Label("Ctrl+C", systemImage: "stop.circle")
            }
            .controlSize(.small)
            .help("Interrupt, like Ctrl+C in Terminal")
        }
    }

    private func finished(_ code: Int32?) -> some View {
        Group {
            let succeeded = code == nil || code == 0
            Image(systemName: succeeded ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(succeeded ? .green : .orange)
            Text(succeeded ? "\(session.current.title) finished" : "\(session.current.title) stopped (exit code \(code ?? 0))")
            Spacer()
            if session.current != .home {
                Button("Home") { session.run(.home) }
            }
            Button("Run Again") { session.runAgain() }
                .keyboardShortcut(.defaultAction)
        }
    }
}

struct KeyLabel: View {
    let key: HintKey

    var body: some View {
        HStack(spacing: 5) {
            Text(key.keyName)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .fixedSize()
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.08)))
            if !key.label.isEmpty {
                Text(key.label).fixedSize()
            }
        }
    }
}
