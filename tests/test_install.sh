#!/bin/bash
# ==============================================================================
# 🧪 Testing install.sh - check_dependencies and check_rclone_config
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
    export PATH=$MOCK_DIR:$PATH
}

teardown_mocks() {
    export PATH=$ORIGINAL_PATH
    rm -rf "$MOCK_DIR"
}

mock_cmd_success() {
    local cmd=$1
    echo '#!/bin/bash' > "$MOCK_DIR/$cmd"
    echo "true" >> "$MOCK_DIR/$cmd"
    chmod +x "$MOCK_DIR/$cmd"
}

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

# ==============================================================================
# Tests for check_dependencies
# ==============================================================================

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

# ==============================================================================
# Tests for check_rclone_config
# ==============================================================================

test_rclone_config_no_gdrive() {
    local output
    set +e
    output=$( (
        rclone() {
            if [[ "$1" == "listremotes" ]]; then echo "other:"; fi
        }
        export -f rclone
        check_rclone_config
    ) 2>&1 )
    local exit_code=$?
    set -e

    if [[ $exit_code -eq 1 ]] && echo "$output" | grep -q "Remote 'gdrive' no encontrado"; then
        pass "check_rclone_config: no gdrive remote (exited properly)"
    else
        echo "Actual output: $output"
        fail "check_rclone_config: no gdrive remote"
    fi
}

test_rclone_config_gdrive_exists_no_n8n() {
    local output
    set +e
    output=$( (
        rclone() {
            if [[ "$1" == "listremotes" ]]; then
                echo "gdrive:"
            elif [[ "$1" == "lsd" ]]; then
                return 1
            elif [[ "$1" == "mkdir" ]]; then
                echo "MOCKED_MKDIR $2"
            fi
        }
        export -f rclone
        check_rclone_config
    ) 2>&1 )
    local exit_code=$?
    set -e

    if [[ $exit_code -eq 0 ]] && echo "$output" | grep -q "MOCKED_MKDIR gdrive:N8N" && echo "$output" | grep -q "Carpeta N8N no existe en Drive, creándola"; then
        pass "check_rclone_config: gdrive exists, created N8N folder"
    else
        echo "Actual exit code: $exit_code"
        echo "Actual output: $output"
        fail "check_rclone_config: gdrive exists no n8n folder"
    fi
}

test_rclone_config_gdrive_exists_has_n8n() {
    local output
    set +e
    output=$( (
        rclone() {
            if [[ "$1" == "listremotes" ]]; then
                echo "gdrive:"
            elif [[ "$1" == "lsd" ]]; then
                return 0
            elif [[ "$1" == "mkdir" ]]; then
                echo "MOCKED_MKDIR $2"
            fi
        }
        export -f rclone
        check_rclone_config
    ) 2>&1 )
    local exit_code=$?
    set -e

    if [[ $exit_code -eq 0 ]] && ! echo "$output" | grep -q "MOCKED_MKDIR" && ! echo "$output" | grep -q "Carpeta N8N no existe en Drive, creándola"; then
        pass "check_rclone_config: gdrive has n8n folder (did not create)"
    else
        echo "Actual output: $output"
        fail "check_rclone_config: gdrive has n8n folder"
    fi
}

# ==============================================================================
# Run all tests
# ==============================================================================
set +e
echo "--- check_dependencies tests ---"
test_all_deps_present
test_docker_missing
test_rclone_missing
test_both_missing

echo ""
echo "--- check_rclone_config tests ---"
test_rclone_config_no_gdrive
test_rclone_config_gdrive_exists_no_n8n
test_rclone_config_gdrive_exists_has_n8n

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
