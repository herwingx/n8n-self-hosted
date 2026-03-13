#!/bin/bash

set -euo pipefail

# Setup
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${PROJECT_DIR}/scripts/backup.sh"

export REMOTE_RETENTION_DAYS=7
export RCLONE_REMOTE="gdrive"
export RCLONE_FOLDER="N8N"

# Helper for testing assertions
assert_in_log() {
    local expected="$1"
    if ! grep -qF "$expected" "$LOG_FILE"; then
        echo "❌ FAILED: Expected to find '$expected' in log"
        echo "Log content:"
        cat "$LOG_FILE"
        return 1
    fi
    return 0
}

# Source the script.
source "$SCRIPT"

# Ensure log function overrides properly so that testing is easy
log() {
    echo "[$1] $2" >> "$LOG_FILE"
}
export -f log

# Ensure we're overriding LOG_FILE just in case the source reset it
export LOG_FILE=$(mktemp)

# Mock rclone for tests
rclone() {
    echo "mock_rclone called with: $*"
    # Success scenario
    if [[ "$1" == "delete" && "$2" == "${RCLONE_REMOTE}:${RCLONE_FOLDER}/" && "$3" == "--min-age" && "$4" == "${REMOTE_RETENTION_DAYS}d" && -z "${MOCK_RCLONE_FAIL:-}" ]]; then
        echo "Mock rclone delete output"
        return 0
    fi
    # Failure scenario
    if [[ "$1" == "delete" && -n "${MOCK_RCLONE_FAIL:-}" ]]; then
        echo "Mock rclone delete error output" >&2
        return 1
    fi
    return 1
}
export -f rclone

test_cleanup_remote_success() {
    echo "Running test_cleanup_remote_success..."
    > "$LOG_FILE" # Clear log

    unset MOCK_RCLONE_FAIL
    cleanup_remote

    assert_in_log "[INFO] Limpieza remota completada" || return 1
    assert_in_log "[INFO] Limpiando backups remotos mayores a 7 días..." || return 1

    echo "✅ test_cleanup_remote_success passed"
}

test_cleanup_remote_failure() {
    echo "Running test_cleanup_remote_failure..."
    > "$LOG_FILE" # Clear log

    export MOCK_RCLONE_FAIL=1
    cleanup_remote

    assert_in_log "[WARN] Error en limpieza remota (puede que no haya archivos antiguos)" || return 1

    echo "✅ test_cleanup_remote_failure passed"
}

# Run tests
FAILURES=0

test_cleanup_remote_success || FAILURES=$((FAILURES + 1))
test_cleanup_remote_failure || FAILURES=$((FAILURES + 1))

# Cleanup
rm -f "$LOG_FILE"

if [ "$FAILURES" -gt 0 ]; then
    echo "$FAILURES test(s) failed."
    exit 1
else
    echo "All tests passed!"
    exit 0
fi
