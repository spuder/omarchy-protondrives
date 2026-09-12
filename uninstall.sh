#!/usr/bin/env bash
# Stops every configured account's mount unit, disables the bar widget, and
# removes the helper scripts and systemd unit this plugin installed.
# Leaves ~/.config/omarchy-protondrive (accounts, rclone configs) and any
# synced files under ~/ProtonDrive untouched — remove those yourself once
# you've confirmed you don't need them.
set -euo pipefail

if command -v protondrive-accountctl >/dev/null 2>&1; then
  while IFS=$'\t' read -r id _rest; do
    [[ -n $id ]] || continue
    systemctl --user disable --now "omarchy-protondrive@${id}.service" 2>/dev/null || true
  done < <(protondrive-accountctl list 2>/dev/null | grep -v '^No accounts' || true)
fi

omarchy-plugin-disable spuder.protondrive || true

rm -f "$HOME/.local/bin/protondrive-status" \
      "$HOME/.local/bin/protondrive-accountctl" \
      "$HOME/.local/bin/protondrive-mount" \
      "$HOME/.config/systemd/user/omarchy-protondrive@.service"
systemctl --user daemon-reload

echo "Uninstalled. Your accounts and synced files were left in place:"
echo "  ~/.config/omarchy-protondrive"
echo "  ~/ProtonDrive"
