#!/bin/bash

set -euo pipefail

# Tests for backup_database function

# Test Setup
setup() {
    # Create isolated environment
    TEST_DIR=$(mktemp -d)

    # Track mock invocations
    MOCK_LOG="${TEST_DIR}/mock.log"

    # Create a wrapper script to source the actual script so we can override variables
    cat > "${TEST_DIR}/run_test.sh" << 'EOF'
#!/bin/bash
source "$1"

# Override variables
BACKUP_DIR="$2"
LOG_FILE="$3"
COMPOSE_FILE="$4"
MOCK_LOG="$5"

# --- MOCKS ---
docker() {
    echo "docker $*" >> "$MOCK_LOG"
    if [[ "$DOCKER_SHOULD_FAIL" == "true" ]]; then
        return 1
    fi
    # Simulate pg_dump output
    echo "dump_data"
}

gzip() {
    echo "gzip $*" >> "$MOCK_LOG"
    if [[ "$GZIP_SHOULD_FAIL" == "true" ]]; then
        return 1
    fi
    # Read from stdin and compress (just pass through here or actually compress)
    cat > /dev/null
    echo "gzipped_data"
}

du() {
    echo "10M	$1"
}

# Run the function
backup_database "$6"
EOF
    chmod +x "${TEST_DIR}/run_test.sh"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# --- TESTS ---

test_success() {
    setup
    export DOCKER_SHOULD_FAIL="false"
    export GZIP_SHOULD_FAIL="false"

    local timestamp="20230101_120000"
    local local_backup_dir="${TEST_DIR}/backups"
    local local_log_file="${local_backup_dir}/backup.log"
    local local_compose_file="${TEST_DIR}/docker-compose.yml"

    mkdir -p "$local_backup_dir"
    touch "$local_compose_file"

    local expected_file="${local_backup_dir}/db_${timestamp}.sql.gz"

    # Run the function
    local result
    result=$("${TEST_DIR}/run_test.sh" "$(dirname "$0")/../scripts/backup.sh" "$local_backup_dir" "$local_log_file" "$local_compose_file" "$MOCK_LOG" "$timestamp")
    local status=$?

    # Assertions
    if [[ "$status" -ne 0 ]]; then
        echo "FAIL: test_success - Function returned non-zero status: $status"
        teardown
        return 1
    fi

    # check that result contains the expected file path as its last line
    local last_line
    last_line=$(echo "$result" | tail -n 1)
    if [[ "$last_line" != "$expected_file" ]]; then
        echo "FAIL: test_success - Expected result to end with '$expected_file', got '$last_line'"
        teardown
        return 1
    fi

    if [[ ! -f "$expected_file" ]]; then
        echo "FAIL: test_success - Expected file '$expected_file' was not created"
        teardown
        return 1
    fi

    if ! grep -q "docker compose -f $local_compose_file exec -T db pg_dump -U n8n n8n" "$MOCK_LOG"; then
        echo "FAIL: test_success - docker command was not called correctly"
        cat "$MOCK_LOG"
        teardown
        return 1
    fi

    echo "PASS: test_success"
    teardown
}

test_docker_failure() {
    setup
    export DOCKER_SHOULD_FAIL="true"
    export GZIP_SHOULD_FAIL="false"

    local timestamp="20230101_120000"
    local local_backup_dir="${TEST_DIR}/backups"
    local local_log_file="${local_backup_dir}/backup.log"
    local local_compose_file="${TEST_DIR}/docker-compose.yml"

    mkdir -p "$local_backup_dir"
    touch "$local_compose_file"

    local expected_file="${local_backup_dir}/db_${timestamp}.sql.gz"

    # Run the function (should fail)
    set +e
    local result
    result=$("${TEST_DIR}/run_test.sh" "$(dirname "$0")/../scripts/backup.sh" "$local_backup_dir" "$local_log_file" "$local_compose_file" "$MOCK_LOG" "$timestamp")
    local status=$?
    set -e

    # Assertions
    if [[ "$status" -eq 0 ]]; then
        echo "FAIL: test_docker_failure - Function returned zero status, expected failure"
        teardown
        return 1
    fi

    if [[ -f "$expected_file" ]]; then
        echo "FAIL: test_docker_failure - Backup file should have been removed on failure"
        teardown
        return 1
    fi

    echo "PASS: test_docker_failure"
    teardown
}

test_gzip_failure() {
    setup
    export DOCKER_SHOULD_FAIL="false"
    export GZIP_SHOULD_FAIL="true"

    local timestamp="20230101_120000"
    local local_backup_dir="${TEST_DIR}/backups"
    local local_log_file="${local_backup_dir}/backup.log"
    local local_compose_file="${TEST_DIR}/docker-compose.yml"

    mkdir -p "$local_backup_dir"
    touch "$local_compose_file"

    local expected_file="${local_backup_dir}/db_${timestamp}.sql.gz"

    # Run the function (should fail due to pipefail)
    set +e
    local result
    result=$("${TEST_DIR}/run_test.sh" "$(dirname "$0")/../scripts/backup.sh" "$local_backup_dir" "$local_log_file" "$local_compose_file" "$MOCK_LOG" "$timestamp")
    local status=$?
    set -e

    # Assertions
    if [[ "$status" -eq 0 ]]; then
        echo "FAIL: test_gzip_failure - Function returned zero status, expected failure"
        teardown
        return 1
    fi

    if [[ -f "$expected_file" ]]; then
        echo "FAIL: test_gzip_failure - Backup file should have been removed on failure"
        teardown
        return 1
    fi

    echo "PASS: test_gzip_failure"
    teardown
}

# Run tests
echo "Running tests for backup_database..."
fails=0
test_success || fails=$((fails + 1))
test_docker_failure || fails=$((fails + 1))
test_gzip_failure || fails=$((fails + 1))

if [[ $fails -gt 0 ]]; then
    echo "Tests failed: $fails"
    exit 1
else
    echo "All tests passed!"
    exit 0
fi