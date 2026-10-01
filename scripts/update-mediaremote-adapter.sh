#!/usr/bin/env bash
# Pobiera mediaremote-adapter w całości (bez zmian) z wydania o podanym tagu
# do Vendor/mediaremote-adapter i zapisuje przypięcie w Vendor/mediaremote-adapter.version.
#
# Użycie: scripts/update-mediaremote-adapter.sh v0.7.7
set -euo pipefail
cd "$(dirname "$0")/.."

TAG="${1:?Podaj tag wydania, np. v0.7.7}"
REPO="ungive/mediaremote-adapter"
DEST="Vendor/mediaremote-adapter"
LOCK="Vendor/mediaremote-adapter.version"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

curl -fsSL "https://github.com/${REPO}/archive/refs/tags/${TAG}.tar.gz" -o "$WORK/adapter.tar.gz"
SHA256="$(shasum -a 256 "$WORK/adapter.tar.gz" | cut -d' ' -f1)"
COMMIT="$(git ls-remote "https://github.com/${REPO}.git" "refs/tags/${TAG}^{}" "refs/tags/${TAG}" | head -1 | cut -f1)"
[ -n "$COMMIT" ] || { echo "Nie znaleziono tagu ${TAG} w ${REPO}" >&2; exit 1; }

mkdir -p "$WORK/src"
tar -xzf "$WORK/adapter.tar.gz" --strip-components=1 -C "$WORK/src"
[ -f "$WORK/src/LICENSE" ] && [ -f "$WORK/src/bin/mediaremote-adapter.pl" ] \
    || { echo "Archiwum nie wygląda na mediaremote-adapter" >&2; exit 1; }

rm -rf "$DEST"
mkdir -p Vendor
mv "$WORK/src" "$DEST"
cat > "$LOCK" <<LOCKFILE
repository=https://github.com/${REPO}
tag=${TAG}
commit=${COMMIT}
archive_sha256=${SHA256}
license=BSD-3-Clause (Vendor/mediaremote-adapter/LICENSE)
LOCKFILE

echo "mediaremote-adapter ${TAG} (${COMMIT:0:7}) w ${DEST}"
echo "Teraz: scripts/test.sh && scripts/build-app.sh, sprawdź media w wyspie, potem commit."
