#!/bin/bash
# ══════════════════════════════════════════════════════════════════════
# Test: backup_n8n_data in scripts/backup.sh
# ══════════════════════════════════════════════════════════════════════

set -euo pipefail

# Find the project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
GREEN='\033[1;32m'
RED='\033[0;31m'
NC='\033[0m'

# Initialize test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Create a temporary directory for tests
TEST_TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_TEMP_DIR"' EXIT

# Mock tar to either succeed or fail depending on global variable
TAR_SHOULD_FAIL=0
tar() {
    if [[ "$TAR_SHOULD_FAIL" == "1" ]]; then
        return 1
    fi
    # If successful, mimic tar by touching the expected output file
    # Format of tar arguments: tar -czf target.tar.gz -C dir source
    # We just need to touch the target file which is the 3rd argument ($3)
    # Actually wait, let's look at the usage in the script:
    # tar -czf "$backup_file" -C "$PROJECT_DIR" n8n_data
    # Wait, the flags are combined "-czf".
    # Arg 1: -czf
    # Arg 2: backup_file
    touch "$2"
    return 0
}

# Stop tee errors if directories don't exist yet by temporarily disabling logs or creating them
mkdir -p "${ROOT_DIR}/backups"
touch "${ROOT_DIR}/backups/backup.log"

# Mock missing dependencies
docker() { return 0; }
export -f docker
rclone() { return 0; }
export -f rclone

# Mock tee as it is giving permission/not-found issues sometimes when sourced globally
tee() {
    cat
}
export -f tee

# Re-override environment variables that backup.sh overwrites.
# BUT wait! `backup.sh` redefines `log()` and hardcodes `LOG_FILE` if it re-evaluates.
# Actually, since `LOG_FILE` is an exported variable, we must make sure `log()` uses our test `LOG_FILE`.
# Let's just redefine `log()` in the test script to enforce writing to our `LOG_FILE`.

# Source the script under test
# By default, set -e will make the script exit when backup_n8n_data fails in scenario 3.
# We should disable it before calling the function or use `|| true`
set +e
source "${ROOT_DIR}/scripts/backup.sh"
set -e

# Re-override environment variables that backup.sh overwrites
export PROJECT_DIR="${TEST_TEMP_DIR}/project"
export BACKUP_DIR="${TEST_TEMP_DIR}/backups"
export LOG_FILE="${BACKUP_DIR}/backup.log"

# Redefine log function to guarantee it uses the test LOG_FILE
log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" >> "$LOG_FILE"
}
export -f log

# Test Helper Functions
assert_success() {
    local return_code="$1"
    local message="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$return_code" -eq 0 ]]; then
        echo -e "${GREEN}✓ PASS${NC}: $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗ FAIL${NC}: $message (expected success, got code $return_code)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_failure() {
    local return_code="$1"
    local message="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$return_code" -ne 0 ]]; then
        echo -e "${GREEN}✓ PASS${NC}: $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗ FAIL${NC}: $message (expected failure, got success)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_log_contains() {
    local string="$1"
    local message="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if grep -q "$string" "$LOG_FILE"; then
        echo -e "${GREEN}✓ PASS${NC}: $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗ FAIL${NC}: $message (could not find '$string' in log)"
        echo "Log contents:"
        cat "$LOG_FILE"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

setup_test() {
    rm -rf "$PROJECT_DIR" "$BACKUP_DIR"
    mkdir -p "$PROJECT_DIR" "$BACKUP_DIR"
    touch "$LOG_FILE"
    TAR_SHOULD_FAIL=0
}

# ─────────────────────────────────────────────────────────────────────
# Tests
# ─────────────────────────────────────────────────────────────────────

echo "Running tests for backup_n8n_data..."

# Test 1: Missing directory
setup_test
# Don't create n8n_data directory
# Let stdout be discarded, but let stderr remain or be captured, though log() writes to LOG_FILE anyway.
# We had `2>&1` which might have piped stderr to /dev/null too, bypassing our log output perhaps? No, tee should write to file anyway unless it's running in a subshell or something.
# Wait, `backup_n8n_data` writes to `LOG_FILE`. Let's just run it!
output=$(backup_n8n_data "20231024_120000" 2>/dev/null) || return_code=$?
return_code=${return_code:-0}
assert_success "$return_code" "Scenario 1: Returns success when n8n_data dir is missing"
assert_log_contains "WARN" "Scenario 1: Logs WARN message when dir is missing"
assert_log_contains "omitiendo" "Scenario 1: Log message indicates skipping"

# Test 2: Successful backup
setup_test
mkdir -p "${PROJECT_DIR}/n8n_data"
# Capture standard output correctly (without error logs leaking)
output=$(backup_n8n_data "20231024_120000" 2>/dev/null) || return_code=$?
return_code=${return_code:-0}
assert_success "$return_code" "Scenario 2: Returns success when backup completes"
assert_log_contains "INFO" "Scenario 2: Logs INFO message when backup completes"
# Verify backup file was 'created' by the mock tar
expected_file="${BACKUP_DIR}/n8n_data_20231024_120000.tar.gz"
if [[ -f "$expected_file" ]]; then
    assert_success 0 "Scenario 2: Backup file created"
else
    assert_success 1 "Scenario 2: Backup file created"
fi
# Verify echoed output
if [[ "$output" == "$expected_file" ]]; then
    assert_success 0 "Scenario 2: Echoes backup file path"
else
    assert_success 1 "Scenario 2: Echoes backup file path (got: $output)"
fi


# Test 3: Tar failure
setup_test
mkdir -p "${PROJECT_DIR}/n8n_data"
TAR_SHOULD_FAIL=1
# Create a dummy file that should be removed
expected_file="${BACKUP_DIR}/n8n_data_20231024_120000.tar.gz"
touch "$expected_file"

return_code=0
backup_n8n_data "20231024_120000" > /dev/null 2>&1 || return_code=$?

assert_failure "$return_code" "Scenario 3: Returns failure when tar fails"
assert_log_contains "ERROR" "Scenario 3: Logs ERROR message when tar fails"
if [[ ! -f "$expected_file" ]]; then
    assert_success 0 "Scenario 3: Backup file removed on error"
else
    assert_success 1 "Scenario 3: Backup file removed on error"
fi

# ─────────────────────────────────────────────────────────────────────
# Test Summary
# ─────────────────────────────────────────────────────────────────────

echo "----------------------------------------"
echo "Tests Run:    $TESTS_RUN"
echo "Tests Passed: $TESTS_PASSED"
echo "Tests Failed: $TESTS_FAILED"
echo "----------------------------------------"

if [[ "$TESTS_FAILED" -gt 0 ]]; then
    exit 1
fi

exit 0