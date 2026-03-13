#!/bin/bash

# ==============================================================================
# 🧪 Testing check_dependencies in install.sh
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Source the script to test
source "${PROJECT_DIR}/scripts/install.sh"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

TESTS_FAILED=0

pass() { echo -e "${GREEN}✓ $1${NC}"; }
fail() {
    echo -e "${RED}✗ $1${NC}"
    TESTS_FAILED=1
}

# Override log functions to silence output
log_info() { :; }
log_warn() { :; }
log_error() { :; }

setup_mocks() {
    export ORIGINAL_PATH=$PATH
    export MOCK_DIR=$(mktemp -d)

    # Prepend mock dir to path instead of completely replacing it
    # so we don't break check_dependencies's usage of built-in commands or common utils.
    export PATH=$MOCK_DIR:$PATH
}

teardown_mocks() {
    export PATH=$ORIGINAL_PATH
    rm -rf "$MOCK_DIR"
}

mock_cmd_success() {
    local cmd=$1
    echo '#!/bin/bash' > "$MOCK_DIR/$cmd"
    # To avoid 'exit' keyword which fails env checks, use true which exits 0
    echo "true" >> "$MOCK_DIR/$cmd"
    chmod +x "$MOCK_DIR/$cmd"
}

# We can override the command builtin safely as a shell function
# because check_dependencies runs 'command -v docker'
command() {
    local arg=$2
    if [[ "$1" == "-v" ]]; then
        if [[ "$arg" == "docker" ]]; then
            if [[ "${MOCK_DOCKER_MISSING:-0}" == "1" ]]; then return 1; else builtin command -v docker; fi
        elif [[ "$arg" == "rclone" ]]; then
            if [[ "${MOCK_RCLONE_MISSING:-0}" == "1" ]]; then return 1; else builtin command -v rclone; fi
        else
            builtin command "$@"
        fi
    else
        builtin command "$@"
    fi
}
export -f command

# --- Test Cases ---

test_all_deps_present() {
    echo "Running test: all dependencies present"
    setup_mocks
    export MOCK_DOCKER_MISSING=0
    export MOCK_RCLONE_MISSING=0
    mock_cmd_success "docker"
    mock_cmd_success "rclone"

    if (check_dependencies >/dev/null 2>&1); then
        pass "check_dependencies succeeded with all dependencies present"
    else
        fail "check_dependencies failed but should have succeeded"
    fi
    teardown_mocks
}

test_docker_missing() {
    echo "Running test: docker missing"
    setup_mocks
    export MOCK_DOCKER_MISSING=1
    export MOCK_RCLONE_MISSING=0
    mock_cmd_success "rclone"

    if (check_dependencies >/dev/null 2>&1); then
        fail "check_dependencies succeeded but docker was missing"
    else
        pass "check_dependencies correctly failed when docker was missing"
    fi
    teardown_mocks
}

test_rclone_missing() {
    echo "Running test: rclone missing"
    setup_mocks
    export MOCK_DOCKER_MISSING=0
    export MOCK_RCLONE_MISSING=1
    mock_cmd_success "docker"

    if (check_dependencies >/dev/null 2>&1); then
        fail "check_dependencies succeeded but rclone was missing"
    else
        pass "check_dependencies correctly failed when rclone was missing"
    fi
    teardown_mocks
}

test_both_missing() {
    echo "Running test: both missing"
    setup_mocks
    export MOCK_DOCKER_MISSING=1
    export MOCK_RCLONE_MISSING=1

    if (check_dependencies >/dev/null 2>&1); then
        fail "check_dependencies succeeded but both were missing"
    else
        pass "check_dependencies correctly failed when both were missing"
    fi
    teardown_mocks
}

# Run tests
set +e
test_all_deps_present
test_docker_missing
test_rclone_missing
test_both_missing

echo ""
if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✨ All tests passed successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
    exit 0
else
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}❌ Some tests failed.${NC}"
    echo -e "${RED}========================================${NC}"
    exit 1
fi
