#!/bin/bash
# Stops ThumbMap and removes the app and login agent. Your config is kept unless you pass --purge.
set -uo pipefail
LABEL="com.local.thumbmap"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
rm -f  "$HOME/Library/LaunchAgents/$LABEL.plist"
rm -rf "$HOME/Applications/ThumbMap.app"
tccutil reset Accessibility "$LABEL" >/dev/null 2>&1
if [ "${1:-}" = "--purge" ]; then
  rm -rf "$HOME/.config/thumbmap" "$HOME/Library/Logs/ThumbMap.log"
  echo "ThumbMap removed, including config and log."
else
  echo "ThumbMap removed. Config kept at ~/.config/thumbmap (use --purge to delete it)."
fi
