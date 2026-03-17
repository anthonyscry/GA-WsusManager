# WSUS Manager Popup Smoke Checklist (Windows)

Use this checklist on a Windows host (PowerShell 5.1+, admin session) to verify popup behavior after the popup-handler hardening in `Scripts/WsusManagementGui.ps1`.

## Automated Startup E2E

You can run the automated startup popup probe test with:

```powershell
Invoke-Pester -Path .\Tests\StartupE2E.Tests.ps1 -Output Detailed
```

This test launches `Scripts\WsusManagementGui.ps1` in startup-probe mode and fails if startup error popups are detected.

## Scope

- Central popup wrapper (`Show-WsusPopup`)
- Duplicate popup suppression (`-SuppressDuplicateSeconds`)
- Confirmation dialog result handling (Yes/No)
- Safe dashboard refresh behavior (`Invoke-DashboardRefreshSafe`)

## Test Environment

1. Use a Windows machine or VM with GUI support.
2. Launch `Scripts\WsusManagementGui.ps1` as Administrator.
3. Keep `C:\WSUS\Logs\WsusOperations_YYYY-MM-DD.log` open in a text editor.

## Smoke Tests

1. Operation already running popup dedupe
   - Start any long operation (for example Diagnostics).
   - While it is running, click another operation button repeatedly for 2-3 seconds.
   - Expected: one "Operation In Progress" popup appears; repeated clicks during suppression window do not keep opening popups.

2. Online-only popup dedupe
   - Switch to Air-Gap mode (toggle status indicator to force manual Air-Gap).
   - Click `Online Sync` multiple times quickly.
   - Expected: one "Online Only" popup appears; repeated rapid clicks are suppressed.

3. Script-not-found popup dedupe
   - Temporarily rename `Scripts\Invoke-WsusManagement.ps1`.
   - Click an operation that depends on it more than once.
   - Expected: "Script Not Found" popup appears and does not spam repeatedly.
   - Restore the file name after test.

4. Module-not-found popup dedupe (schedule flow)
   - Temporarily rename `Modules\WsusScheduledTask.psm1`.
   - Open Schedule flow and attempt to create task.
   - Expected: one "Module Not Found" popup; repeated attempts within a few seconds do not spam.
   - Restore the file name after test.

5. Restore confirm dialog result handling
   - Open Restore, select a valid `.bak` file, click Restore.
   - Click `No`.
   - Expected: restore operation does not start.
   - Repeat and click `Yes`.
   - Expected: restore operation starts.

6. Deep Cleanup and Reset confirm dialogs
   - Click Deep Cleanup, then `No`.
   - Expected: no operation starts.
   - Click Deep Cleanup again, then `Yes`.
   - Expected: operation starts.
   - Repeat same pattern for Reset Content.

7. Input-validation popups (single popup each action)
   - Transfer: click Start Transfer with blank required path.
   - Install: set invalid installer path and click install.
   - Schedule: invalid time format, then missing username/password.
   - Expected: each invalid action shows one clear popup and blocks operation start.

8. Dashboard refresh hardening (no fatal popup)
   - In Settings, set SQL instance to an invalid value (for test only).
   - Trigger refresh via F5, Dashboard navigation, and wait for auto-refresh.
   - Expected: app remains responsive; no fatal popup; warning/error details go to log panel/log file.
   - Restore SQL instance value afterward.

## Pass Criteria

- No popup spam from repeated clicks in guarded flows.
- Yes/No confirmation logic behaves correctly (No cancels, Yes proceeds).
- Refresh-related failures do not crash the UI.
- Validation popups are clear and block unsafe operation starts.

## Notes

- Popup suppression windows are intentional for noisy paths (for example operation-in-progress, online-only, missing script/module).
- Suppression events are logged with "Popup suppressed (duplicate within ... s)" in daily log.
