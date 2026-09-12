# Plan: native, multi-account Proton Drive for Omarchy

## Status of this repo (read this first)

This is v0.1, a proof of concept. Honestly:

**Real and tested:**
- `manifest.json` passes `omarchy-plugin-validate` (schema, entry points, id
  namespace, no symlinks).
- `Model.js`'s parsing/formatting logic — 8/8 Node unit tests.
- `bin/protondrive-status` — valid JSON in both `--demo` mode and against an
  empty/missing config (`test/status-fixture.sh`), plus a per-account quota
  cache (`CACHE_TTL_SECONDS`) so the panel's periodic refresh doesn't hit
  Proton's API live every ~30s per account — errors always recheck
  immediately regardless of the cache.
- `Panel.qml` / `Service.qml` / `ProtonDriveIcon.qml` — syntactically valid
  QML per `qmllint`, checked against the same baseline as the real,
  shipped Dropbox plugin (see README's Verification section for why that
  comparison is the right bar, given `qmllint` can't resolve Quickshell's
  own `qs.*` modules standalone).
- `protondrive-accountctl add`, hand-tested against the real rclone
  `protondrive` backend with deliberately bad credentials: prompts for
  id/display name/email/password/2FA/mailbox password, verifies the login
  with a live `rclone about` call rather than trusting `rclone config
  create`'s exit code (which, per rclone's own docs, silently defaults
  unanswered questions instead of prompting — it does **not** validate
  credentials on its own), and rolls back cleanly on failure with no
  orphaned state. Also caught and fixed: a bad password made `rclone about`
  hang the full timeout, and the resulting uncaught `TimeoutExpired`
  crashed past the rollback. Not yet tested with a real, working login.

**Also real and tested, installed live:** running inside an actual
`omarchy-shell` on the machine this was built on (`omarchy plugin add` +
`install.sh`, updated in place with `omarchy plugin update --yes` after
each fix) — the panel renders and its bar icon, click-to-open, and account
rows all work. What flushed out most of the bugs above was exactly this:
hands-on use, not just static checks.

