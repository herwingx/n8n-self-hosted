#!/bin/bash

# Define variables needed
SCRIPT_DIR="/tmp/scripts"
PROJECT_DIR="/tmp/project"

echo "Adding mock crontab to use cron files..."
mkdir -p /tmp/cron
cat << 'MOCK' > /tmp/crontab_mock
#!/bin/bash
if [ "$1" = "-l" ]; then
    sleep 0.5 # simulate network/system delay
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
    sleep 0.5
fi
MOCK
chmod +x /tmp/crontab_mock

mkdir -p /tmp/bin
cp /tmp/crontab_mock /tmp/bin/crontab
export PATH="/tmp/bin:$PATH"

setup_cron_original() {
    local cron_job="0 3 * * * ${SCRIPT_DIR}/backup.sh >> ${PROJECT_DIR}/backups/cron.log 2>&1"
    local cron_comment="# n8n-backup: Backup diario a las 3:00 AM"

    if crontab -l 2>/dev/null | grep -q "n8n-backup"; then
        return
    fi

    (crontab -l 2>/dev/null || echo ""; echo "$cron_comment"; echo "$cron_job") | crontab -
}

# We can source install.sh
source scripts/install.sh >/dev/null 2>&1 || true

log_warn() { :; }
log_info() { :; }

# Benchmark Original Adding
echo "Benchmarking Original Adding..."
crontab -r 2>/dev/null || true
start=$(date +%s%N)
setup_cron_original
end=$(date +%s%N)
diff_orig_add=$(( (end - start) / 1000000 ))
echo "Original (adding): ${diff_orig_add} ms"

# Benchmark Optimized Adding
echo "Benchmarking Optimized Adding..."
crontab -r 2>/dev/null || true
start=$(date +%s%N)
setup_cron
end=$(date +%s%N)
diff_opt_add=$(( (end - start) / 1000000 ))
echo "Optimized (adding): ${diff_opt_add} ms"

echo "Improvement (adding): $((diff_orig_add - diff_opt_add)) ms"

# Benchmark Original Existing
echo "Benchmarking Original Existing..."
crontab -r 2>/dev/null || true
setup_cron_original # initialize so it exists
start=$(date +%s%N)
setup_cron_original
end=$(date +%s%N)
diff_orig_exist=$(( (end - start) / 1000000 ))
echo "Original (existing): ${diff_orig_exist} ms"


# Benchmark Optimized Existing
echo "Benchmarking Optimized Existing..."
crontab -r 2>/dev/null || true
setup_cron # initialize so it exists
start=$(date +%s%N)
setup_cron
end=$(date +%s%N)
diff_opt_exist=$(( (end - start) / 1000000 ))
echo "Optimized (existing): ${diff_opt_exist} ms"

echo "Improvement (existing): $((diff_orig_exist - diff_opt_exist)) ms"
