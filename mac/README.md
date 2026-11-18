# Pawsweep: how it works

This folder is [Pawsweep](../.github/README.md), a minimal Mac interface for
[Mole](https://github.com/tw93/Mole). This page is for working on it: how it works, how to build it,
and how releases and Mole updates happen. To use it, see the [main page](../.github/README.md).

## How it works

Pawsweep runs Mole itself in a terminal inside the window and turns mouse actions into key presses.
It never reimplements a Mole screen, so it keeps working as Mole changes.

| You do | Pawsweep presses |
|---|---|
| Click a row in a list | ↑ or ↓ until the selection arrow (➤ or ▶) is on that row |
| Click a checkbox row (● / ○) | the arrows, then Space, so the box toggles |
| Double-click a plain row (main menu, disk analyzer) | the arrows, then Enter |
| Scroll over a list | ↑ / ↓ |
| Click a key hint on screen, such as `Space Select` or `Q Quit` | that key |
| Click a button in the bar under the terminal | that key (the bar shows the current screen's hints) |
| Click anywhere else | nothing: you select text, as in Terminal |

Also: **Dry Run** (⇧⌘D) adds `--dry-run` to Clean, Uninstall, Optimize, Purge, Installers and Slim;
**Ctrl+C** (⌘.) interrupts; **Run Again** (⌘R) reruns; ⌘0 to ⌘5 open Home and the five main commands.

- `Sources/PawsweepCore/ScreenModel.swift` reads the visible text: the row marked with ➤ or ▶, and
  the gray hint line (`↑↓ | Space Select | Enter Confirm | Q Quit`).
- `Sources/Pawsweep/MoleTerminalView.swift` turns a click into key presses. Mole's menus read one key
  at a time and some drop keys that arrive while they redraw, so it presses one arrow, waits for the
  redraw, and checks where the arrow landed before pressing the next.
- `Sources/Pawsweep/Session.swift` runs one Mole command at a time and stops it the way Ctrl+C does.
- The terminal is [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (MIT), pinned to 1.99.1:
  later versions do not compile with Swift 6.2.
- The app bundle holds Mole's `mole`, `mo`, `bin/` and `lib/`, plus the `analyze` and `status` Go
  tools built from `cmd/`. The bundled copy differs from the repository's in one way:
  `patches/bundled-mole.patch` disables `mo update` and `mo remove` (they would rewrite the app) and
  names the install "Pawsweep app".

## Build from source

You need Swift 6.2 or newer (Xcode 26, or its Command Line Tools) and Go (the version in `../go.mod`).

```bash
mac/scripts/build-app.sh                        # mac/build/Pawsweep.app and mac/dist/Pawsweep-<version>.zip
PAWSWEEP_ARCHS=arm64 mac/scripts/build-app.sh   # one architecture, faster
swift test --package-path mac                   # the screen-reading tests
```

With only the Command Line Tools (no Xcode), `swift test` needs to be told where Swift Testing is:

```bash
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
swift test --package-path mac -Xswiftc -F -Xswiftc $F -Xlinker -F -Xlinker $F -Xlinker -rpath -Xlinker $F
```

To run the app against another copy of Mole (a checkout, or a test copy whose commands are stubbed
out), set `PAWSWEEP_MOLE_DIR` or pass `-PawsweepMoleDir <folder>` when launching it.

## Releases

The [Pawsweep workflow](../.github/workflows/pawsweep.yml) tests and builds the universal app on
every change to `mac/`. On `main`, when `mac/VERSION` names a version that has no release yet, it
publishes one (tag `pawsweep-v<version>`). So releasing is: change `mac/VERSION`, commit, push.

## Mole updates

Once a day the same workflow looks for a new Mole release (`V*` tags of tw93/Mole; never Mole's
unreleased main branch). When there is one, `scripts/mole-release.sh merge` merges it and bumps
`mac/VERSION` one patch version, then the workflow tests and builds the app, and only if all of that
passes does it push to `main` and publish the release. If anything fails (a conflict, a failing
test, a patch that no longer applies), `main` is left as it was and GitHub emails you about the
failed run. Fix it by hand and push; the next day's run carries on.

Pawsweep's own files never conflict with Mole's: they are `mac/`, `.github/README.md` (which GitHub
shows instead of Mole's README) and `.github/workflows/pawsweep.yml`.

**One-time setup.** Mole's releases often change Mole's own workflow files, and the token GitHub
gives workflows is not allowed to push those. So the workflow pushes with a token of yours, stored
as the `SYNC_TOKEN` secret:

1. Create a fine-grained token with
   [this pre-filled form](https://github.com/settings/personal-access-tokens/new?name=Pawsweep+sync&description=Lets+the+Pawsweep+workflow+push+Mole+releases+to+main&target_name=NezarAli&expires_in=none&contents=write&workflows=write)
   (Contents and Workflows: read and write). Under **Repository access**, choose **Only select
   repositories** and pick this repository. Then **Generate token** and copy it.
2. In this repository: **Settings → Secrets and variables → Actions → New repository secret**,
   name `SYNC_TOKEN`, paste the token.

Without it, updates that don't touch workflow files still go through, and the others fail with a
message pointing here. If you give the token an expiry date, renew it before then.

Forks start with scheduled workflows turned off. If the daily run doesn't appear under the
repository's **Actions** tab, open the Pawsweep workflow there and enable it. GitHub also turns off
schedules in repositories with no activity for 60 days; Mole releases usually keep it busy.

## License

GPL-3.0, like Mole ([LICENSE](../LICENSE)).
