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

ADAPTER_OUT=".build/mediaremote-adapter"
scripts/build-mediaremote-adapter.sh "$ADAPTER_OUT"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/mediaremote-adapter" \
    "$APP/Contents/Frameworks" "$APP/Contents/Helpers"
cp "$BIN_DIR/Wyspa" "$APP/Contents/MacOS/Wyspa"
# Hook Claude Code uruchamiany przez Claude Code (ścieżka wpisywana do ~/.claude/settings.json przy instalacji).
cp "$BIN_DIR/wyspa-hook" "$APP/Contents/Helpers/wyspa-hook"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# mediaremote-adapter: framework ładowany przez /usr/bin/perl (nie linkowany), skrypt, klient testowy, licencja.
cp -R "$ADAPTER_OUT/MediaRemoteAdapter.framework" "$APP/Contents/Frameworks/"
cp "$ADAPTER_OUT/MediaRemoteAdapterTestClient" "$APP/Contents/Helpers/"
cp Vendor/mediaremote-adapter/bin/mediaremote-adapter.pl \
    Vendor/mediaremote-adapter/LICENSE \
    Vendor/mediaremote-adapter.version \
    "$APP/Contents/Resources/mediaremote-adapter/"

if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
    SIGN_ID="$IDENTITY"
    echo "Podpis certyfikatem „${IDENTITY}”."
else
    SIGN_ID="-"
    echo "UWAGA: brak certyfikatu „${IDENTITY}”, użyto podpisu ad-hoc."
    echo "       Zgody systemowe będą znikać po każdym buildzie. Uruchom scripts/dev-cert.sh."
fi
# Kod zagnieżdżony podpisujemy przed pakietem (od środka na zewnątrz).
codesign --force --timestamp=none --sign "$SIGN_ID" "$APP/Contents/Frameworks/MediaRemoteAdapter.framework"
codesign --force --timestamp=none --sign "$SIGN_ID" "$APP/Contents/Helpers/MediaRemoteAdapterTestClient"
codesign --force --timestamp=none --sign "$SIGN_ID" "$APP/Contents/Helpers/wyspa-hook"
codesign --force --timestamp=none --sign "$SIGN_ID" "$APP"

codesign --verify --strict "$APP"
lipo -info "$APP/Contents/MacOS/Wyspa"
echo "Gotowe: $APP"
