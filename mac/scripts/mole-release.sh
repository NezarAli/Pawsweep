#!/usr/bin/env bash
# Keeps Pawsweep on Mole's newest release.
#
#   mac/scripts/mole-release.sh check [upstream]   prints the newest Mole release tag (V1.74.0)
#                                                  if it is newer than the Mole in this checkout,
#                                                  and nothing otherwise
#   mac/scripts/mole-release.sh merge [upstream]   merges that release into the current branch and
#                                                  commits mac/VERSION one patch version up, so the
#                                                  next Pawsweep release carries it; prints the tag
#
# upstream defaults to https://github.com/tw93/Mole.git. Only release tags are merged (V<numbers>),
# never Mole's main branch, so Pawsweep ships the Mole that Mole itself released. A merge with
# conflicts is undone and exits 1: someone has to merge that release by hand.
set -euo pipefail

ACTION="${1:-}"
UPSTREAM="${2:-https://github.com/tw93/Mole.git}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

mole_version() { sed -n 's/^VERSION="\(.*\)"$/\1/p' mole | head -1; }

newer_release() {
    local current latest
    current="$(mole_version)"
    [[ -n "$current" ]] || { echo "No VERSION=\"...\" line in ./mole" >&2; exit 1; }
    latest="$(git ls-remote --tags --refs "$UPSTREAM" 'refs/tags/V*' |
        sed 's#.*refs/tags/##' | grep -E '^V[0-9]+(\.[0-9]+)*$' | sort -V | tail -1)"
    [[ -n "$latest" ]] || { echo "No Mole release tags at $UPSTREAM" >&2; exit 1; }
    # Newer only: sort -V puts the higher version last.
    if [[ "${latest#V}" != "$current" &&
        "$(printf '%s\n%s\n' "$current" "${latest#V}" | sort -V | tail -1)" == "${latest#V}" ]]; then
        echo "$latest"
    fi
}

case "$ACTION" in
    check)
        newer_release
        ;;
    merge)
        release="$(newer_release)"
        [[ -n "$release" ]] || exit 0
        git fetch --quiet --no-tags "$UPSTREAM" "refs/tags/$release"
        if ! git merge --quiet --no-edit -m "Merge Mole $release" FETCH_HEAD >&2; then
            git merge --abort
            echo "Mole $release does not merge cleanly. Merge it by hand: git fetch $UPSTREAM tag $release && git merge $release" >&2
            exit 1
        fi
        IFS=. read -r major minor patch < mac/VERSION
        next="$major.$minor.$((patch + 1))"
        printf '%s\n' "$next" > mac/VERSION
        # [skip ci]: the workflow that made this commit releases it itself.
        git commit --quiet -m "Pawsweep $next: Mole ${release#V}" -m "[skip ci]" -- mac/VERSION
        echo "$release"
        ;;
    *)
        echo "Usage: $0 check|merge [upstream]" >&2
        exit 2
        ;;
esac
