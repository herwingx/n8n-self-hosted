#!/bin/bash

# Test suite for upload_to_drive function in scripts/backup.sh
# Tests success and failure paths using manual mocking

set -euo pipefail

# Find the script to source
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_SCRIPT="${PROJECT_DIR}/scripts/backup.sh"

# Test setup
setup() {
    export TEST_TEMP_DIR="$(mktemp -d)"
    export LOG_FILE="${TEST_TEMP_DIR}/test.log"
    export TEST_FILE="${TEST_TEMP_DIR}/dummy_backup.tar.gz"
    export RCLONE_REMOTE="gdrive"
    export RCLONE_FOLDER="N8N"
    touch "$TEST_FILE"

    trap teardown EXIT

    # Store the path to the original rclone command or just know we'll use a function mock
    # Mocks go here
}

teardown() {
    rm -rf "$TEST_TEMP_DIR"
}

# The actual mock needs to capture execution context and control exit status.
# We will define a bash function that overrides the command.

# Test Cases
test_upload_success() {
    # 1. Setup mock
    rclone() {
        # Mock rclone copy success
        echo "MOCK: rclone $1 $2 $3 $4" >> "${TEST_TEMP_DIR}/mock_rclone_calls.log"
        return 0
    }

    # Export function if needed, but since we're sourcing the script in the same shell
    # the function override should apply.

    # 2. Execute
    source "$BACKUP_SCRIPT"
    # source command overrides variables initialized in setup
    export LOG_FILE="${TEST_TEMP_DIR}/test.log"

    # Reset mock log
    rm -f "${TEST_TEMP_DIR}/mock_rclone_calls.log"

    local exit_code=0
    upload_to_drive "$TEST_FILE" || exit_code=$?

    # 3. Assert
    if [[ $exit_code -ne 0 ]]; then
        echo "❌ test_upload_success: Failed! Expected exit code 0, got $exit_code"
        return 1
    fi

    # Verify rclone was called
    if ! grep -q "MOCK: rclone copy $TEST_FILE ${RCLONE_REMOTE}:${RCLONE_FOLDER}/ --progress" "${TEST_TEMP_DIR}/mock_rclone_calls.log"; then
        echo "❌ test_upload_success: Failed! rclone was not called with correct arguments"
        cat "${TEST_TEMP_DIR}/mock_rclone_calls.log"
        return 1
    fi

    echo "✅ test_upload_success: Passed"
    return 0
}

test_upload_failure() {
    # 1. Setup mock
    rclone() {
        # Mock rclone copy failure
        echo "MOCK: rclone copy failure" >> "${TEST_TEMP_DIR}/mock_rclone_calls.log"
        return 1
    }

    # 2. Execute
    source "$BACKUP_SCRIPT"
    export LOG_FILE="${TEST_TEMP_DIR}/test.log"

    local exit_code=0
    upload_to_drive "$TEST_FILE" > /dev/null 2>&1 || exit_code=$?

    # 3. Assert
    if [[ $exit_code -ne 1 ]]; then
        echo "❌ test_upload_failure: Failed! Expected exit code 1, got $exit_code"
        return 1
    fi

    echo "✅ test_upload_failure: Passed"
    return 0
}

# Run tests
main() {
    echo "Running upload_to_drive tests..."

    local failed=0

    setup
    test_upload_success || failed=1

    # Reset test dir for next test
    rm -f "${TEST_TEMP_DIR}/mock_rclone_calls.log"
    rm -f "$LOG_FILE"

    test_upload_failure || failed=1

    if [[ $failed -ne 0 ]]; then
        echo "❌ Some tests failed."
        exit 1
    else
        echo "✅ All tests passed."
        exit 0
    fi
}

main "$@"