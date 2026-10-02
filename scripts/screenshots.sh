#!/bin/bash
# Zrzuty ekranu do README z danymi demonstracyjnymi: docs/screenshots/*.png
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p docs/screenshots
WYSPA_SCREENSHOTS_DIR="$PWD/docs/screenshots" swift test --filter ScreenshotTests
ls -1 docs/screenshots
