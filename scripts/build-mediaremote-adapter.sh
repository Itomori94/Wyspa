#!/usr/bin/env bash
# Buduje MediaRemoteAdapter.framework i MediaRemoteAdapterTestClient z Vendor/mediaremote-adapter
# samym clang (bez CMake). Lista źródeł jest czytana z CMakeLists.txt adaptera, więc aktualizacja
# adaptera nie wymaga zmian w tym skrypcie.
#
# Użycie: scripts/build-mediaremote-adapter.sh <katalog-wyjściowy>
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:?Podaj katalog wyjściowy}"
SRC="Vendor/mediaremote-adapter"
NAME="MediaRemoteAdapter"
FLAGS=(-arch arm64 -arch x86_64 -mmacosx-version-min=14.0 -fobjc-arc -O2)

[ -d "$SRC" ] || { echo "Brak $SRC — uruchom scripts/update-mediaremote-adapter.sh" >&2; exit 1; }

# Pliki z bloku set(ADAPTER_SOURCES ...) w CMakeLists.txt.
SOURCES=()
while IFS= read -r file; do
    SOURCES+=("$SRC/$file")
done < <(sed -n '/set(ADAPTER_SOURCES/,/)/p' "$SRC/CMakeLists.txt" | grep -oE 'src/[A-Za-z0-9_/]+\.m')
[ ${#SOURCES[@]} -gt 0 ] || { echo "Nie znaleziono ADAPTER_SOURCES w CMakeLists.txt" >&2; exit 1; }

FRAMEWORK="$OUT/$NAME.framework"
rm -rf "$FRAMEWORK" "$OUT/${NAME}TestClient"
mkdir -p "$FRAMEWORK/Versions/A/Resources" "$FRAMEWORK/Versions/A/Headers"

# Widoczność domyślna: skrypt Perla wywołuje funkcje frameworka po nazwie symbolu.
clang -dynamiclib "${FLAGS[@]}" -fvisibility=default \
    -I"$SRC/include" -I"$SRC/src" \
    -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
    -install_name "@rpath/$NAME.framework/Versions/A/$NAME" \
    "${SOURCES[@]}" -o "$FRAMEWORK/Versions/A/$NAME"
cp "$SRC/include/MediaRemoteAdapter.h" "$FRAMEWORK/Versions/A/Headers/"

VERSION="$(sed -n 's/^tag=v\{0,1\}//p' Vendor/mediaremote-adapter.version)"
cat > "$FRAMEWORK/Versions/A/Resources/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$NAME</string>
    <key>CFBundleIdentifier</key><string>com.vandenbe.$NAME</string>
    <key>CFBundleName</key><string>$NAME</string>
    <key>CFBundlePackageType</key><string>FMWK</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
</dict>
</plist>
PLIST

ln -s A "$FRAMEWORK/Versions/Current"
ln -s "Versions/Current/$NAME" "$FRAMEWORK/$NAME"
ln -s Versions/Current/Resources "$FRAMEWORK/Resources"
ln -s Versions/Current/Headers "$FRAMEWORK/Headers"

clang "${FLAGS[@]}" -I"$SRC/src/test" \
    -framework Foundation -framework MediaPlayer \
    "$SRC/src/test/main.m" "$SRC/src/test/NowPlayingTest.m" \
    -o "$OUT/${NAME}TestClient"

echo "Zbudowano $FRAMEWORK i $OUT/${NAME}TestClient (${#SOURCES[@]} plików źródłowych)"
