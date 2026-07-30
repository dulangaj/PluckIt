#!/bin/bash
# Builds PluckIt.app and signs it ad hoc — no Apple Developer account required.
#
#   scripts/build.sh              build into ./build/PluckIt.app
#   scripts/build.sh --install    build, then copy into /Applications
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA="${DERIVED_DATA:-.derived}"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
install=false

for arg in "$@"; do
    case "$arg" in
        --install) install=true ;;
        *) echo "usage: $0 [--install]" >&2; exit 64 ;;
    esac
done

if ! xcodebuild -version >/dev/null 2>&1; then
    echo "xcodebuild is unavailable. Install Xcode from the App Store, then run:" >&2
    echo "  sudo xcode-select --switch /Applications/Xcode.app" >&2
    exit 1
fi

xcodebuild \
    -project PluckIt.xcodeproj \
    -target PluckIt \
    -configuration "$CONFIGURATION" \
    SYMROOT="$PWD/$DERIVED_DATA" \
    OBJROOT="$PWD/$DERIVED_DATA/Intermediates" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM="" \
    build

built="$DERIVED_DATA/$CONFIGURATION/PluckIt.app"
rm -rf build/PluckIt.app
mkdir -p build
cp -R "$built" build/

if $install; then
    rm -rf "$INSTALL_DIR/PluckIt.app"
    cp -R build/PluckIt.app "$INSTALL_DIR/"
    echo "Installed $INSTALL_DIR/PluckIt.app"
else
    echo "Built build/PluckIt.app — drag it to /Applications, or rerun with --install."
fi
