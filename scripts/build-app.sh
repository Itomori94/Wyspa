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
# Skąd pochodzi build — dla modułu Aktualizacje (porównanie z GitHubem i „Zaktualizuj teraz”). Bez gita pola są puste.
SOURCE_COMMIT="$(git rev-parse HEAD 2>/dev/null || true)"
SOURCE_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
SOURCE_REMOTE="$(git remote get-url origin 2>/dev/null || true)"
SOURCE_DIRTY="$([ -n "$(git status --porcelain 2>/dev/null)" ] && echo 1 || echo 0)"
for entry in "WyspaSourceCommit:$SOURCE_COMMIT" "WyspaSourceBranch:$SOURCE_BRANCH" "WyspaSourceRemote:$SOURCE_REMOTE" \
             "WyspaSourcePath:$PWD" "WyspaSourceDirty:$SOURCE_DIRTY"; do
    /usr/libexec/PlistBuddy -c "Add :${entry%%:*} string ${entry#*:}" "$APP/Contents/Info.plist"
done
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Komenda `wyspa` (moduł Skrypty) — skrypt w zasobach, instalowany do ~/.local/bin przyciskiem w ustawieniach.
cp Resources/wyspa "$APP/Contents/Resources/wyspa"
chmod 755 "$APP/Contents/Resources/wyspa"

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
