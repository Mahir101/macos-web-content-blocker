#!/bin/bash
# uninstall.sh — stop and remove both services and clean /etc/hosts.
#
# Note: the in-app delayed-disable protection does NOT gate this script;
# it is the operator-level escape hatch. Remove or restrict it if you
# want the install to be harder to undo.
set -euo pipefail

USER_AGENTS="$HOME/Library/LaunchAgents"
SYSTEM_DAEMONS="/Library/LaunchDaemons"
BLOCKERD_LABEL="com.selfcontrol.pornblocker.blockerd"
HOSTSSYNC_LABEL="com.selfcontrol.pornblocker.hostssync"
BEGIN="# >>> pornblocker BEGIN (managed; do not edit) >>>"
END="# <<< pornblocker END <<<"

echo "==> Stopping blockerd…"
launchctl bootout "gui/$(id -u)/$BLOCKERD_LABEL" 2>/dev/null || true
rm -f "$USER_AGENTS/$BLOCKERD_LABEL.plist"

echo "==> Stopping hosts-sync daemon (needs sudo)…"
sudo launchctl bootout "system/$HOSTSSYNC_LABEL" 2>/dev/null || true
sudo rm -f "$SYSTEM_DAEMONS/$HOSTSSYNC_LABEL.plist"

echo "==> Cleaning managed block from /etc/hosts…"
sudo awk -v b="$BEGIN" -v e="$END" '
    $0 == b {skip=1; next}
    $0 == e {skip=0; next}
    skip != 1 {print}
' /etc/hosts | sudo tee /etc/hosts.tmp >/dev/null
sudo mv /etc/hosts.tmp /etc/hosts
sudo dscacheutil -flushcache 2>/dev/null || true
sudo killall -HUP mDNSResponder 2>/dev/null || true

echo "==> Uninstalled. Support data left in ~/Library/Application Support/PornBlocker"
echo "    (delete it manually if you want a full wipe)."
