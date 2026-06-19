# Handoff: GUI "Install WSUS" Fails on cm-ms02 (2026-06-18)

## Scope of troubleshooting

- **VM being troubleshot**: `cm-ms02` (Hyper-V guest, 4 vCPU, 4 GB RAM, joined to `CMLab` internal switch at `192.168.61.5`)
- **Local host (VHOST)**: Windows 11 Pro, Hyper-V, repo at `C:\projects\GA-WsusManager` (commit `f34491c` before this report, then `5e97c39` after the first bug fix)
- **User account on cm-ms02**: `CM\Install` / `Server123!`
- **User account on cm-ms01**: `CM\dod_admin` / `Server123!`
- **App version on cm-ms02**: `dist\GA-WsusManager.exe` v4.1.0 (file version `4.2.x` in metadata, product `GA-WsusManager`)
- **App code on cm-ms02**: `C:\WSUS\WsusManager\` (flat layout — Scripts, Modules, docs, wiki directly under WsusManager)
- **WSUS state on cm-ms02 at start of session**: not installed. Install was attempted during the E2E and reported as "FAIL" by the E2E script, but actually **succeeded** silently (see "Background" below).
- **WSUS state on cm-ms02 at end of session**: installed and running. WsusService, W3SVC, SQLBrowser, MSSQL$SQLEXPRESS all Running. Internet via host WinNAT (CMLabNAT).

## User-reported failure (the one we're working on)

User clicks **Install WSUS** in the GUI with **Live Terminal Mode: On**. The GUI prints:

```
[19:06:52] [-] Failed to start operation: Exception calling "Start" with "0" argument(s): "The Process object must have the UseShellExecute property set to false in order to use environment variables."
```

This error replaced an earlier error the user got in the same flow:

```
[18:52:58] [-] Failed to start operation: Exception calling "ContainsKey" with "1" argument(s): "Key cannot be null. Parameter name: key"
```

Both errors come from `Start-WsusOperation` in `Modules\WsusOperationRunner.psm1` when invoked with the `install` operation plan while Live Terminal Mode is on.

## Background: how we got here

1. **2026-06-18 afternoon, earlier in this session**: ran a multi-launch E2E attempt on cm-ms02 from the new build. Seven of nine launch attempts failed at the pre-install or install-initiation step with various deploy-script bugs (path nesting, env-var propagation, parameter names). The seventh launched a real install, which actually completed (SQL Express + WSUS) inside the 5-10 minute install window, but my E2E script's `Start-Process` tracking reported an empty exit code so it labeled the install as "FAIL" and aborted the rest of the pipeline.
2. **Post-install cleanup**: I cleaned up the failed E2E artifacts and stopped reporting install failure.
3. **NAT and DNS**: set up WinNAT (`CMLabNAT`) on the host for the `192.168.61.0/24` subnet (cm-ms02 is on `192.168.61.5`), and changed cm-ms02's DNS to `8.8.8.8 / 1.1.1.1` (the original `192.168.61.3` couldn't resolve external names) so the VM can reach the internet. This was a prerequisite for the eventual online sync the user is preparing for.
4. **Flatten copy to cm-ms01 and cm-ms02**: copied the app and installers to `C:\WSUS\WsusManager\` and `C:\WSUS\SQLDB\` on both VMs in flat layout, with the SQL Express and SSMS installers staged. This was preparation for the next install path.
5. **User retried Install WSUS from the EXE on cm-ms02 and hit the first error** (Key cannot be null, timestamp 18:52:58). I reproduced, root-caused, fixed, and committed (commit `5e97c39`).
6. **User retried and hit the second error** (Start exception, timestamp 19:06:52). This report captures the handoff for both errors and the remaining underlying issue.

## Root cause of the first error (already fixed in commit `5e97c39`)

**File**: `Modules\WsusOperationRunner.psm1`, line 167.

**Cause**: The `$guardKey` expression used to detect double-completion of the operation assigned `$Context.Process.Id` directly, but `System.Diagnostics.Process.Id` is `int?` (nullable) and is `null` until `Start()` succeeds. When the install command failed to start (which is what was happening here, just with a different error), the catch block at line 396 called `Complete-WsusOperation`, and the null `Process.Id` was passed to `Hashtable.ContainsKey()` which throws `Key cannot be null. Parameter name: key`.

**Original code**:
```powershell
$guardKey = if ($Context.ContainsKey('Process') -and $null -ne $Context.Process) { $Context.Process.Id } else { [string]$Context.GetHashCode() }
if ($script:CompletedOperations.ContainsKey($guardKey)) { return }
```

**Fixed code**:
```powershell
$guardKey = if ($Context.ContainsKey('Process') -and $null -ne $Context.Process -and $null -ne $Context.Process.Id) { $Context.Process.Id } else { [string]$Context.GetHashCode() }
if ($script:CompletedOperations.ContainsKey($guardKey)) { return }
```

**Verification on cm-ms02 before/after deploy**:
- Before fix: `MethodInvocationException: Exception calling "ContainsKey" with "1" argument(s): "Key cannot be null. Parameter name: key"` at `Complete-WsusOperation, C:\WSUS\WsusManager\Modules\WsusOperationRunner.psm1: line 168`.
- After fix (copied to VM via PSSession): same call path returns `PSArgumentException: Cannot find type [System.Windows.Threading.DispatcherTimer]: verify that the assembly containing this type is loaded.` (a test-environment-only error because the repro runs without a WPF context; the real ContainsKey error is gone).
- Local Pester suite (`Tests\WsusArchitectureInterfaces.Tests.ps1`, `Tests\Integration.Tests.ps1`, `Tests\WsusHostEnvironment.Tests.ps1`): 84 passed, 0 failed.

## Root cause of the second error (the one the user is currently seeing)

**File**: `Modules\WsusOperationRunner.psm1`, line 367-383.

**Cause**: `Start-WsusOperation` builds a `ProcessStartInfo` with both:
- `Environment` hashtable parameter (line 310, filled from the install plan's `WSUS_INSTALL_SA_PASSWORD` secret env var)
- `Terminal` mode which sets `$psi.UseShellExecute = $true` (line 369)

`.NET Process.Start` rejects this combination with the exact error the user sees:

```
The Process object must have the UseShellExecute property set to false in order to use environment variables.
```

This is a fundamental conflict in `.NET ProcessStartInfo`:
- `UseShellExecute = true` — required for Terminal mode (visible console window)
- Passing `Environment` to `ProcessStartInfo.EnvironmentVariables` — only allowed when `UseShellExecute = false`

The install operation plan is the only one that passes `Environment` (for the SA password). All other operation plans (`cleanup`, `maintenance`, `diagnostics`, `restore`, `export`, `import`, `reset`) have empty `Environment` and don't trigger this error. So **the bug is specific to the install operation in Terminal mode**.

**Reproduction on cm-ms02 (after fix #1)**:
```
===ERROR===
Type: System.Management.Automation.MethodInvocationException
Message: Exception calling "Start" with "0" argument(s): "The Process object must have the UseShellExecute property set to false in order to use environment variables."

