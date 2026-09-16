# Security

This plugin runs unsandboxed inside the shared `omarchy-shell` process, per
Omarchy's own plugin-add warning. Review `Service.qml`, `Panel.qml`, and
everything under `bin/` yourself before installing it.

## Reporting a vulnerability

Open a GitHub issue on this repository, or a private security advisory via
GitHub's "Report a vulnerability" button under the Security tab, if the
issue shouldn't be public before a fix ships.

## Self-review process

This repository follows the `omarchy-plugin-security-review` process
(trust-boundary mapping, command/argument safety, credential and local-data
storage, network access, privilege/service/package changes, dependency/
release supply chain) before each Marketplace submission or update. It
complements, and does not replace, Marketplace validation, the Automated
Security Baseline, or maintainer review — no self-review or automated scan
certifies that this plugin is safe.

## Latest audit

- **2026-09-15** — commit `e44267d9bb301045c2017fd8c3e04b51085fc652` —
  **READY FOR SUBMISSION**. Fixed two low-severity, same-user input-
  validation gaps (embedded control characters in free-text account
  fields; a locally-written cache file missing the `0600` permissions
  every other state file in the same directory already has). Full
  findings table and record in [PLAN.md](PLAN.md#security-audit--2026-09-15).
