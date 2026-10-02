#!/usr/bin/env bash
# Uruchamia wszystkie testy jednostkowe. Wywoływane przed każdym commitem.
# Najpierw buduje wyspa-hook, bo testy integracyjne uruchamiają prawdziwy helper.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --product wyspa-hook
swift test "$@"
