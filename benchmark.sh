#!/bin/bash
source scripts/install.sh >/dev/null 2>&1 || true

# Mock functions to avoid output
log_info() { :; }
log_warn() { :; }

# Also mock crontab so we don't actually modify the system crontab in the benchmark?
# Or just let it modify, but clean up after?
# Let's mock crontab to have a consistent slowish response
crontab() {
    # sleep 0.01
    command crontab "$@"
}

time_function() {
    local iterations=100
    local start=$(date +%s%N)
    for i in $(seq 1 $iterations); do
        setup_cron
    done
    local end=$(date +%s%N)
    local diff=$((end - start))
    echo "scale=3; $diff / 1000000" | bc
}

echo "Running benchmark..."
time_function
