#!/usr/bin/env bash
# Installs this plugin's runtime dependencies and helper scripts, then
# enables the bar widget. Not wired into `omarchy install service ...` —
# that dispatcher only scans Omarchy's own /usr/bin, which is reserved for
# first-party services (see the omarchy.* id restriction in
# omarchy-plugin-validate). Third-party plugins install themselves.
#
# Usage: ./install.sh   (run once, after `omarchy plugin add <this repo>`)
set -euo pipefail

echo "Installing rclone and the Nautilus emblem/context-menu extension..."
omarchy-pkg-add rclone nautilus-python

echo "Installing helper scripts to ~/.local/bin..."
install -Dm755 bin/protondrive-status "$HOME/.local/bin/protondrive-status"
install -Dm755 bin/protondrive-accountctl "$HOME/.local/bin/protondrive-accountctl"
install -Dm755 bin/protondrive-mount "$HOME/.local/bin/protondrive-mount"

echo "Installing the per-account systemd user template..."
install -Dm644 systemd/omarchy-protondrive@.service \
  "$HOME/.config/systemd/user/omarchy-protondrive@.service"
systemctl --user daemon-reload

echo "Adding Proton Drive to the bar..."
omarchy-plugin-enable spencerowen.protondrive

cat <<MSG

Installed. Add your first account with:

  protondrive-accountctl add personal "Personal"

or click the new Proton Drive icon in the bar and choose "Add a Proton Drive
account" — either opens an interactive rclone login in a terminal. Once
signed in, start syncing with:

  systemctl --user enable --now omarchy-protondrive@personal.service

MSG
