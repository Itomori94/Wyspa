#!/usr/bin/env bash
# Buduje build/Wyspa.app (universal: arm64 + x86_64) i podpisuje go.
#
# Podpis: certyfikat „Wyspa Development” z scripts/dev-cert.sh (stały, zgody TCC przetrwają rebuild),
# a gdy go brak — podpis ad-hoc z ostrzeżeniem.
#
# Użycie: scripts/build-app.sh [--debug] [--native]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="release"
ARCHS=(--arch arm64 --arch x86_64)
for arg in "$@"; do
    case "$arg" in
        --debug) CONFIG="debug" ;;
        --native) ARCHS=() ;;
        *) echo "Nieznana opcja: $arg" >&2; exit 64 ;;
    esac
done

IDENTITY="Wyspa Development"
APP="build/Wyspa.app"

swift build -c "$CONFIG" ${ARCHS[@]+"${ARCHS[@]}"}
BIN_DIR="$(swift build -c "$CONFIG" ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Wyspa" "$APP/Contents/MacOS/Wyspa"
cp Resources/Info.plist "$APP/Contents/Info.plist"

if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
    codesign --force --timestamp=none --sign "$IDENTITY" "$APP"
    echo "Podpisano certyfikatem „${IDENTITY}”."
else
    codesign --force --sign - "$APP"
    echo "UWAGA: brak certyfikatu „${IDENTITY}”, użyto podpisu ad-hoc."
    echo "       Zgody systemowe będą znikać po każdym buildzie. Uruchom scripts/dev-cert.sh."
fi

codesign --verify --strict "$APP"
lipo -info "$APP/Contents/MacOS/Wyspa"
echo "Gotowe: $APP"
