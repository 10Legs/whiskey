#!/usr/bin/env bash
# Watch a GitHub PR's CI checks and report when done.
# Usage: ./scripts/watch-ci.sh <pr-number> [repo] [interval-seconds]
#   pr-number : required
#   repo      : default 10Legs/whiskey
#   interval  : default 30 seconds

set -euo pipefail

PR="${1:?Usage: $0 <pr-number> [repo] [interval-seconds]}"
REPO="${2:-10Legs/whiskey}"
INTERVAL="${3:-30}"

echo "[watch-ci] Watching PR #$PR on $REPO (polling every ${INTERVAL}s)"
echo "[watch-ci] Started at $(date)"

EXPECTED_CHECKS=3  # Build & Test, SwiftLint, Code Quality

while true; do
    output=$(gh pr checks "$PR" --repo "$REPO" 2>&1) || true
    timestamp=$(date '+%H:%M:%S')

    # Count states
    pending=$(echo "$output" | grep -c $'\tpending\t' || true)
    passing=$(echo "$output" | grep -c $'\tpass\t' || true)
    failing=$(echo "$output" | grep -c $'\tfail\t' || true)
    total=$(( pending + passing + failing ))

    echo "[$timestamp] total=$total pending=$pending pass=$passing fail=$failing"

    # Guard: require all expected checks to be registered before declaring done.
    # Avoids false-green when a new run hasn't registered its jobs yet.
    if [[ "$pending" -eq 0 && "$total" -ge "$EXPECTED_CHECKS" ]]; then
        echo ""
        echo "[watch-ci] All checks complete:"
        echo "$output"
        if [[ "$failing" -gt 0 ]]; then
            echo ""
            echo "[watch-ci] FAILED — $failing check(s) failed."
            exit 1
        else
            echo ""
            echo "[watch-ci] ALL GREEN — PR #$PR is ready to merge."
            exit 0
        fi
    elif [[ "$total" -eq 0 ]]; then
        echo "[$timestamp] No checks registered yet — waiting for run to start."
    fi

    sleep "$INTERVAL"
done
