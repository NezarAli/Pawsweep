#!/bin/bash
# Builds MolePup.app and a zip of it from this checkout:
#   mac/build/MolePup.app
#   mac/dist/MolePup-<version>.zip
#
# Needs Swift 6.2 or newer (Xcode 26, or its Command Line Tools) and Go
# (the version in ../go.mod). MOLEPUP_ARCHS="arm64" builds for one architecture
# only, which is faster while developing; the default is a universal app.

set -euo pipefail

MAC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "$MAC_DIR/.." && pwd)"
APP_NAME="MolePup"
APP_VERSION="$(tr -d '[:space:]' < "$MAC_DIR/VERSION")"
MOLE_VERSION="$(sed -n 's/^VERSION="\(.*\)"$/\1/p' "$REPO_DIR/mole" | head -1)"
BUILD_NUMBER="$(git -C "$REPO_DIR" rev-list --count HEAD 2> /dev/null || echo 1)"
BUILD_DIR="$MAC_DIR/build"
DIST_DIR="$MAC_DIR/dist"
APP="$BUILD_DIR/$APP_NAME.app"
read -r -a ARCHS <<< "${MOLEPUP_ARCHS:-arm64 x86_64}"

log() { printf '\n==> %s\n' "$*"; }

for tool in swift go lipo iconutil codesign ditto patch; do
    command -v "$tool" > /dev/null || {
        echo "Missing $tool. See mac/README.md, Build from source." >&2
        exit 1
    }
done

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/go" "$DIST_DIR"

log "Mole's Go tools (analyze, status) for ${ARCHS[*]}"
for tool in analyze status; do
    slices=()
    for arch in "${ARCHS[@]}"; do
        goarch="$arch"
        [[ "$arch" == "x86_64" ]] && goarch="amd64"
        (cd "$REPO_DIR" && CGO_ENABLED=0 GOOS=darwin GOARCH="$goarch" \
            go build -trimpath -ldflags="-s -w" -o "$BUILD_DIR/go/$tool-$arch" "./cmd/$tool")
        slices+=("$BUILD_DIR/go/$tool-$arch")
    done
    lipo -create -output "$BUILD_DIR/go/$tool-go" "${slices[@]}"
done

log "$APP_NAME $APP_VERSION for ${ARCHS[*]}"
slices=()
for arch in "${ARCHS[@]}"; do
    triple="$arch-apple-macosx13.0"
    swift build --package-path "$MAC_DIR" -c release --triple "$triple"
    bin_path="$(swift build --package-path "$MAC_DIR" -c release --triple "$triple" --show-bin-path)"
    slices+=("$bin_path/$APP_NAME")
done

log "Assembling $APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/mole/bin" "$APP/Contents/Resources/Licenses"
lipo -create -output "$APP/Contents/MacOS/$APP_NAME" "${slices[@]}"
sed -e "s/@APP_VERSION@/$APP_VERSION/g" \
    -e "s/@BUILD_NUMBER@/$BUILD_NUMBER/g" \
    -e "s/@MOLE_VERSION@/$MOLE_VERSION/g" \
    "$MAC_DIR/Resources/Info.plist" > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" > /dev/null

# Mole itself: the files its installer copies (install.sh), plus the Go tools.
MOLE_OUT="$APP/Contents/Resources/mole"
cp "$REPO_DIR/mole" "$REPO_DIR/mo" "$MOLE_OUT/"
cp "$REPO_DIR"/bin/*.sh "$MOLE_OUT/bin/"
cp "$BUILD_DIR/go/analyze-go" "$BUILD_DIR/go/status-go" "$MOLE_OUT/bin/"
cp -R "$REPO_DIR/lib" "$MOLE_OUT/lib"
chmod +x "$MOLE_OUT/mole" "$MOLE_OUT/mo" "$MOLE_OUT"/bin/*
# The bundled copy's one difference: `mo update` and `mo remove` point to the app.
patch --quiet --forward -p1 -d "$MOLE_OUT" < "$MAC_DIR/patches/bundled-mole.patch"
find "$MOLE_OUT" -name '*.orig' -delete

cp "$REPO_DIR/LICENSE" "$APP/Contents/Resources/Licenses/GPL-3.0.txt"
cp "$MAC_DIR/.build/checkouts/SwiftTerm/LICENSE" "$APP/Contents/Resources/Licenses/SwiftTerm-MIT.txt"

swift "$MAC_DIR/scripts/make-icon.swift" "$BUILD_DIR/AppIcon.iconset"
iconutil -c icns -o "$APP/Contents/Resources/AppIcon.icns" "$BUILD_DIR/AppIcon.iconset"

log "Signing (ad hoc: MolePup has no Apple Developer ID)"
codesign --force --sign - "$MOLE_OUT/bin/analyze-go" "$MOLE_OUT/bin/status-go"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"

ZIP="$DIST_DIR/$APP_NAME-$APP_VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
log "Done: $APP
    $ZIP (Mole $MOLE_VERSION)"
