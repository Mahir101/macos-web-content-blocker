#!/bin/bash
# hosts-sync.sh — mirror the blocker's domain export into /etc/hosts.
#
# Run as root by the hostssync LaunchDaemon. Maintains a marked block
# in /etc/hosts delimited by BEGIN/END markers so it can be rewritten
# idempotently without touching the user's other entries.
#
# Usage: hosts-sync.sh /path/to/blocked-domains.txt
set -euo pipefail

EXPORT_FILE="${1:?usage: hosts-sync.sh <export-file>}"
HOSTS_FILE="/etc/hosts"
BEGIN="# >>> pornblocker BEGIN (managed; do not edit) >>>"
END="# <<< pornblocker END <<<"

# Build the new managed block.
block="$BEGIN"$'\n'
if [[ -f "$EXPORT_FILE" ]]; then
    while IFS= read -r domain; do
        [[ -z "$domain" ]] && continue
        # Skip comments / malformed lines.
        [[ "$domain" == \#* ]] && continue
        block+="0.0.0.0 ${domain}"$'\n'
        block+="0.0.0.0 www.${domain}"$'\n'
        block+="::1 ${domain}"$'\n'
    done < "$EXPORT_FILE"
fi
block+="$END"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

# Copy everything outside the managed markers, then append fresh block.
awk -v b="$BEGIN" -v e="$END" '
    $0 == b {skip=1; next}
    $0 == e {skip=0; next}
    skip != 1 {print}
' "$HOSTS_FILE" > "$tmp"

# Drop trailing blank lines, then add the managed block.
printf '%s\n%s\n' "$(cat "$tmp")" "$block" > "${tmp}.2"
mv "${tmp}.2" "$HOSTS_FILE"
chmod 644 "$HOSTS_FILE"

# Flush the DNS cache so changes take effect immediately.
dscacheutil -flushcache 2>/dev/null || true
killall -HUP mDNSResponder 2>/dev/null || true

echo "$(date '+%Y-%m-%dT%H:%M:%S') hosts-sync applied $(grep -c '^0.0.0.0' "$HOSTS_FILE" 2>/dev/null || echo 0) entries"
