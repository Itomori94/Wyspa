#!/usr/bin/env bash
# Uruchamia wszystkie testy jednostkowe. Wywoływane przed każdym commitem.
set -euo pipefail
cd "$(dirname "$0")/.."
swift test "$@"
