<h1>omarchy-protondrive</h1>

A native, Dropbox-style Proton Drive integration for [Omarchy](https://omarchy.org/) — a bar
widget with per-account status and storage, backed by real FUSE mounts
(`rclone mount --vfs-cache-mode=full`), built to handle **multiple Proton
Drive accounts at once**.

This is a proof of concept: the Quickshell plugin (bar icon + dropdown
panel), the account-management CLI, and the systemd/rclone plumbing are all
real and independently tested (see [Verification](#verification)), but no
one has yet run it end-to-end against a live Proton Drive account. See
[PLAN.md](PLAN.md) for what's built, what's stubbed, and what's next.

## Why this shape

Omarchy's own Dropbox integration (`omarchy-install-service-dropbox`) is a
thin wrapper around the official proprietary `dropboxd` — it installs that
binary plus `nautilus-dropbox` and adds one bar plugin around its systray
icon. There's no equivalent official Linux client for Proton Drive, so
this plugin owns more of the stack itself:

- **Sync engine**: [rclone](https://rclone.org/protondrive/)'s `protondrive`
  backend handles Proton's SRP login and client-side encryption — not
  reimplemented here.
- **Filesystem**: `rclone mount` per account, giving on-demand FUSE access
  with a local VFS cache, the same shape as Dropbox's Smart Sync rather than
  a full duplicate local copy.
- **Multi-account**: each account gets its own rclone config file, mount
  point, and `systemd --user` unit — see [PLAN.md](PLAN.md#multi-account-design)
  for why that's cheap here even though it isn't for Dropbox's own client.
- **Shell integration**: one Quickshell `bar-widget` plugin (bar icon +
  panel), following the same structure as the first-party Dropbox and CPU
  plugins under `/usr/share/omarchy/shell/plugins/panels/`.

## Install

```bash
git clone <this-repo> && cd omarchy-protondrive
omarchy plugin add "$(pwd)" --enable   # or: omarchy plugin add <git-url> --enable
./install.sh                            # installs rclone + helper scripts, enables the widget
```

Add an account (also reachable from the panel's "Add a Proton Drive
account" row, which opens the same command in a terminal):

```bash
protondrive-accountctl add personal "Personal"
systemctl --user enable --now omarchy-protondrive@personal.service
```

Add as many accounts as you like — `personal`, `work`, whatever id you pick
— each gets its own row in the panel, its own mount under `~/ProtonDrive/`,
and its own pause/resume toggle.

Remove with `./uninstall.sh` (leaves your accounts and synced files in
place; see the script for what it does and doesn't touch).

## Layout

```
manifest.json              Quickshell plugin manifest (kind: bar-widget)
Panel.qml                  Bar icon + dropdown panel (accounts list, add-account row)
Service.qml                Account state, IPC to the helper scripts below
Model.js                   Pure JS: status parsing, formatting — unit tested under Node
ProtonDriveIcon.qml         Bar icon glyph
bin/protondrive-status      Read-only: one JSON object describing every account
bin/protondrive-accountctl  add / remove / pause / resume / list accounts
bin/protondrive-mount       ExecStart for the per-account systemd unit (rclone mount)
systemd/omarchy-protondrive@.service   Per-account templated user unit
install.sh / uninstall.sh
test/                       Node unit tests (Model.js) + a bash smoke test (protondrive-status --demo)
```

## Verification

Everything below was actually run against this repo, on an Omarchy machine,
not just written and assumed correct:

```bash
node --test test/model.test.js      # 8/8 pass — status parsing & formatting
bash test/status-fixture.sh         # protondrive-status --demo and --no-config both return valid JSON
python3 -m py_compile bin/protondrive-status bin/protondrive-accountctl
omarchy-plugin-validate .           # passes the real registry validator (manifest schema,
                                     #   entry points, id namespace, no symlinks)
```

The QML was also run through `qmllint` against Omarchy's own shell tree. It
reports the same category of "unresolved `qs.*` import" warnings — and zero
hard errors — as linting the real, shipped Dropbox plugin the identical way;
that module resolution needs a running Quickshell process, not just an
import path, so it's not something `qmllint` alone can close out. What it
can't tell you, and what nobody has done yet, is confirm the panel actually
renders and reacts correctly inside a live `omarchy-shell` — that's the
first thing to check by hand before this stops being a proof of concept.

## Design docs

The reasoning behind the architecture — why rclone, why FUSE-mount over a
synced folder, the multi-account model, and the phased roadmap — is in
[PLAN.md](PLAN.md).

## License

MIT — see [LICENSE](LICENSE).
