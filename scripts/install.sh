#!/usr/bin/env bash
# Instaluje Wyspę do /Applications: build, zamknięcie działającej kopii, podmiana, uruchomienie.
#
# Użycie: scripts/install.sh [--skip-build]
set -euo pipefail
cd "$(dirname "$0")/.."

TARGET="/Applications/Wyspa.app"

if [ "${1:-}" != "--skip-build" ]; then
    scripts/build-app.sh
fi
[ -d build/Wyspa.app ] || { echo "Brak build/Wyspa.app — uruchom bez --skip-build." >&2; exit 1; }

# SIGTERM: Wyspa zamyka się porządnie (moduły kończą procesy potomne, hooki Claude wracają do terminala).
if pgrep -x Wyspa >/dev/null; then
    pkill -x Wyspa || true
    for _ in $(seq 1 50); do pgrep -x Wyspa >/dev/null || break; sleep 0.1; done
fi

rm -rf "$TARGET"
ditto build/Wyspa.app "$TARGET"
codesign --verify --strict "$TARGET"
open "$TARGET"

echo "Zainstalowano: $TARGET"
echo
echo "Po pierwszej instalacji w /Applications:"
echo "  • Ustawienia → Ogólne: włącz ponownie „Uruchamiaj przy logowaniu” (dotyczy nowej lokalizacji)."
echo "  • Ustawienia → Moduły → Claude Code: jeśli widać „Hooki wskazują inną kopię Wyspy”, kliknij „Zaktualizuj ścieżkę”."
