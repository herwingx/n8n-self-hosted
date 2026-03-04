#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Mock colors for test output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

pass() { echo -e "${GREEN}✅ PASS: $1${NC}"; }
fail() { echo -e "${RED}❌ FAIL: $1${NC}"; exit 1; }

# Source install.sh
source "${PROJECT_DIR}/scripts/install.sh"

test_rclone_config_no_gdrive() {
    local output
    # Deshabilitar 'set -e' temporalmente para poder atrapar el error
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
        pass "test_rclone_config_no_gdrive (exited properly and printed error)"
    else
        echo "Actual output: $output"
        fail "test_rclone_config_no_gdrive"
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
                # Simulate folder not existing
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
        pass "test_rclone_config_gdrive_exists_no_n8n (created folder)"
    else
        echo "Actual exit code: $exit_code"
        echo "Actual output: $output"
        fail "test_rclone_config_gdrive_exists_no_n8n"
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
                # Simulate folder existing
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
        pass "test_rclone_config_gdrive_exists_has_n8n (did not create folder)"
    else
        echo "Actual output: $output"
        fail "test_rclone_config_gdrive_exists_has_n8n"
    fi
}

echo "Running tests for check_rclone_config..."
test_rclone_config_no_gdrive
test_rclone_config_gdrive_exists_no_n8n
test_rclone_config_gdrive_exists_has_n8n
echo "All tests passed!"
