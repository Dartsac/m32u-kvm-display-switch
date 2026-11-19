#!/bin/bash
# Stops the KVM watcher and removes everything install.sh created.
set -uo pipefail

LABEL="local.m32u-kvm-display-watcher"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist" \
      "$HOME/bin/kvm-display-watcher" \
      "$HOME/bin/toggle-mirror.sh" \
      "$HOME/Library/Logs/m32u-kvm-display-watcher.log"
rm -rf "$HOME/.config/display-toggle"
echo "Uninstalled."
