// Where the copy of Mole that Pawsweep runs lives, and the environment it runs in.

import Foundation

struct MoleInstallation {
    /// The `mole` entry script.
    let entry: URL
    let version: String?

    /// The app bundle's copy (Contents/Resources/mole). For development, the
    /// PAWSWEEP_MOLE_DIR environment variable or the `-PawsweepMoleDir <folder>`
    /// launch argument points at another copy, or `swift run` finds the
    /// repository that holds mac/.
    static func find() -> MoleInstallation? {
        var candidates: [URL] = []
        let override = ProcessInfo.processInfo.environment["PAWSWEEP_MOLE_DIR"]
            ?? UserDefaults.standard.string(forKey: "PawsweepMoleDir")
        if let dir = override, !dir.isEmpty {
            candidates.append(URL(fileURLWithPath: dir))
        }
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("mole"))
        }
        var directory = Bundle.main.executableURL?.deletingLastPathComponent()
        for _ in 0..<8 {
            guard let current = directory else { break }
            candidates.append(current)
            directory = current.deletingLastPathComponent()
        }
        for directory in candidates {
            let entry = directory.appendingPathComponent("mole")
            let common = directory.appendingPathComponent("lib/core/common.sh")
            if FileManager.default.isReadableFile(atPath: entry.path),
               FileManager.default.fileExists(atPath: common.path) {
                return MoleInstallation(entry: entry, version: readVersion(entry))
            }
        }
        return nil
    }

    /// The `VERSION="1.73.0"` line of the entry script.
    private static func readVersion(_ entry: URL) -> String? {
        guard let text = try? String(contentsOf: entry, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") where line.hasPrefix("VERSION=\"") {
            return line.dropFirst("VERSION=\"".count).split(separator: "\"").first.map(String.init)
        }
        return nil
    }
}

enum ShellEnvironment {
    /// The environment Mole runs in: the app's own, with the PATH a terminal would
    /// have (so Mole finds Homebrew, npm, Docker and the rest) and a 256-color terminal.
    static func load() async -> [String] {
        var environment = ProcessInfo.processInfo.environment
        let loginPath = await Task.detached(priority: .userInitiated) { loginShellPath() }.value
        environment["PATH"] = mergedPath(loginPath, environment["PATH"])
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        environment["TERM_PROGRAM"] = "Pawsweep"
        if (environment["LANG"] ?? "").isEmpty {
            environment["LANG"] = "en_US.UTF-8"
        }
        return environment.map { "\($0.key)=\($0.value)" }.sorted()
    }

    static func mergedPath(_ loginPath: String?, _ appPath: String?) -> String {
        var seen = Set<String>()
        var parts: [String] = []
        let standard = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin"
        for source in [loginPath, standard, appPath] {
            for part in (source ?? "").split(separator: ":").map(String.init) where !part.isEmpty {
                if seen.insert(part).inserted { parts.append(part) }
            }
        }
        return parts.joined(separator: ":")
    }

    /// Asks the user's login shell for its PATH, as Terminal would start it.
    /// Gives up after three seconds, for shells whose startup waits on something.
    static func loginShellPath() -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"].flatMap {
            FileManager.default.isExecutableFile(atPath: $0) ? $0 : nil
        } ?? "/bin/zsh"
        let marker = "__PAWSWEEP_PATH__"
        let printPath = (shell as NSString).lastPathComponent == "fish"
            ? "printf '\\n\(marker)%s\(marker)\\n' (string join : $PATH)"
            : "printf '\\n\(marker)%s\(marker)\\n' \"$PATH\""

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-i", "-c", printPath]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        let lock = NSLock()
        var data = Data()
        output.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            lock.lock(); data.append(chunk); lock.unlock()
        }
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { return nil }
        if finished.wait(timeout: .now() + 3) == .timedOut {
            process.terminate()
        }
        output.fileHandleForReading.readabilityHandler = nil

        lock.lock(); let text = String(decoding: data, as: UTF8.self); lock.unlock()
        guard let start = text.range(of: marker),
              let end = text.range(of: marker, range: start.upperBound..<text.endIndex) else { return nil }
        let path = String(text[start.upperBound..<end.lowerBound])
        return path.isEmpty ? nil : path
    }
}
