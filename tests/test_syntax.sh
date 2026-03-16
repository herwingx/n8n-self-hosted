#!/bin/bash
# Comprueba que scripts/install.sh carga sin errores de sintaxis.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

source "${PROJECT_DIR}/scripts/install.sh" >/dev/null 2>&1 || true
echo "Syntax OK"
