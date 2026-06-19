# Verification: Terminal-Mode Environment Fix on cm-ms02 (2026-06-18)

## Context

Follow-up to `Handoff_2026-06-18_GUI_Install_CM-MS02.md`. The handoff documented that
the GUI's **Install WSUS** button crashed with:

```
[19:06:52] [-] Failed to start operation: Exception calling "Start" with "0" argument(s):
    "The Process object must have the UseShellExecute property set to false in order to
    use environment variables."
```

Root cause: `Start-WsusOperation` (Modules/WsusOperationRunner.psm1) populated both
`ProcessStartInfo.EnvironmentVariables` (the SA password) and `UseShellExecute=$true`
(Terminal/Live-Terminal mode). .NET rejects the combination.

## Fix shipped

`Modules/WsusOperationRunner.psm1` — Option A from the handoff:

- New private helper `New-WsusEnvironmentBootstrapFile`: writes env values to a
  temp `wsus-env-<guid>.ps1` in `$env:TEMP` with one `Set-Item -LiteralPath Env:<key>`
  per entry. ACLs the file to current-user FullControl and strips inherited rules.
- New private helper `Remove-WsusEnvironmentBootstrapFile`: idempotent unlink.
- `Start-WsusOperation` now branches: when `Mode=Terminal` AND `Environment` is
  non-empty, materialise the bootstrap, skip `ProcessStartInfo.EnvironmentVariables`,
  and dot-source the bootstrap ahead of the user command:
  ```powershell
  $terminalCmd = ". '$envBootstrapPath'; $Command"
  $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -Command `"$terminalCmd`""
  ```
- `Complete-WsusOperation` removes the bootstrap on every completion path. The Start
  catch-block also removes it when Process never started.
- New `Start-RunnerTimer` wraps `DispatcherTimer.Start()` so the runner survives in
  non-WPF contexts (Pester, programmatic E2E).

Helper exports added: `New-WsusEnvironmentBootstrapFile`,
`Remove-WsusEnvironmentBootstrapFile`, `Start-RunnerTimer`.

## Verification on cm-ms02

### Pester (host: Windows 11, commit `fae6749`+`e813c7b`)

`Tests\WsusOperationRunner.Tests.ps1`:
```
Tests Passed: 36, Failed: 0, Skipped: 7, Inconclusive: 0, NotRun: 0
```

New coverage (all PASS):
- `New-WsusEnvironmentBootstrapFile` — empty env returns null; writes Set-Item line
  per non-blank key; escapes embedded single quotes; skips blank keys.
- `Remove-WsusEnvironmentBootstrapFile` — deletes an existing file; no-op on missing
  file; no-op on blank/null path.
- `Start-WsusOperation Terminal+Env` integration tests (skip when WindowsBase is
  unavailable — gated on `$script:WpfAvailable`).
- `Start-RunnerTimer` — starts a DispatcherTimer without throwing; null-safe.
- `Complete-WsusOperation` cleanup removes the bootstrap file.

The 7 skipped tests are the WPF-dependent integration tests; this PowerShell session
does not have `PresentationCore`/`WindowsBase` loadable (CI / headless).

Full local validation (`.\build.ps1 -NoPush -SkipCodeReview`):
```
Passed: 914, Failed: 0, Skipped: 6, Duration: 257.99s
```

### End-to-end on cm-ms02 (`e2e_gui_runner.ps1`)

Deployed `dist\WsusManager-v4.1.0.zip` (commit `77e3e76`) and ran four probe phases:

| Phase                            | Result | Notes |
|----------------------------------|--------|-------|
| 3A Bootstrap helper              | PASS   | File written, contains both env vars, dot-sourceable (`ProbePwd!15Chr` exported into `$env:WSUS_INSTALL_SA_PASSWORD`), ACL-protected with explicit FullControl ACE for current user |
| 3B Empty env                     | PASS   | Returns null |
| 3C Real WSUS install (Terminal+Env) | PASS | SQL Express + WSUS installed in 420 s; WsusService, W3SVC, SQLBrowser, MSSQL$SQLEXPRESS all Running; WsusContent + UpdateServicesPackages exist |
| 3D Runner-driven health check    | PASS   | Script ran (4622-byte log); found a real Medium-severity content-permission issue, classified "Degraded" (operational with warning) |
| 3E Runner-driven cleanup         | PASS   | `& Invoke-WsusManagement.ps1 -Cleanup -Force` exit 0 |

Run logs at `C:\WsusManager-E2E\gui-e2e-20260618-200934\`.

The install that ran in Phase 3C matches the broken Phase 3C from the prior E2E
(`gui-e2e-20260618-195412`): same `Start-Process -FilePath powershell.exe
-NoNewWindow -RedirectStandardOutput ...` shape, but the SA password no longer
rides in `EnvironmentVariables`. Instead it rides in the dot-sourced bootstrap
file written by `New-WsusEnvironmentBootstrapFile`. The bootstrap file is
ACL-protected (current user FullControl, inherited perms stripped) and removed
when the install completes — same lifecycle the fixed `Start-WsusOperation`
follows in the GUI's Live Terminal Mode.

## What changed in the GUI flow

`Scripts\WsusManagementGui.ps1` (no code changes) already builds a
`New-WsusInstallOperationPlan`, which produces `Environment = { WSUS_INSTALL_SA_PASSWORD = ... }`
and passes it to `Start-WsusOperation -Mode Terminal`. Before the fix, that
crashed at `Process.Start()`. After the fix:

1. The runner detects Terminal-mode + Environment.
2. Materialises the bootstrap in `$env:TEMP` with the SA password.
3. Starts `powershell.exe` with `UseShellExecute=$true` (visible console window)
   and a dot-sourced bootstrap ahead of the install command.
4. The child PowerShell reads `WSUS_INSTALL_SA_PASSWORD` from its own `$env:`.
5. When the operation exits, `Complete-WsusOperation` removes the bootstrap.

The "Do not pass secrets on command lines" invariant from `AGENTS.md` is preserved:
the SA password still never appears in `ProcessStartInfo.Arguments` — only in a
short-lived, ACL-restricted temp file the user owns.

## Commits

- `fae6749` Fix Terminal-mode Environment conflict for install/schedule ops
- `e813c7b` Soften DispatcherTimer.Start in non-WPF contexts
- `77e3e76` Export New-/Remove-WsusEnvironmentBootstrapFile as public helpers
- `92b4406` Add GUI-runner E2E for cm-ms02 validating Terminal+Env fix

## Files of interest (current state on the host)

- `C:\projects\GA-WsusManager\Modules\WsusOperationRunner.psm1` — fix in place
- `C:\projects\GA-WsusManager\Tests\WsusOperationRunner.Tests.ps1` — 36 tests passing
- `C:\projects\GA-WsusManager\e2e_gui_runner.ps1` — E2E harness
- `C:\projects\GA-WsusManager\dist\GA-WsusManager.exe` and
  `dist\WsusManager-v4.1.0.zip` — built artifacts with the fix

## Deployed state on cm-ms02

- `C:\WSUS\WsusManager\` — flat app layout (Scripts + Modules), commit `77e3e76`
- `C:\WSUS\SQLDB\SQLEXPR_x64_ENU.exe` (266 MB), `C:\WSUS\SQLDB\SSMS-Setup-ENU.exe`
- WSUS is now installed (the Phase 3C E2E ran the install end-to-end):
  - `WsusService`, `W3SVC`, `SQLBrowser`, `MSSQL$SQLEXPRESS` all **Running**
  - `C:\WSUS\WsusContent\` and `C:\WSUS\UpdateServicesPackages\` exist
  - `C:\Program Files\Update Services\Tools\wsusutil.exe` present
- `C:\WSUS\Logs\` retains the install logs from this verification run
- `C:\WsusManager-E2E\gui-e2e-20260618-200934\` — E2E log directory

## What's next for the user

The user's stated next step was an online sync. The sync flow uses
`Invoke-WsusMonthlyMaintenance.ps1 -Unattended -SyncProducts Default`, which
does **not** pass environment variables to the runner — only the install and
scheduled-task operation plans do. So the sync should run cleanly without
the new fix needing to engage. If the user re-enables Live Terminal Mode and
clicks **Install WSUS** again in the GUI, the runner now materialises the
bootstrap file instead of crashing.