**In-panel login form (Phase 4, done):** "Add account" is a real form now
— id, display name, email, password, optional 2FA, optional mailbox
password — not a terminal. The password goes over the spawned process's
stdin, never argv, mirroring the first-party network plugin's Wi-Fi
password handling exactly. `protondrive-accountctl add --json` reads one
JSON line from stdin and returns one JSON line, sharing the same
create+verify+rollback path (`perform_add`) the interactive terminal flow
already used and was tested against. This is *not* the official CLI's
browser-hand-off login (see below for why that isn't reachable from here)
— the password is still typed into our form, not Proton's own page — but
it is a proper native field instead of a CLI prompt.

**Not yet done — the actual gap between this and "finished":**
- Never completed a real, successful login — every live test so far
  (interactive and `--json`) exercised the failure path deliberately. A
  working account is needed to confirm the mount itself, the pause/resume
  toggle, and quota display end to end.
- No Nautilus emblem/context-menu extension yet (Phase 3 below).
- No conflict-resolution UI, no per-file "keep offline" pinning beyond
  rclone's own VFS cache (Phase 5).

## Why this shape

Omarchy's Dropbox integration wraps the official `dropboxd` binary — a
`bar-widget` plugin around its systray, `dropbox-cli`, and the official
`nautilus-dropbox` extension. No custom sync logic. There's no equivalent
official Linux client for Proton Drive, so this plugin has to own more:

1. **Sync/crypto**: [rclone's `protondrive` backend](https://rclone.org/protondrive/)
   handles Proton's SRP login and client-side (PGP-based) encryption. Not
   reimplemented here — that's not something to get subtly wrong. It's
   currently beta; uploads broke between roughly November 2025 and an
   early-2026 fix (missing block-verification tokens, a broken retry path).
   Pin a recent rclone version and watch for backend regressions. See
   "Official Proton Drive SDK/CLI" below — there's now a real official
   alternative worth tracking, but it doesn't do sync/mount yet, so rclone
   stays the sync engine for now.
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

## Official Proton Drive SDK/CLI (found 2026-09-09)

There is now an official Proton AG SDK and CLI:
[`ProtonDriveApps/sdk`](https://github.com/ProtonDriveApps/sdk), MIT
licensed, `cli/` built with Bun. It's a real step up on auth: browser-based
login (no password typed at a CLI prompt) with the session stored in the
OS secret store — `libsecret` on Linux — which is a materially better auth
UX than either rclone's SRP prompts or the terminal flow this plugin
currently uses. It also doesn't help with the actual job this plugin does:
**no sync command and no mount**, just one-shot `filesystem list/upload/
download/move/rename/trash` and sharing. The README explicitly says it's
"not production-ready for third-party use," with the interface still
changing and a crypto migration planned for late 2026/early 2027. It's also
a separate credential system from rclone's — adopting its login wouldn't
by itself fix rclone's, since they don't share a session.

Verdict: keep rclone mount as the sync/FUSE engine — nothing else does that
job today. Revisit this SDK once it's stable and (if it ever ships one) has
a sync/mount story of its own; until then it's most useful as the
legitimate direct-API path for share-link generation (Phase 3) once mature
enough to depend on.

**Checked directly whether its session could be reused by rclone instead of
building a new login flow — it can't.** rclone's protondrive provider
schema does have `client_uid` / `client_access_token` / `client_refresh_
token` / `client_salted_key_pass` fields, which looked promising, but
rclone's own docs label all four "internal use only" — they're where
rclone caches its *own* SRP session after a password login, not a
bring-your-own-token slot. Separately, the official CLI's on-disk state
(`~/.local/share/proton-drive-cli/clientUid.json`) turned out to hold only
a bare client id, not the session itself — the actual secret material
lives in the OS keyring under that CLI's own app identity, and Proton's
API commonly binds a session to the app that requested it, so a token
extracted from there would likely be rejected coming from rclone even if
extracted. Built the in-panel login form (above) instead.

## Prior art: schneipp/omarchy-proton-drive-plugin (found 2026-09-09)

A published, early-stage (5 commits, no version tags) Omarchy plugin:
[github.com/schneipp/omarchy-proton-drive-plugin](https://github.com/schneipp/omarchy-proton-drive-plugin).
Worth knowing about, and validates rather than replaces this approach:

- Built on the official CLI above (`proton-drive-cli-bin`, AUR), not
  rclone — inherits its browser-based login, launched (at the time this was
  checked) via `omarchy-launch-tui` rather than a hardcoded terminal
  binary. Briefly adopted that same launcher here for the terminal-based
  add-account flow, since it respects the user's actual configured
  terminal (`xdg-terminal-exec`) rather than assuming one — since
  superseded by the in-panel login form above, so no longer used, but
  worth remembering as the right way to open *any* terminal from a plugin
  if one is ever needed again.
- No FUSE mount: since the official CLI has none, it's an app-level
  browser/upload/download tool with a hand-rolled sync loop (diffing
  `activeRevision.claimedSize` / `claimedModificationTime` / `claimedDigests.
  sha1` between listings), not a `~/ProtonDrive` folder that behaves like a
  real filesystem. That's the actual ask this plugin exists to meet, and it
  isn't one.
- Single account only.

## Prior art: edbron/omarchy-cloud-drives PR #2 (found 2026-09-09)

A closer comparison than the other two: [edbron/omarchy-cloud-drives](https://github.com/edbron/omarchy-cloud-drives)
is a real rclone-based plugin (iCloud Drive, Google Drive, OneDrive) with
actual FUSE mounts via systemd user units — same core architecture as this
plugin. [PR #2](https://github.com/edbron/omarchy-cloud-drives/pull/2)
adds Proton Drive as a fourth provider, also via rclone's `protondrive`
backend, credentials also sent over stdin rather than argv/disk (same
pattern used here).

Checked the actual files, not just the PR description: every provider —
Proton Drive included — mounts at one **fixed path** (`~/Cloud/ProtonDrive`)
through a generic `PROVIDERS` table keyed by provider type, not by an
arbitrary account id. One slot per provider, so Proton Drive is
single-account here too, same structural limitation as the other two.
There's an unanswered comment on the PR itself asking "Does this support
multiple proton drive accounts?" — from `@spuder`, the same GitHub user
this machine's own `~/Code/omarchy` fork traces back to.

So across three independent Proton Drive plugins now surveyed — the
official-CLI-based one, this cloud-drives one, and Omarchy's own Dropbox
integration — multiple simultaneous accounts remains a gap nothing else
has closed. That's the case for continuing to build this rather than
switching to or forking any of them.

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
validate` passing. Done.

**Phase 2 — prove it live.**
- Done: `omarchy plugin add` + `install.sh` on the machine this was built
  on, bar icon and panel confirmed rendering and reacting inside a real
  `omarchy-shell`; kept current with `omarchy plugin update --yes` after
  each fix.
- Done, moved up from Phase 4: in-panel login form (id/display name/email/
  password/2FA/mailbox password), password over stdin never argv — see
  Status above.
- Still open: a real, successful `protondrive-accountctl add` against an
  actual Proton Drive account — every live test so far deliberately used
  bad credentials to exercise the failure/rollback path. Confirm `rclone
  about` reports usage/quota correctly and the mount survives
  reboot/suspend once one succeeds.
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

**Phase 4 — pinning.** (native login form done, moved to Phase 2 above)
- Per-file "always keep offline" pin, layered on top of rclone's VFS cache
  rather than replacing it — rclone doesn't have this concept natively.
- Conflict list surfaced in the panel when `rclone mount`'s own conflict
  handling produces a `.conflict` file.

**Phase 5 — packaging.**
- AUR package for the helper scripts + systemd unit, so `install.sh`
  collapses to `omarchy-pkg-add omarchy-protondrives`.
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