ScriptStackTrace:
at Start-WsusOperation, C:\WSUS\WsusManager\Modules\WsusOperationRunner.psm1: line 396
at <ScriptBlock>, <No file>: line 23
```

## Workaround for the user right now (no code change)

The user can complete the install from the GUI by toggling **Live Terminal Mode: Off** before clicking **Install WSUS**. This switches the runner to `Embedded` mode (line 373-382 of `WsusOperationRunner.psm1`) which uses `UseShellExecute = false` and properly carries `Environment` to the child process. The install will run with embedded log output instead of a visible console window.

Repro to confirm the workaround works:
```powershell
# In PSSession to cm-ms02
$secure = ConvertTo-SecureString 'Server123!' -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential('CM\Install', $secure)
$s = New-PSSession -VMName cm-ms02 -Credential $cred -ErrorAction Stop
Invoke-Command -Session $s -ScriptBlock {
    Import-Module 'C:\WSUS\WsusManager\Modules\WsusUtilities.psm1' -Force -DisableNameChecking
    Import-Module 'C:\WSUS\WsusManager\Modules\WsusOperationPlan.psm1' -Force -DisableNameChecking
    Import-Module 'C:\WSUS\WsusManager\Modules\WsusOperationRunner.psm1' -Force -DisableNameChecking
    $secureSaPassword = ConvertTo-SecureString 'TestPwd15Chr!123' -AsPlainText -Force
    $op = New-WsusInstallOperationPlan -InstallScriptPath 'C:\WSUS\WsusManager\Scripts\Install-WsusWithSqlExpress.ps1' -InstallerPath 'C:\WSUS\SQLDB' -SaUsername 'sa' -SaPassword $secureSaPassword
    $ctx = @{ ScriptRoot = 'C:\WSUS\WsusManager\Scripts'; SetOperationRunning = {param($v)}; UpdateButtonState = {} }
    # Mode 'Embedded' (not 'Terminal') avoids the UseShellExecute conflict
    $proc = Start-WsusOperation -Command $op.Command -Title $op.Title -Context $ctx -Mode 'Embedded' -TimeoutMinutes 180 -Environment $op.Environment
    Write-Host "OK PID=$($proc.Id)"
}
```

## Proper fix (not yet committed)

Two options. Recommend **Option A** because it preserves the Live Terminal UX the user already enabled by default (`$script:LiveTerminalMode = $true` at line 97 of `WsusManagementGui.ps1`).

### Option A (recommended): serialize the env var into a temp file and have the child script read it

1. In `Start-WsusOperation`, when `$Mode -eq 'Terminal'` and `$Environment.Count -gt 0`:
   - Write the env values to a temp file (e.g. `C:\Windows\Temp\wsus-env-<guid>.ps1`)
   - Inject `& { . $tempFile; <original command> }` into the command string
   - Set `Environment = @{}` on the ProcessStartInfo (so UseShellExecute=true still works)
   - Delete the temp file in the `Complete-WsusOperation` cleanup
2. No changes to install plan, no changes to install script, no changes to GUI.

### Option B: change the install plan to pass `-SaPassword` on the command line

The install script already accepts `-SaPassword` directly (it's the same parameter the install script's own non-interactive install code uses internally). The plan's `New-WsusInstallOperationPlan` could call `-SaPassword` instead of `-SaPasswordEnvVar`, and the runner would not need to pass `Environment`.

Drawback: violates the existing security pattern "Do not pass secrets on command lines" called out in `AGENTS.md` and the install plan's own design intent. The env-var pattern was added in plan 06 specifically to avoid this.

### Option C: ask the user to disable Live Terminal for install only

Simplest. Just document that install is the one operation that requires Embedded mode. Add a check in the GUI: when clicking "Install WSUS" with Live Terminal enabled, prompt: "Live Terminal Mode cannot pass the SA password environment variable to the install process. Switch to Embedded Mode for this operation?" and remember the preference for the session. No code change to the runner.

## What I did not do (out of scope for this report)

- **Did not run the full E2E again** — the E2E script is in `C:\projects\GA-WsusManager\e2e_cm-ms02.ps1` with `-DryRun` mode working, but the live E2E was halted at the user's request after 7+ launch attempts in this session revealed the deploy script was too brittle. The real install (SQL + WSUS) has actually happened on cm-ms02 — that was confirmed by direct service checks after the E2E script reported FAIL.
- **Did not commit the installer's behavior on cm-ms02 to git** — install state lives on the VM, not the repo. The repo is clean (commit `5e97c39` is HEAD).
- **Did not run a full online sync on cm-ms02** — that's the user's next planned step. Sync requires either a working install (now in place) and live internet (verified working after the NAT setup), but the sync itself goes through `Invoke-WsusMonthlyMaintenance.ps1 -SyncProducts Default` which has the same Terminal-mode + Environment limitation if the user enables Live Terminal. Same Option A/C applies.

## What to do next (recommended)

1. User retries **Install WSUS** with **Live Terminal Mode: Off** in the GUI. Captures the install log inline.
2. If the user wants the fix for real, pick **Option A** (cleanest, preserves UX) or **Option C** (simplest, one-line check). I can implement either in a follow-up session.
3. Once install is confirmed, run the GUI's online sync. If sync also fails with the Terminal-mode error (it shouldn't — sync doesn't take an env var), apply the same fix.

## Files of interest (current state on the host)

- `C:\projects\GA-WsusManager\Modules\WsusOperationRunner.psm1` — fixed in `5e97c39` (ContainsKey null guard), Terminal-mode conflict NOT YET fixed
- `C:\projects\GA-WsusManager\Modules\WsusOperationPlan.psm1` — `New-WsusInstallOperationPlan` (line 87) calls `New-WsusSecretEnvironment` which produces the Environment hashtable; same in `New-WsusScheduleOperationPlan` (line ~150) for scheduled task password
- `C:\projects\GA-WsusManager\Scripts\WsusManagementGui.ps1` — `$script:LiveTerminalMode = $true` at line 97 (default). `$useTerminal = $script:LiveTerminalMode -and -not $script:ForceEmbeddedMode` at line 3185. BtnLiveTerminal at line 3585 toggles the flag.
- `C:\projects\GA-WsusManager\Scripts\Install-WsusWithSqlExpress.ps1` — the install script; reads the SA password from the env var via `[Environment]::GetEnvironmentVariable($SaPasswordEnvVar)` (line ~348). Already supports both `-SaPassword` and `-SaPasswordEnvVar`.

## Deployed state on cm-ms02 (right now, end of session)

- `C:\WSUS\WsusManager\` — flat app layout, 6 scripts, 27 modules, commit `5e97c39`
- `C:\WSUS\SQLDB\SQLEXPR_x64_ENU.exe` (266 MB) and `C:\WSUS\SQLDB\SSMS-Setup-ENU.exe` (473 MB)
- `C:\WSUS\WsusContent\` and `C:\WSUS\UpdateServicesPackages\` exist (WSUS is installed)
- Services running: WsusService, W3SVC, SQLBrowser, MSSQL$SQLEXPRESS
- Internet: working (CMLabNAT, DNS 8.8.8.8/1.1.1.1)
- `C:\WSUS\Logs\` contains install logs from this session

## Deployed state on cm-ms01 (for the parallel VM)

- `C:\WSUS\WsusManager\` — flat app layout, 6 scripts, 27 modules, commit `5e97c39` (same)
- `C:\WSUS\SQLDB\SQLEXPR_x64_ENU.exe` and `C:\WSUS\SQLDB\SSMS-Setup-ENU.exe`
- WSUS not yet installed (no WsusService yet on this VM — verified during the copy step)
