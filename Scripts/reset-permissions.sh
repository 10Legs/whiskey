#!/usr/bin/env bash
# reset-permissions.sh
# Removes WhisKey from TCC (Accessibility + Input Monitoring).
# Run this when you need a clean permission state.
# After running, re-launch WhisKey and re-grant in System Settings > Privacy & Security.

BUNDLE_ID="com.rdemeritt.whiskey"

echo "Resetting TCC permissions for $BUNDLE_ID..."

tccutil reset Accessibility "$BUNDLE_ID"
echo "  ✓ Accessibility reset"

tccutil reset ListenEvent "$BUNDLE_ID"
echo "  ✓ Input Monitoring reset"

echo ""
echo "Done. Re-launch WhisKey and grant Accessibility + Input Monitoring in:"
echo "  System Settings > Privacy & Security > Accessibility"
echo "  System Settings > Privacy & Security > Input Monitoring"
echo ""
echo "NOTE: With WhiskeyDev certificate, you should only need to do this once."
