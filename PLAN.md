# Plan: native, multi-account Proton Drive for Omarchy

## Status of this repo (read this first)

This is v0.1, a proof of concept. Honestly:

**Real and tested:**
- `manifest.json` passes `omarchy-plugin-validate` (schema, entry points, id
  namespace, no symlinks).
- `Model.js`'s parsing/formatting logic — 8/8 Node unit tests.
- `bin/protondrive-status` — valid JSON in both `--demo` mode and against an
  empty/missing config (`test/status-fixture.sh`).
- `Panel.qml` / `Service.qml` / `ProtonDriveIcon.qml` — syntactically valid
  QML per `qmllint`, checked against the same baseline as the real,
  shipped Dropbox plugin (see README's Verification section for why that
  comparison is the right bar, given `qmllint` can't resolve Quickshell's
  own `qs.*` modules standalone).

**Not yet done — the actual gap between this and "finished":**
- Never run inside a live `omarchy-shell`. The panel's layout, keyboard
  navigation, and IPC handler are modeled closely on the first-party Dropbox
  plugin's, but "closely modeled" is not "confirmed working."
- Never run against a real Proton Drive account. `rclone`'s `protondrive`
  backend is beta and has broken before (see below) — `protondrive-accountctl
  add`'s `rclone config create ... protondrive` call needs a live login to
  prove out.
- No Nautilus emblem/context-menu extension yet (Phase 3 below).
- No in-panel login form — "Add account" currently shells out to a terminal
  running an interactive `rclone config create`, because Proton's SRP + 2FA
  + mailbox-password flow has no browser hand-off to build a native form
  around yet (Phase 4).
- No conflict-resolution UI, no per-file "keep offline" pinning beyond
  rclone's own VFS cache (Phase 4/5).

## Why this shape

Omarchy's Dropbox integration wraps the official `dropboxd` binary — a
`bar-widget` plugin around its systray, `dropbox-cli`, and the official
`nautilus-dropbox` extension. No custom sync logic. There's no equivalent
official Linux client for Proton Drive, so this plugin has to own more:

