# Pawsweep

A free Mac app for [Mole](https://github.com/tw93/Mole), the open-source command-line Mac cleaner.
Pawsweep runs Mole itself, in a window, and lets you drive it with the mouse. Every screen looks
and behaves exactly as `mo` does in Terminal, because it *is* `mo`.

> Pawsweep is a community project. It is not affiliated with or endorsed by the Mole project, and it
> is not [Mole for Mac](https://mole.fit). "Mole" is the Mole project's trademark (see
> [TRADEMARK.md](../TRADEMARK.md)).

## Install

1. Download `Pawsweep-<version>.zip` from [Releases](https://github.com/NezarAli/Pawsweep/releases).
2. Unzip it and move **Pawsweep** to your Applications folder.
3. Open it. The first time, macOS blocks it, because Pawsweep is not signed with a paid Apple
   Developer ID. Open **System Settings → Privacy & Security**, scroll down to the message about
   Pawsweep, and click **Open Anyway**. (Or, in Terminal: `xattr -dr com.apple.quarantine /Applications/Pawsweep.app`.)
4. Optional: give Pawsweep **Full Disk Access** (System Settings → Privacy & Security → Full Disk
   Access), so Mole can reach everything it reaches from a Terminal that has it.

Needs macOS 13 Ventura or newer, on Apple silicon or Intel. Nothing else to install: Mole comes
inside the app.

## Using it

The sidebar lists Mole's commands: Home (Mole's main menu), Clean, Uninstall, Optimize, Analyze,
Status, Purge, Installers, Slim, History, and the settings screens (protected caches, protected
maintenance, project folders, Touch ID for sudo, help). Click one to run it.

In the terminal, the mouse presses keys for you:

| You do | Pawsweep presses |
|---|---|
| Click a row in a list | ↑ or ↓ until the selection arrow (➤ or ▶) is on that row |
| Click a checkbox row (● / ○) | the arrows, then Space, so the box toggles |
| Double-click a plain row (main menu, disk analyzer) | the arrows, then Enter |
| Scroll over a list | ↑ / ↓ |
| Click a key hint on screen, such as `Space Select` or `Q Quit` | that key |
| Click a button in the bar under the terminal | that key (the bar shows the current screen's hints) |
| Click anywhere else | nothing: you select text, as in Terminal |

The keyboard works as it does in Terminal. Also:

- **Dry Run** (the eye in the toolbar, ⇧⌘D) adds `--dry-run` to Clean, Uninstall, Optimize, Purge,
  Installers and Slim, so they show what they would remove and change nothing.
- **Ctrl+C** (bottom right, ⌘.) interrupts the running command, as Ctrl+C does in Terminal.
- **Run Again** (⌘R) reruns the current command. ⌘0 to ⌘5 open Home and the five main commands.
- Switching commands while one is working asks first, then stops it the way Ctrl+C would.
- Password and Touch ID prompts for administrator steps appear in the terminal, as in Terminal.

## Safety

Pawsweep changes nothing about what Mole does; it only presses keys. Mole's own rules apply:
Clean, Purge and Installers delete permanently, while Uninstall, Analyze and Slim move files to the
Trash after you confirm. Use Dry Run first. Mole records what it removed in
`~/Library/Logs/mole/operations.log` (see History).

## Updates

The Mole inside Pawsweep is the version this fork had when the release was built. `mo update` and
`mo remove` are disabled inside the app (they would rewrite the app itself) and point here instead.
New Pawsweep releases bring new Mole versions.

## How it works

- `Sources/PawsweepCore/ScreenModel.swift` reads the visible text: the row marked with ➤ or ▶, and
  the gray hint line (`↑↓ | Space Select | Enter Confirm | Q Quit`).
- `Sources/Pawsweep/MoleTerminalView.swift` turns a click into key presses. Mole's menus read one key
  at a time and some drop keys that arrive while they redraw, so it presses one arrow, waits for the
  redraw, and checks where the arrow landed before pressing the next.
- The terminal is [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (MIT).
- The app bundle holds Mole's `mole`, `mo`, `bin/` and `lib/`, plus the `analyze` and `status` Go
  tools built from `cmd/`. The bundled copy differs from the repository's in one way:
  `patches/bundled-mole.patch` disables self-update and self-removal and names the install "Pawsweep app".

## Build from source

You need Swift 6.2 or newer (Xcode 26, or its Command Line Tools) and Go (the version in `../go.mod`).

```bash
mac/scripts/build-app.sh                       # mac/build/Pawsweep.app and mac/dist/Pawsweep-<version>.zip
PAWSWEEP_ARCHS=arm64 mac/scripts/build-app.sh   # one architecture, faster
swift test --package-path mac                  # the screen-reading tests
```

With only the Command Line Tools (no Xcode), `swift test` needs to be told where Swift Testing is:

```bash
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
swift test --package-path mac -Xswiftc -F -Xswiftc $F -Xlinker -F -Xlinker $F -Xlinker -rpath -Xlinker $F
```

To run the app against another copy of Mole (a checkout, or a test copy), set `PAWSWEEP_MOLE_DIR`
or pass `-PawsweepMoleDir <folder>` when launching it.

SwiftTerm is pinned to 1.99.1: later versions do not compile with Swift 6.2.

## Releasing

1. Change `mac/VERSION`, commit, and push.
2. Tag the commit `pawsweep-v<version>` and push the tag.

The [Pawsweep workflow](../.github/workflows/pawsweep.yml) builds the universal app and publishes the
release. GitHub Actions must be turned on for the fork (its Actions tab).

## Keeping up with Mole

Everything Pawsweep adds lives in `mac/`, `.github/workflows/pawsweep.yml` and a note at the top of
the repository's README, so GitHub's **Sync fork** brings in new Mole versions with few conflicts.

## License

GPL-3.0, like Mole ([LICENSE](../LICENSE)).
