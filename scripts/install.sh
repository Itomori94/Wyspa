#!/usr/bin/env bash
# Instaluje Wyspę do /Applications: build, zamknięcie działającej kopii, podmiana, uruchomienie.
#
# Użycie: scripts/install.sh [--skip-build] [--native]
#   --native   build tylko na bieżącą architekturę (szybszy; tak instaluje aktualizacja z poziomu Wyspy)
#
# Linie „▸ <etap>: …” czyta Wyspa podczas aktualizacji (okienko postępu) — nazwy etapów są wspólne z UpdateStage (test).
set -euo pipefail
cd "$(dirname "$0")/.."

TARGET="/Applications/Wyspa.app"
# Kopia obok docelowej (ten sam wolumin), zrobiona, póki stara wersja działa: po jej zamknięciu podmiana
# to tylko zmiana nazwy, więc Wyspy nie ma najwyżej przez chwilę.
STAGING="/Applications/.Wyspa-instalacja"

BUILD=1
BUILD_ARGS=()
for arg in "$@"; do
    case "$arg" in
        --skip-build) BUILD=0 ;;
        --native) BUILD_ARGS+=(--native) ;;
        *) echo "Nieznana opcja: $arg" >&2; exit 64 ;;
    esac
done

stage() { echo "▸ $1: $2"; }

# -a: pgrep i pkill domyślnie pomijają swoich przodków, a przy aktualizacji z poziomu Wyspy to ona uruchamia ten
# skrypt. Bez -a Wyspa nie była zamykana, a `open` tylko ją aktywował — działała stara wersja do ręcznego restartu.
running() { pgrep -a -x Wyspa >/dev/null; }

# Czeka do $1 × 0,1 s, aż żadna kopia Wyspy nie działa.
wait_for_exit() {
    for _ in $(seq 1 "$1"); do
        running || return 0
        sleep 0.1
    done
    ! running
}

STOPPED=0
LAUNCHED=0
# Gdy skrypt zamknął Wyspę, a potem coś się nie udało, uruchamia ją z powrotem (nową, jeśli zdążyła się
# zainstalować) — Wyspa nie zostaje wyłączona.
finish() {
    rm -rf "$STAGING"
    if [ "$STOPPED" = 1 ] && [ "$LAUNCHED" = 0 ]; then
        echo "Instalacja przerwana — uruchamiam Wyspę z powrotem." >&2
        if [ -d "$TARGET" ]; then open "$TARGET" || true; else open build/Wyspa.app || true; fi
    fi
}
trap finish EXIT

if [ "$BUILD" = 1 ]; then
    stage build "budowanie Wyspy"
    scripts/build-app.sh ${BUILD_ARGS[@]+"${BUILD_ARGS[@]}"}
fi
[ -d build/Wyspa.app ] || { echo "Brak build/Wyspa.app — uruchom bez --skip-build." >&2; exit 1; }

stage install "kopiowanie do $(dirname "$TARGET")"
rm -rf "$STAGING"
mkdir "$STAGING"
ditto build/Wyspa.app "$STAGING/Wyspa.app"
codesign --verify --strict "$STAGING/Wyspa.app"

stage restart "zamykanie Wyspy i uruchamianie nowej wersji"
if running; then
    STOPPED=1
    # SIGTERM: Wyspa zamyka się porządnie (moduły kończą procesy potomne, hooki Claude wracają do terminala).
    pkill -a -x Wyspa || true
    if ! wait_for_exit 100; then
        echo "Wyspa nie zamknęła się w 10 s — zamykam ją na siłę." >&2
        pkill -KILL -a -x Wyspa || true
        wait_for_exit 50 || { echo "Nie udało się zamknąć Wyspy." >&2; exit 1; }
    fi
fi
rm -rf "$TARGET"
mv "$STAGING/Wyspa.app" "$TARGET"

# Sprawdzamy, że nowa kopia naprawdę ruszyła: `open` potrafi się nie udać, np. gdy LaunchServices
# jeszcze nie odnotowało zamknięcia poprzedniej.
for attempt in 1 2 3; do
    open "$TARGET" || true
    for _ in $(seq 1 50); do
        if running; then LAUNCHED=1; break 2; fi
        sleep 0.1
    done
    echo "Wyspa się nie uruchomiła (próba $attempt z 3)." >&2
done
[ "$LAUNCHED" = 1 ] || { echo "Nie udało się uruchomić $TARGET." >&2; exit 1; }

echo "Zainstalowano: $TARGET"
echo
echo "Po pierwszej instalacji w /Applications:"
echo "  • Ustawienia → Ogólne: włącz ponownie „Uruchamiaj przy logowaniu” (dotyczy nowej lokalizacji)."
echo "  • Ustawienia → Moduły → Claude Code: jeśli widać „Hooki wymagają aktualizacji”, kliknij „Zaktualizuj ścieżkę”."
