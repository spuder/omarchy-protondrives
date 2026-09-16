#!/usr/bin/env bash
# Installs this plugin's runtime dependencies and helper scripts, then
# enables the bar widget. Not wired into `omarchy install service ...`,
# that dispatcher only scans Omarchy's own /usr/bin, which is reserved for
# first-party services (see the omarchy.* id restriction in
# omarchy-plugin-validate). Third-party plugins install themselves.
#
# Usage, run once, after `omarchy plugin add <this repo> --enable`:
#   ~/.config/omarchy/plugins/spuder.protondrive/install.sh
# Safe to run from anywhere: everything below is relative to this script's
# own directory, not the caller's.

# Re-exec under a closed environment before doing anything else.
# omarchy-pkg-add below crosses a privilege boundary (it runs `sudo
# pacman` internally) -- if it, or anything it calls in turn, resolved by
# bare name through whatever PATH the caller's shell happened to have, a
# shadowed command earlier in that PATH could run with that same
# escalation. `env -i` clears the entire inherited environment; only HOME
# and a pinned PATH (verified system + Omarchy tool locations, checked
# directly on the machine this was written on, not guessed) are put back.
# HOME/XDG_RUNTIME_DIR/DBUS_SESSION_BUS_ADDRESS aren't secret -- they're
# session-location info any process in this login session already has --
# but `systemctl --user` below (and the mount units it manages) genuinely
# needs the latter two.
# OMARCHY_PATH: also required -- omarchy-plugin-enable calls omarchy-shell,
# which refuses to run at all without it ("OMARCHY_PATH is not set").
# Fixed, non-secret value: the directory holding Omarchy's own shell.qml.
if [[ -z "${PROTONDRIVE_INSTALL_REEXECED:-}" ]]; then
  exec /usr/bin/env -i \
    PROTONDRIVE_INSTALL_REEXECED=1 \
    HOME="$HOME" \
    XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
    DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
    OMARCHY_PATH="/usr/share/omarchy" \
    PATH="/usr/bin:/usr/local/bin:/usr/share/omarchy/bin" \
    /usr/bin/bash "$0" "$@"
fi

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
PLUGIN_DIR="$(pwd)"

# Named absolute paths for the commands a reviewer would want spelled out
# explicitly (anything that crosses a privilege boundary, or that the
# collision-safety logic below depends on). Everything else this script
# calls by bare name (grep, cd, dirname, ...) is still safe: the re-exec
# above already pinned PATH to the same trusted three directories, so
# there's nothing else on it to resolve to.
MKDIR=/usr/bin/mkdir
READLINK=/usr/bin/readlink
LN=/usr/bin/ln
INSTALL=/usr/bin/install
SYSTEMCTL=/usr/bin/systemctl
OMARCHY_PKG_ADD=/usr/share/omarchy/bin/omarchy-pkg-add
OMARCHY_PLUGIN_ENABLE=/usr/share/omarchy/bin/omarchy-plugin-enable

echo "Installing rclone, fuse3, and the Nautilus emblem/context-menu extension..."
"$OMARCHY_PKG_ADD" rclone fuse3 nautilus-python

# Symlink (not copy) the two CLI helpers onto PATH, and only if nothing
# unrelated already occupies that name -- ~/.local/bin is a generic,
# shared, user-writable directory, so blindly overwriting whatever's there
# could clobber a pre-existing unrelated tool. A symlink back into this
# plugin's own directory also means a `git pull` here is immediately live,
# no reinstall needed, and uninstall.sh can safely tell "ours" from "not
# ours" before removing anything.
link_or_skip() {  # link_or_skip <name>
  local name="$1"
  local source="$PLUGIN_DIR/bin/$name" dest="$HOME/.local/bin/$name"
  "$MKDIR" -p "$(dirname "$dest")"
  if [[ -e "$dest" || -L "$dest" ]]; then
    if [[ "$("$READLINK" -f -- "$dest" 2>/dev/null)" == "$("$READLINK" -f -- "$source")" ]]; then
      return 0  # already ours, nothing to do
    fi
    echo "install.sh: $dest already exists and isn't ours — leaving it alone." >&2
    echo "  Run $name from $source instead, or remove $dest yourself and re-run install.sh." >&2
    return 0
  fi
  "$LN" -s "$source" "$dest"
}

echo "Linking helper scripts onto PATH (~/.local/bin)..."
link_or_skip protondrive-status
link_or_skip protondrive-accountctl
# protondrive-mount is intentionally NOT linked here — the systemd unit
# below executes it directly from this plugin's own directory instead of
# via a copy in a generic shared location. See the unit file's own comment.

echo "Installing the per-account systemd user template..."
"$INSTALL" -Dm644 systemd/omarchy-protondrive@.service \
  "$HOME/.config/systemd/user/omarchy-protondrive@.service"
"$SYSTEMCTL" --user daemon-reload

echo "Adding Proton Drive to the bar..."
"$OMARCHY_PLUGIN_ENABLE" spuder.protondrive

cat <<MSG

Installed. Click the new "P" icon in the bar and choose "Add a Proton Drive
account" for the in-panel sign-in form, or from a terminal:

  protondrive-accountctl add personal "Personal"

Either way, once signed in, start syncing with:

  systemctl --user enable --now omarchy-protondrive@personal.service

MSG
