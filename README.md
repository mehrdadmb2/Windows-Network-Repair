# Windows Network Repair Pro

Capability-aware PowerShell utility for Windows 7/8/8.1/10/11 that focuses on three legacy SMB compatibility settings while detecting OS, architecture, hardware and available APIs before making changes.

## Main fixes

1. Disable Client for Microsoft Networks binding on supported Windows versions.
2. Enable `AllowInsecureGuestAuth` (including the policy location on modern Windows).
3. Disable the SMB client signing requirement (`RequireSecuritySignature=0`).

The tool creates rollback snapshots, verifies changes, logs operations and reports when a feature is unavailable instead of using unsafe fallbacks.

## Files

- `NetworkRepair.cmd` - elevated launcher.
- `NetworkRepair.ps1` - main application.
- `Restore.cmd` / `Restore.ps1` - restore utility.
- `Modules/` - console, detection, logging, backup, diagnostics and three-fix logic.
- `Backup/` - backup snapshots.
- `Logs/` - logs and reports.

## Run

Right-click `NetworkRepair.cmd` -> **Run as administrator**.

## Safety

The three requested SMB compatibility changes can reduce security. Use them for controlled/legacy-device scenarios, not as a blanket hardening bypass. SMB1 and insecure guest access are legacy compatibility features.
