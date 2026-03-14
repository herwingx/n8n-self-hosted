#!/bin/bash

# Setup colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test runner functions
describe() {
    echo -e "\n🧪 Testing: $1"
}

it() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "  - $1... "
}

pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓ PASS${NC}"
}

fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗ FAIL${NC}"
    echo -e "    $1"
}

# --- Mock definitions ---
# We will override these in specific test cases if needed
export MOCK_DOCKER_COMPOSE_PS_SUCCESS=1
export MOCK_GUNZIP_SUCCESS=1
export MOCK_DOCKER_COMPOSE_EXEC_SUCCESS=1

docker() {
    if [[ "$1" == "compose" && "$4" == "ps" && "$5" == "db" ]]; then
        if [[ "$MOCK_DOCKER_COMPOSE_PS_SUCCESS" == "1" ]]; then
            echo "db is running"
            return 0
        else
            echo "db is stopped"
            return 1
        fi
    fi

    if [[ "$1" == "compose" && "$4" == "exec" && "$5" == "-T" && "$6" == "db" && "$7" == "psql" ]]; then
        if [[ "$MOCK_DOCKER_COMPOSE_EXEC_SUCCESS" == "1" ]]; then
            # Read from stdin (simulated gunzip output)
            cat > /dev/null
            return 0
        else
            cat > /dev/null
            return 1
        fi
    fi

    # default fallback just in case
    return 0
}

gunzip() {
    if [[ "$1" == "-c" ]]; then
        if [[ "$MOCK_GUNZIP_SUCCESS" == "1" ]]; then
            echo "dummy sql content"
            return 0
        else
            echo "gunzip error" >&2
            return 1
        fi
    fi
    return 0
}

# Source the script under test
# Since the script has 'set -euo pipefail', we temporarily disable 'e'
# so it doesn't immediately exit when a subshell or a command fails.
set +e
source scripts/restore.sh > /dev/null
set -e # re-enable it or let it be. Let's keep it disabled for tests or handle errors carefully.
set +euo pipefail

# --- Test Cases ---

test_db_not_running() {
    it "fails when database service is not running"

    MOCK_DOCKER_COMPOSE_PS_SUCCESS=0

    # Capture output and exit code
    output=$(restore_database "dummy.sql.gz" 2>&1)
    result=$?

    if [[ $result -eq 1 ]] && echo "$output" | grep -q "El servicio de base de datos no está corriendo"; then
        pass
    else
        fail "Expected exit code 1 and error message, got exit code $result and output: $output"
    fi
}

test_successful_restore() {
    it "succeeds when db is running and restore command is successful"

    MOCK_DOCKER_COMPOSE_PS_SUCCESS=1
    MOCK_GUNZIP_SUCCESS=1
    MOCK_DOCKER_COMPOSE_EXEC_SUCCESS=1

    output=$(restore_database "dummy.sql.gz" 2>&1)
    result=$?

    if [[ $result -eq 0 ]] && echo "$output" | grep -q "✅ Base de datos restaurada"; then
        pass
    else
        fail "Expected exit code 0 and success message, got exit code $result and output: $output"
    fi
}

test_gunzip_failure() {
    it "fails when gunzip fails during restore"

    MOCK_DOCKER_COMPOSE_PS_SUCCESS=1
    MOCK_GUNZIP_SUCCESS=0
    MOCK_DOCKER_COMPOSE_EXEC_SUCCESS=1

    # Re-enable pipefail here so we can test the pipeline failure
    set -o pipefail
    output=$(restore_database "dummy.sql.gz" 2>&1)
    result=$?
    set +o pipefail

    if [[ $result -eq 1 ]] && echo "$output" | grep -q "Error al restaurar base de datos"; then
        pass
    else
        fail "Expected exit code 1 and error message, got exit code $result and output: $output"
    fi
}

test_docker_exec_failure() {
    it "fails when docker exec fails during restore"

    MOCK_DOCKER_COMPOSE_PS_SUCCESS=1
    MOCK_GUNZIP_SUCCESS=1
    MOCK_DOCKER_COMPOSE_EXEC_SUCCESS=0

    set -o pipefail
    output=$(restore_database "dummy.sql.gz" 2>&1)
    result=$?
    set +o pipefail

    if [[ $result -eq 1 ]] && echo "$output" | grep -q "Error al restaurar base de datos"; then
        pass
    else
        fail "Expected exit code 1 and error message, got exit code $result and output: $output"
    fi
}

# --- Run Tests ---
describe "restore_database()"
test_db_not_running
test_successful_restore
test_gunzip_failure
test_docker_exec_failure

# --- Summary ---
echo -e "\n📊 Test Summary"
echo "──────────────────"
echo "Total:  $TESTS_RUN"
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
if [[ $TESTS_FAILED -gt 0 ]]; then
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
    exit 1
else
    echo "Done"
    exit 0
fi
