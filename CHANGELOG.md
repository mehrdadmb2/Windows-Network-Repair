# Changelog

## 2.0.2 — 2026-11-18

- Fixed a false GitHub Actions failure after a successful PS2EXE compile: the workflow no longer checks the stale `$LASTEXITCODE` value after invoking PowerShell scripts.
- Kept `$LASTEXITCODE` checks only immediately after native commands such as Git and Node.js, where that variable is meaningful.
- Added independent post-build validation of the EXE file, minimum size and absence of a `.config` sidecar inside the workflow.
- Added independent post-packaging checks for all release files and for version/tag consistency in `release-manifest.json`.
- Updated package, in-app report and release guide version references to `2.0.2`.

## 2.0.1 — 2026-11-18

- Fixed the release workflow so both version-tag pushes and manual `workflow_dispatch` runs publish a GitHub Release.
- Added a required semantic release-tag input for manual runs; the release action creates the tag when it does not exist and updates existing release assets safely.
- Added tag/commit consistency checks to prevent binaries built from one commit being attached to a tag pointing at another commit.
- Upgraded release workflow actions to maintained Node.js 24-compatible major versions.
- Added post-publish GitHub API verification for all four release assets; a green run now requires the EXE, source archive, release manifest and checksum file to be visible.
- Removed PS2EXE `-longPaths` from the one-file build because it generated an adjacent `.exe.config` file.
- Added PE-header, minimum-size, bundle syntax and no-sidecar checks before packaging.
- Added a curated source ZIP, release manifest and SHA-256 checksums; user logs, runtime data, local backups and nested ZIP archives are excluded.
- Added Dependabot monitoring for GitHub Actions dependencies.
- Updated the in-app and package version to `2.0.1`.


## 2.0.0 — 2026-11-17

- Reworked the primary option 3 workflow: real pre-change snapshot, verified rollback backup, ordered settings changes, independent action verification, post-change sampling and JSON audit report.
- Added standalone live monitoring (option 10), network connectivity checks and richer system / adapter / service telemetry.
- Added exact registry value snapshots so rollback restores both existing values and values that were absent before the change.
- Improved unsupported API handling: unsupported adapter-binding operations are explicitly marked SKIP rather than being reported as a generic failure.
- Added a responsive GitHub Pages dashboard for importing and comparing real reports locally in the browser.
- Added Windows EXE build automation and automatic GitHub Release packaging.
- Documented Windows / PowerShell compatibility and the security consequences of insecure SMB guest access and reduced SMB signing.
- Added Group Policy preflight blockers and fail-fast execution to avoid risky partial option 3 changes.
- Improved fixed-interval live sampling and binding-restore API fallback.
- Kept compatibility with v1 registry-export backup snapshots and their legacy folder.
- Expanded dashboard telemetry with gateway/DNS probes, firewall groups and service/adapter health.
- Added CI syntax checks for all PowerShell files and the dashboard JavaScript; pinned PS2EXE 1.0.18 for repeatable builds.
