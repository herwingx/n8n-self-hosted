#!/bin/bash
source scripts/install.sh >/dev/null 2>&1 || true

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

echo "=== Test 1: Empty crontab ==="
crontab -r 2>/dev/null || true
setup_cron
echo "Crontab contents:"
crontab -l

echo "=== Test 2: Existing crontab with n8n-backup ==="
setup_cron
echo "Crontab contents (should be same as above):"
crontab -l

echo "=== Test 3: Existing crontab without n8n-backup ==="
crontab -r 2>/dev/null || true
echo "0 0 * * * some_other_job" > /tmp/cron/mycron
setup_cron
echo "Crontab contents:"
crontab -l
