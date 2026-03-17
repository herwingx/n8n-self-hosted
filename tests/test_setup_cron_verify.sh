#!/bin/bash
# Verifica que setup_cron (install.sh) añade o mantiene el job de backup correctamente.
# Usa un crontab mock en /tmp para no tocar el crontab real.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Mock functions
log_warn() { echo "log_warn: $1"; }
log_info() { echo "log_info: $1"; }

mkdir -p /tmp/cron
cat << 'MOCK' > /tmp/crontab_mock
#!/bin/bash
if [ "$1" = "-l" ]; then
    if [ -f /tmp/cron/mycron ]; then
        cat /tmp/cron/mycron
    else
        echo "no crontab for user" >&2
        return 1 2>/dev/null || true
    fi
elif [ "$1" = "-r" ]; then
    rm -f /tmp/cron/mycron
elif [ "$1" = "-" ]; then
    cat > /tmp/cron/mycron
fi
MOCK
chmod +x /tmp/crontab_mock
mkdir -p /tmp/bin
cp /tmp/crontab_mock /tmp/bin/crontab
export PATH="/tmp/bin:$PATH"

# Cargar install.sh (usa PROJECT_DIR y SCRIPT_DIR del script)
source "${PROJECT_DIR}/scripts/install.sh" >/dev/null 2>&1 || true

# Re-definir logs para no ensuciar salida
log_warn() { :; }
log_info() { :; }

FAIL=0

# Test 1: crontab vacío → debe quedar con n8n-backup
crontab -r 2>/dev/null || true
setup_cron
if ! crontab -l 2>/dev/null | grep -q "n8n-backup"; then
    echo "FAIL: Test 1 - crontab vacío debería tener entrada n8n-backup"
    FAIL=1
fi

# Test 2: llamar de nuevo no duplica
setup_cron
count=$(crontab -l 2>/dev/null | grep -c "n8n-backup" || true)
if [[ "${count:-0}" -gt 1 ]]; then
    echo "FAIL: Test 2 - no debería duplicar la entrada (count=$count)"
    FAIL=1
fi

# Test 3: crontab con otro job → debe conservar el otro y añadir n8n-backup
crontab -r 2>/dev/null || true
echo "0 0 * * * some_other_job" > /tmp/cron/mycron
setup_cron
if ! crontab -l 2>/dev/null | grep -q "some_other_job"; then
    echo "FAIL: Test 3 - debería conservar some_other_job"
    FAIL=1
fi
if ! crontab -l 2>/dev/null | grep -q "n8n-backup"; then
    echo "FAIL: Test 3 - debería añadir n8n-backup"
    FAIL=1
fi

# Test 4: setup_cron_update añade n8n-update y no duplica
crontab -r 2>/dev/null || true
setup_cron
setup_cron_update
if ! crontab -l 2>/dev/null | grep -q "n8n-update"; then
    echo "FAIL: Test 4 - debería tener entrada n8n-update"
    FAIL=1
fi
setup_cron_update
count=$(crontab -l 2>/dev/null | grep -c "n8n-update" || true)
if [[ "${count:-0}" -gt 1 ]]; then
    echo "FAIL: Test 4 - no debería duplicar n8n-update (count=$count)"
    FAIL=1
fi

# Test 5: crontab debe tener ambos n8n-backup y n8n-update
if ! crontab -l 2>/dev/null | grep -q "n8n-backup"; then
    echo "FAIL: Test 5 - debería tener n8n-backup"
    FAIL=1
fi
if ! crontab -l 2>/dev/null | grep -q "n8n-update"; then
    echo "FAIL: Test 5 - debería tener n8n-update"
    FAIL=1
fi

if [[ $FAIL -eq 0 ]]; then
    echo "test_setup_cron_verify: all passed"
    exit 0
else
    exit 1
fi
