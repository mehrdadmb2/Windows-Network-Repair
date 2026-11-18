# GitHub Actions build fix — v2.0.2

## Root cause

`Build-Executable.ps1` is a PowerShell script. After it invokes PS2EXE, `$LASTEXITCODE` can contain the exit code of a native compiler process used internally by PS2EXE. A non-zero value there does **not** mean the PowerShell build script failed. The previous workflow incorrectly checked that stale value after the script call, causing a false failure even though the EXE had been created and its PE header verified.

## Correction

- PowerShell script invocation is now validated through terminating errors (`try/catch`) and output-file checks.
- `$LASTEXITCODE` is retained only after native commands such as `git` and `node --check`.
- The build step verifies the EXE exists, is at least 50 KB, and has no `.exe.config` sidecar.
- The packaging step verifies the four release files and checks the manifest version/tag.

## Publish

Replace the repository contents with this package, push to `main`, then run **Build Windows EXE and publish release** with `release_tag = v2.0.2`. Do not reuse the older `v2.0.1` tag for a different commit.
