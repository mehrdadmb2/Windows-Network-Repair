# Changelog

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
