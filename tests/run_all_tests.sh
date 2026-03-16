#!/bin/bash
# Ejecuta todos los tests de scripts (excluye benchmarks).
# Debe ejecutarse desde la raíz del proyecto: ./tests/run_all_tests.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

TESTS=(
    "tests/test_syntax.sh"
    "tests/test_install.sh"
    "tests/test_backup_database.sh"
    "tests/test_backup_n8n_data.sh"
    "tests/test_upload_to_drive.sh"
    "tests/test_backup_cleanup_remote.sh"
    "tests/test_restore_database.sh"
    "tests/test_restore.sh"
    "tests/test_setup_cron_verify.sh"
)

FAILED=0
for t in "${TESTS[@]}"; do
    echo "────────────────────────────────────────────"
    echo "▶ $t"
    if "$t"; then
        echo "  OK"
    else
        echo "  FAILED"
        FAILED=$((FAILED + 1))
    fi
done

echo "────────────────────────────────────────────"
if [[ $FAILED -eq 0 ]]; then
    echo "Todos los tests pasaron."
    exit 0
else
    echo "$FAILED test(s) fallaron."
    exit 1
fi
