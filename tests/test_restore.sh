#!/bin/bash
# Tests for download_from_drive function in scripts/restore.sh

set -euo pipefail

# Setup environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
export TEST_DIR=$(mktemp -d)
export BACKUP_DIR="${TEST_DIR}/backups"
export MOCK_RCLONE_OUTPUT="${TEST_DIR}/mock_rclone_output.log"
export MOCK_LOG_INFO="${TEST_DIR}/mock_log_info.log"
export MOCK_LOG_ERROR="${TEST_DIR}/mock_log_error.log"

mkdir -p "$BACKUP_DIR"

# Clean up function
cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# Mock functions
rclone() {
    echo "rclone $@" >> "$MOCK_RCLONE_OUTPUT"
    # To test success/fail based on filename
    if [[ "$@" =~ "fail.tar.gz" ]]; then
        return 1
    else
        return 0
    fi
}

log_info() {
    echo "$@" >> "$MOCK_LOG_INFO"
}

log_error() {
    echo "$@" >> "$MOCK_LOG_ERROR"
}

# Export mocks to be used by sourced script
export -f rclone
export -f log_info
export -f log_error

# Source the script under test
source "${PROJECT_DIR}/scripts/restore.sh"

# Mock functions to override those from sourced script
rclone() {
    echo "rclone $@" >> "$MOCK_RCLONE_OUTPUT"
    # To test success/fail based on filename
    if [[ "$@" =~ "fail.tar.gz" ]]; then
        return 1
    else
        return 0
    fi
}

log_info() {
    echo "$@" >> "$MOCK_LOG_INFO"
}

log_error() {
    echo "$@" >> "$MOCK_LOG_ERROR"
}

# Test counter
TESTS_RUN=0
TESTS_PASSED=0

assert_success() {
    local exit_code=$1
    local test_name=$2
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ $exit_code -eq 0 ]]; then
        echo "✅ PASS: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "❌ FAIL: $test_name (Expected 0, got $exit_code)"
    fi
}

assert_failure() {
    local exit_code=$1
    local test_name=$2
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ $exit_code -ne 0 ]]; then
        echo "✅ PASS: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "❌ FAIL: $test_name (Expected non-zero, got $exit_code)"
    fi
}

# ─────────────────────────────────────────────────────────────────────
# Tests
# ─────────────────────────────────────────────────────────────────────

# Test 1: Happy Path
echo "--- Testing download_from_drive (Happy Path) ---"
rm -f "$MOCK_RCLONE_OUTPUT" "$MOCK_LOG_INFO" "$MOCK_LOG_ERROR"

output=$(download_from_drive "success.tar.gz" 2>/dev/null)
exit_code=$?

assert_success $exit_code "download_from_drive success.tar.gz returns 0"

# Verify rclone was called with correct arguments
if grep -q "rclone copy ${RCLONE_REMOTE}:${RCLONE_FOLDER}/success.tar.gz $BACKUP_DIR/ --progress" "$MOCK_RCLONE_OUTPUT"; then
    assert_success 0 "rclone copy called with correct arguments for success.tar.gz"
else
    assert_failure 0 "rclone copy called with incorrect arguments for success.tar.gz"
fi

# Verify expected echo output
expected_dest="${BACKUP_DIR}/success.tar.gz"
if [[ "$output" == "$expected_dest" ]]; then
    assert_success 0 "download_from_drive echoes the destination path"
else
    assert_failure 0 "download_from_drive failed to echo the destination path (Got: $output, Expected: $expected_dest)"
fi

# Verify logging
if grep -q "✅ Descarga completada" "$MOCK_LOG_INFO"; then
    assert_success 0 "log_info logs success message"
else
    assert_failure 0 "log_info did not log success message"
fi

# Test 2: Failure Path
echo "--- Testing download_from_drive (Failure Path) ---"
rm -f "$MOCK_RCLONE_OUTPUT" "$MOCK_LOG_INFO" "$MOCK_LOG_ERROR"

# Using set +e so the script doesn't exit when download_from_drive fails
set +e
output=$(download_from_drive "fail.tar.gz" 2>/dev/null)
exit_code=$?
set -e

assert_failure $exit_code "download_from_drive fail.tar.gz returns non-zero"

# Verify rclone was called with correct arguments
if grep -q "rclone copy ${RCLONE_REMOTE}:${RCLONE_FOLDER}/fail.tar.gz $BACKUP_DIR/ --progress" "$MOCK_RCLONE_OUTPUT"; then
    assert_success 0 "rclone copy called with correct arguments for fail.tar.gz"
else
    assert_failure 0 "rclone copy called with incorrect arguments for fail.tar.gz"
fi

# Verify unexpected echo output is empty
if [[ -z "$output" ]]; then
    assert_success 0 "download_from_drive echoes nothing on failure"
else
    assert_failure 0 "download_from_drive echoed something on failure (Got: $output)"
fi

# Verify error logging
if grep -q "Error al descargar" "$MOCK_LOG_ERROR"; then
    assert_success 0 "log_error logs error message"
else
    assert_failure 0 "log_error did not log error message"
fi

# ─────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────
echo ""
echo "Test Summary: $TESTS_PASSED/$TESTS_RUN tests passed."

if [[ $TESTS_PASSED -eq $TESTS_RUN ]]; then
    exit 0
else
    exit 1
fi