1. **Sync/crypto**: [rclone's `protondrive` backend](https://rclone.org/protondrive/)
   handles Proton's SRP login and client-side (PGP-based) encryption. Not
   reimplemented here — that's not something to get subtly wrong. It's
   currently beta; uploads broke between roughly November 2025 and an
   early-2026 fix (missing block-verification tokens, a broken retry path),
   and there's an open effort to align the backend with Proton's own
   upcoming official SDK (targeted late 2026/2027, JS/C# only — no native
   Linux SDK is coming from Proton itself). Pin a recent rclone version and
   watch for backend regressions.
2. **Filesystem**: `rclone mount --vfs-cache-mode=full` per account — FUSE,
   on-demand fetch, local cache for pinned/recently-used files. Chosen over
   `rclone bisync` (still beta, periodic reconciliation rather than
   continuous two-way sync) to get the Dropbox Smart Sync feel rather than a
   full duplicate local copy.
3. **Shell surface**: one Quickshell `bar-widget` plugin (`Panel.qml` is
   both the bar icon and the dropdown, per the pattern in
   `/usr/share/omarchy/shell/plugins/panels/dropbox/`). `manifest.json`'s
   `schema` only covers plugin-wide settings (refresh interval, mount root,
   show-quota) — the account list itself is richer structured data that
   belongs in the daemon-owned `~/.config/omarchy-protondrive/accounts.json`,
   not in `shell.json`'s per-widget settings blob.
4. **File-manager surface**: out of Quickshell's reach — it's compositor/
   shell-level, not GTK. Needs a separate Nautilus extension (Phase 3).

## Multi-account design

The user-facing question that shaped this: *does Omarchy's Dropbox plugin
handle multiple accounts?* No — the official Dropbox Linux client has never
supported multiple accounts natively (confirmed against the workarounds
people hand-roll: separate `$HOME`s per `dropboxd` instance, or tools like
Maestral's `--config-name`), and Omarchy's plugin just wraps that client, so
it inherits the limitation.

Because this plugin isn't wrapping a proprietary single-account client,
multi-account is mostly bookkeeping:

- Each account gets a **fully separate rclone config file**
  (`~/.config/omarchy-protondrive/<id>/rclone.conf`), not shared sections
  in one file. Removing an account is a directory removal; a corrupted or
  revoked session for one account can't touch another.
- Each account gets its **own `rclone mount` process**, via the templated
  `omarchy-protondrive@<id>.service` unit, rather than multiplexing several
  mounts through one `rclone rcd`. Costs a little more memory; buys crash
  isolation (`work`'s mount hanging doesn't take `personal` down with it).
- Each account gets its **own mount point** (`~/ProtonDrive/<Display
  Name>/`), so file-manager bookmarks and Nautilus emblem resolution can
  key off path prefix alone.
- `protondrive-status`'s account objects and `accounts.json` are keyed by
  `id` throughout — the panel, the CLI, and (later) the conflict/pin state
  all use `(account_id, path)`, never bare `path`.
- One real cost of doing it this way: Proton Drive's API is
  reverse-engineered, not official, so N accounts means N independent
  pollers hitting it (`--poll-interval=1m` per mount, currently). Don't
  scale polling frequency linearly with account count — that risks
  rate-limiting or lockouts an official API wouldn't have.

## Roadmap

**Phase 1 — this repo.** Manifest + bar/panel plugin, account CLI, systemd
template, install/uninstall scripts, unit + smoke tests, `omarchy-plugin-
validate` passing. Done, unverified end-to-end (see Status above).

**Phase 2 — prove it live.**
- `omarchy plugin add` this repo for real, enable it, confirm the bar icon
  and panel render and react (click, hover, keyboard nav) inside an actual
  `omarchy-shell`.
- `protondrive-accountctl add` against a real Proton Drive account; confirm
  `rclone about` reports usage/quota correctly and the mount survives
  reboot/suspend.
- Add `docs/bar.png` and `docs/panel.png` (the README references screenshots
  nowhere yet — add them once there's a real render to capture).

**Phase 3 — file manager.**
- `nautilus-python` extension: emblems for synced / syncing / cloud-only /
  error, keyed by which mount point a file lives under (falls out of the
  per-account-mount-point design above almost for free).
- Context menu action: copy a Proton Drive share link (needs the sharing
  endpoints rclone's backend exposes, or a direct API call if it doesn't).
- GTK bookmark per account in `~/.config/gtk-3.0/bookmarks`.
- Thunar has no emblem/info-provider API — a `thunar-custom-actions` entry
  can cover the context-menu action there, but not status overlays.

**Phase 4 — native login + pinning.**
- Replace the terminal-based "Add account" with an in-panel form once
  there's a safe way to drive `rclone config create`'s prompts (username,
  password, 2FA, mailbox password) from QML without the plugin process
  itself ever holding the password in memory longer than the single RPC
  call needs.
- Per-file "always keep offline" pin, layered on top of rclone's VFS cache
  rather than replacing it — rclone doesn't have this concept natively.
- Conflict list surfaced in the panel when `rclone mount`'s own conflict
  handling produces a `.conflict` file.

**Phase 5 — packaging.**
- AUR package for the helper scripts + systemd unit, so `install.sh`
  collapses to `omarchy-pkg-add omarchy-protondrive`.
- CI: run `test/model.test.js`, `test/status-fixture.sh`, and `omarchy-
  plugin-validate` on every push.

## Security notes

- Plugins run **unsandboxed** inside the long-lived `omarchy-shell` process
  — reviewed before enabling, per Omarchy's own plugin-add warning. Nothing
  here is exempt from that; review `Service.qml` and the `bin/` scripts
  before trusting them.
- `protondrive-accountctl` writes `accounts.json` atomically (temp file +
  `os.replace`) and refuses a symlinked target or state directory, matching
  the defensive pattern the first-party CPU plugin's `state-dir-safety.sh`
  test checks for.
- Per-account directories are created `0700`; the `env` file consumed by
  systemd is `0600`.
- Secrets: rclone's own config-file encryption (`rclone config` with a
  config password) is not yet wired to the desktop keyring here — v0.1's
  per-account `rclone.conf` files are protected only by directory
  permissions. Routing the config password through `libsecret`/
  `gnome-keyring` via `rclone`'s `--password-command` is a Phase 2/3 item,
  not yet done.
