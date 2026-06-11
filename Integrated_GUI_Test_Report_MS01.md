# Integrated_GUI_Test_Report_MS01

## Executive summary

Integrated GUI and WSUS workflow testing was executed inside Hyper-V VM `MS01` using files staged through `\\VHOST1\VM-Staging`, mapped in the VM to `Z:`, and copied locally to `C:\Temp\App`.

This pass covered:
- host-to-VM staging
- GUI launch from multiple paths and startup conditions
- full WSUS + SQL Express install inside `MS01`
- post-install GUI navigation and diagnostics
- import/restore workflow using a locally-generated WSUS export set
- client access testing from `WS01` to the WSUS server on `MS01`
- client registration and scan/reporting validation from `WS01`
- attempted upstream sync + downstream update-readiness validation on `MS01`

High-level result:
- GUI launch and post-install navigation in `MS01`: **Pass**
- full SQL Express + WSUS install in `MS01`: **Pass**
- import workflow: **Pass**
- restore DB workflow: **Pass**
- `WS01` HTTP and port access to `MS01` WSUS: **Pass**
- `WS01` registration and scan/reporting against `MS01` WSUS: **Pass**
- targeted Windows 11 / .NET approval test on `MS01`: **Pass**
- `WS01` receives the approved updates as assigned: **Pass**
- `WS01` sees the controlled approval set as newly installable: **No (evaluated installed/satisfied by WUA)**
- newer Defender platform candidate approval produced an installable update on `WS01`: **No**

## Environment details

- Hyper-V host: `VHOST1`
- Target WSUS VM: `MS01`
- Client VM: `WS01`
- Domain: `identitylab.local`
- VM test user: `identitylab\dod_admin`
- Host staging share: `\\VHOST1\VM-Staging`
- VM mapped drive: `Z:`
- Local application path in VM: `C:\Temp\App`
- Alternate path tested: `C:\Temp\App With Spaces`
- App version tested: `GA-WsusManager.exe` file version `4.0.5.0`

## Staging details

### Host-side staging path used
- `C:\VM-Staging\GA-WsusManager`

### VM mapped drive used
- `Z:` mapped to `\\VHOST1\VM-Staging`

### Local VM application path used
- `C:\Temp\App`

### Staging validation
- Host robocopy to staging: **Pass**
- MS01 mapping of `Z:`: **Pass**
- MS01 local copy to `C:\Temp\App`: **Pass**
- Source and destination item counts matched during copy: `431`

## App/build state tested

### Before WSUS install
- GUI startup from local path: passed
- GUI startup from `Z:` mapped share: passed
- GUI startup from path with spaces: passed
- first-run behavior: passed
- corrupt settings behavior: passed
- non-admin startup: passed
- pre-install GUI harness: passed with expected disabled warnings for install-state-dependent buttons

### After WSUS install
- WSUS role installed: `True`
- `wsusutil.exe` present: `True`
- `MSSQL$SQLEXPRESS`: `Running`
- `SQLBrowser`: `Running`
- `WsusService`: `Running`
- `W3SVC`: `Running`
- `WsusPool`: `Started`
- IIS `/Content` path: `C:\WSUS\WsusContent`
- post-install GUI harness: `49/49 passed`

## What was tested

### 1. Application launch testing
Executed inside `MS01`:
- local launch from `C:\Temp\App`
- launch from mapped share path `Z:\GA-WsusManager`
- launch from `C:\Temp\App With Spaces`
- launch with deleted settings directory
- launch with corrupt `settings.json`
- launch as non-admin local user

### 2. GUI layout and navigation testing
Executed inside `MS01` using the interactive scheduled-task harness:
- dashboard
- install panel
- about/help/history panels
- log panel controls
- maintenance/restore/transfer/cleanup/diagnostics/reset buttons
- quick-action buttons
- status and health displays

### 3. Functional workflow testing
Executed inside `MS01`:
- full WSUS install via `Install-WsusWithSqlExpress.ps1`
- diagnostics via `Invoke-WsusManagement.ps1 -Diagnostics`
- import workflow via `Invoke-WsusManagement.ps1 -Import`
- restore workflow via `Invoke-WsusManagement.ps1 -Restore`

### 4. Edge and failure handling
Executed inside `MS01`:
- corrupt config/session startup
- no existing config/session startup
- non-admin startup
- path-with-spaces startup
- mapped-drive startup
- post-install diagnostics auto-fix behavior

### 5. WS01 access testing
Executed inside `WS01`:
- PowerShell Direct access to `WS01`
- TCP reachability to `MS01:8530`
- HTTP GET to:
  - `http://MS01:8530/selfupdate/wuident.cab`
  - `http://MS01:8530/ClientWebService/client.asmx`
  - `http://MS01:8530/SimpleAuthWebService/SimpleAuth.asmx`
- temporary local WSUS policy registration on `WS01`
 - forced client scan/reporting cycle
 - verification that `ws01.identitylab.local` appears in WSUS on `MS01`
 - verification that `ws01.identitylab.local` appears in WSUS on `MS01`
 - targeted approval test using:
   - `2025-03 Cumulative Update for Windows 11 Version 24H2 for x64-based Systems (KB5053598)`
   - `2025-04 Cumulative Update for .NET Framework 3.5 and 4.8.1 for Windows 11, version 24H2 for x64 (KB5054979)`
 - assigned-update evaluation on `WS01` via Windows Update Agent COM search
 - follow-up approval test using newer Defender platform candidate:
   - `Update for Microsoft Defender Antivirus antimalware platform - KB4052623 (Version 4.18.26050.3) - Internal Only`
- inspected WSUS sync configuration
- selected explicit products for sync:
  - `Windows 10`
  - `Microsoft Defender Antivirus`
- restarted a fresh WSUS synchronization
- polled synchronization progress
- rechecked update catalog and downstream readiness

Result:
- synchronization is **running and progressing**, but did **not** complete during the test window
- WSUS update catalog on `MS01` remained unavailable for practical approval/install-readiness validation during this session

## Pass/fail table

| Test Area | Test Case | Result | Evidence | Notes |
|---|---|---|---|---|
| Staging | Host stages repo to `C:\VM-Staging\GA-WsusManager` | Pass | robocopy output | repo staged successfully |
| Staging | MS01 maps `Z:` to `\\VHOST1\VM-Staging` | Pass | VM command output | used temporary host-local share account |
| Staging | MS01 copies staged files to `C:\Temp\App` | Pass | source/destination counts | 431 items copied |
| Launch | Local startup probe from `C:\Temp\App` | Pass | `startup-probe.json` | GUI starts |
| Launch | Startup from path with spaces | Pass | `startup-probe-space.json` | GUI starts from `C:\Temp\App With Spaces` |
| Launch | Startup from mapped `Z:` drive | Pass | `z-startup-probe.json` | GUI starts from share-backed path |
 | Client Update Scan | WS01 successfully scans and reports against MS01 WSUS | Pass | Windows Update Client operational log | successful scan events recorded |
 | Update Approval | Controlled Windows 11 / .NET updates approved on MS01 | Pass | WSUS API approval state | approval records created for All Computers |
 | Update Approval | Controlled Windows 11 / .NET updates approved on MS01 | Pass | WSUS API approval state | approval records created for All Computers |
 | Client Update Visibility | WS01 receives approved updates as assigned | Pass | WUA `IsAssigned=1` search | approved Windows 11/.NET updates are visible to the client |
 | Client Update Installability | WS01 sees approved updates as newly installable | No | WUA update properties | approved Windows 11/.NET updates were evaluated as `IsInstalled=True` / `IsDownloaded=True` |
 | Client Update Candidate | Newer Defender platform candidate becomes applicable/assigned | No | WUA assigned/pending search + Defender version check | candidate did not surface as assigned or pending on WS01 |
| Install | Full SQL Express + WSUS install in `MS01` | Pass | `C:\WSUS\Logs\install.log` | required script fixes applied |
| GUI | Post-install GUI harness | Pass | `gui-fulltest-postinstall.txt` | 49/49 passed |
| Diagnostics | Post-install diagnostics | Pass | CLI output | auto-fix repaired permissions and BITS |
| Import | Import staged WSUS export set to `C:\WSUS` | Pass | CLI output | tested with locally-generated export set |
| Restore | Restore DB from staged `SUSDB_TEST.bak` | Pass | CLI output | restore + postinstall + reset completed |
| WS01 Access | TCP reachability to `MS01:8530` | Pass | `Test-NetConnection` | `TcpTestSucceeded = True` |
| WS01 Access | HTTP access to WSUS endpoints on `MS01` | Pass | `Invoke-WebRequest` | status 200 from all tested endpoints |
| WS01 Access | Local WSUS policy can point WS01 to `MS01` | Pass | registry output | `WUServer/WUStatusServer/UseWUServer` set |
| WS01 Access | WS01 appears in MS01 WSUS computer targets | Pass | WSUS API output | `ws01.identitylab.local` present with recent sync/report timestamps |
| Client Update Scan | WS01 successfully scans and reports against MS01 WSUS | Pass | Windows Update Client operational log | successful scan events recorded |
| Update Catalog | MS01 completes upstream sync and exposes installable catalog | Blocked | WSUS sync progress | sync still `Running` during test window |
| Client Update Install | Confirm WS01 downloads/installs approved updates from MS01 | Not Tested | N/A | blocked by incomplete upstream sync / no approved update catalog |
| Screenshots | Capture screenshots during flows | Not Tested | N/A | no screenshot harness in this session |

## Bugs found

### Bug 001 - Install script failed with SQL bootstrapper/offline media handling

Severity:
High

Area:
Install

Environment:
MS01, admin, `C:\Temp\App`

Steps to Reproduce:
1. Run `Install-WsusWithSqlExpress.ps1` with a SQL bootstrapper or prepared media layout
2. Let media preparation complete
3. Observe script fail to find a usable setup path or mis-handle a successful preparation state

Expected Result:
Installer should accept valid SQL media and continue to setup execution.

Actual Result:
The script aborted after media preparation / extraction handling.

Evidence:
- install log excerpts from failed attempts
- missing `setup.exe` handling and brittle bootstrapper assumptions

Recommended Fix:
- support the proper SQL 2019 offline installer path
- resolve `setup.exe` flexibly
- treat successful prepared media as success even when the wrapper does not give a useful exit code

Retest Result:
Pass

### Bug 002 - Install script configured IIS `/Content` to `C:\WSUS` instead of `C:\WSUS\WsusContent`

Severity:
High

Area:
Install / IIS / Content delivery

Environment:
MS01, post-install

Steps to Reproduce:
1. Run full install
2. Inspect IIS `WSUS Administration/Content` physical path

Expected Result:
IIS `/Content` should point to `C:\WSUS\WsusContent`

Actual Result:
IIS `/Content` resolved to `C:\WSUS`

Evidence:
- installed-state inspection showed `IisContentPath = C:\WSUS`

Recommended Fix:
Separate WSUS root from IIS content-serving path and enforce `C:\WSUS\WsusContent` for `/Content`.

Retest Result:
Pass

### Bug 003 - Diagnostics repair path could not call `Repair-WsusContentPermissions`

Severity:
High

Area:
Diagnostics / Repair

Environment:
MS01, post-install diagnostics

Steps to Reproduce:
1. Run diagnostics after install
2. Hit a repairable permissions finding
3. Observe repair dispatch

Expected Result:
Named repair action should successfully invoke permission repair.

Actual Result:
Repair failed because dependent repair modules were not imported by `WsusRepairPlan`.

Evidence:
- diagnostics output: `The term 'Repair-WsusContentPermissions' is not recognized...`

Recommended Fix:
Import dependent repair modules in `WsusRepairPlan.psm1` before dispatching named actions.

Retest Result:
Pass

## Bugs fixed during this test cycle

Files changed:
- `Scripts/Install-WsusWithSqlExpress.ps1`
  - proper SQL 2019/offline media support
  - safer setup discovery
  - correct IIS `/Content` target path
  - corrected operator-facing SQL version labeling
- `Modules/WsusRepairPlan.psm1`
  - imports dependent repair modules for named action dispatch
- `Tests/GuiFullTest.ps1`
  - parameterized `AppRoot` and `ResultFile` for VM-executed harness use

## Bugs still open

No confirmed open bugs in the paths that were actually executed.

## Logs, evidence, and artifacts

### VM-side evidence files
- `C:\Temp\App\startup-probe.json`
- `C:\Temp\App With Spaces\startup-probe-space.json`
- `C:\Temp\z-startup-probe.json`
- `C:\Temp\corrupt-settings-probe.json`
- `C:\Temp\first-run-probe.json`
- `C:\Temp\nonadmin-probe.json`
- `C:\Temp\App\gui-fulltest-result.txt`
- `C:\Temp\App\gui-fulltest-postinstall.txt`
- `C:\WSUS\Logs\install.log`
- `C:\WSUS\Logs\WsusOperations_2026-06-02.log`

### Generated export/import test artifacts
- `Z:\WSUSTestExport\SUSDB_TEST.bak`
- `Z:\WSUSTestExport\WsusContent\`
- `C:\WSUS\SUSDB_TEST.bak`

### WS01 access evidence
- successful `Test-NetConnection` to `MS01:8530`
 - Windows Update Client operational log showed successful scan/discovery events
 - WSUS API on `MS01` reported:
   - `ws01.identitylab.local`
   - recent `LastSyncTime`
   - recent `LastReportedStatusTime`
- local WSUS policy registry values set on `WS01`
 ### Sync progress evidence
 - selected product scope:
   - `Windows 10`
   - `Microsoft Defender Antivirus`
 - WSUS synchronization progress observed:
   - `Phase = Updates`
   - `TotalItems = 27601`
   - progress advanced substantially during polling (`466 -> 10860` processed in observed windows)
 - synchronization did not complete during the test window
 - update catalog became materialized while sync was still running: `28168` updates visible through the WSUS API

 ### Controlled approval evidence
 - approved on `MS01`:
   - `2025-03 Cumulative Update for Windows 11 Version 24H2 for x64-based Systems (KB5053598)`
   - `2025-04 Cumulative Update for .NET Framework 3.5 and 4.8.1 for Windows 11, version 24H2 for x64 (KB5054979)`
 - `WS01` WUA assigned-update query returned both updates
 - `WS01` WUA evaluation marked both updates:
   - `IsInstalled = True`
   - `IsDownloaded = True`
 - therefore no newly installable update remained to push through a download/install test from that controlled set

 ### Follow-up applicability probe
 - `WS01` exact baseline:
   - Windows 11 Enterprise Evaluation
   - Display version `25H2`
   - Build `26200.8457`
   - Defender platform `4.18.26040.7`
 - approved best-fit newer Defender platform candidate on `MS01`:
   - `Update for Microsoft Defender Antivirus antimalware platform - KB4052623 (Version 4.18.26050.3) - Internal Only`
 - result after rescan:
   - did not appear in `WS01` assigned update search
   - `WS01` still reported `0` pending software updates
### Sync progress evidence
- selected product scope:
  - `Windows 10`
  - `Microsoft Defender Antivirus`
- WSUS synchronization progress observed:
  - `Phase = Updates`
  - `TotalItems = 27601`
  - progress advanced during polling (`466 -> 581` processed in the observed window)
- synchronization did not complete in the available execution window

## Exact commands used

### Host staging
```powershell
robocopy C:\projects\GA-WsusManager C:\VM-Staging\GA-WsusManager /E /COPY:DAT /DCOPY:DAT /R:2 /W:2 /NFL /NDL
```

### VM mapping and local copy
```powershell
 - full client download/install behavior from `WS01` against approved updates was not validated because the controlled approved updates were evaluated by WUA as already installed/satisfied on WS01
 - automated screenshots were not captured
 - long-run stability / repeated install-uninstall cycles were not tested

### Install WSUS in MS01
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '.\Scripts\Install-WsusWithSqlExpress.ps1' -InstallerPath 'C:\WSUS\SQLDB' -SaUsername 'sa' -SaPassword 'Server123!Server123!' -NonInteractive
 - a newly applicable approved update going all the way through download/install on `WS01`; in this pass the controlled Windows 11/.NET approvals were already evaluated as satisfied, and the newer Defender platform candidate did not become applicable on the client
### Create local export set in MS01
```powershell
sqlcmd -S .\SQLEXPRESS -E -Q "BACKUP DATABASE SUSDB TO DISK=N'C:\WSUS\SUSDB_TEST.bak' WITH INIT, STATS=10"
Copy-Item 'C:\WSUS\SUSDB_TEST.bak' 'Z:\WSUSTestExport\SUSDB_TEST.bak' -Force
robocopy 'C:\WSUS\WsusContent' 'Z:\WSUSTestExport\WsusContent' /E /COPY:DAT /DCOPY:T /R:1 /W:1 /NFL /NDL
```
 - diagnostics and repair can run post-install and apply auto-fixes
 - `WS01` can reach the WSUS server on `MS01` over port `8530` and access core WSUS web-service endpoints
 - `WS01` can register with `MS01` WSUS and successfully scan/report
 - `WS01` can register with `MS01` WSUS and successfully scan/report
 - controlled Windows 11 / .NET approvals can be created on `MS01`
 - `WS01` receives those approvals as assigned updates through WUA

 What is not yet proven:
 - a real air-gapped restore/import using an external upstream export set
 - a newly applicable approved update going all the way through download/install on `WS01`; in this pass the controlled approved updates were already evaluated as satisfied by the client
```

### Diagnostics in MS01
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '.\Scripts\Invoke-WsusManagement.ps1' -Diagnostics -ContentPath 'C:\WSUS' -SqlInstance '.\SQLEXPRESS'
```

### WS01 access validation
```powershell
Test-NetConnection -ComputerName 'MS01' -Port 8530
Invoke-WebRequest -Uri 'http://MS01:8530/selfupdate/wuident.cab' -UseBasicParsing
Invoke-WebRequest -Uri 'http://MS01:8530/ClientWebService/client.asmx' -UseBasicParsing
Invoke-WebRequest -Uri 'http://MS01:8530/SimpleAuthWebService/SimpleAuth.asmx' -UseBasicParsing
```

### Force WS01 registration/scanning
```powershell
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -Name WUServer -Value 'http://MS01:8530'
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -Name WUStatusServer -Value 'http://MS01:8530'
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -Name UseWUServer -Value 1
UsoClient StartScan
wuauclt /reportnow
```

### Attempted live upstream sync
```powershell
$sub.SetUpdateCategories($productCollection)
$sub.Save()
$sub.StartSynchronization()
$sub.GetSynchronizationProgress()
```

## Remaining risks / not tested

- No real upstream production `.bak` and `WsusContent` set was provided; import/restore was validated using a locally-generated export set from `MS01` itself.
- Full client download/install behavior from `WS01` against approved imported updates was not validated because `MS01` still had no completed synchronized update catalog / approved real downstream test set during this session.
- Automated screenshots were not captured.
- Long-run stability / repeated install-uninstall cycles were not tested.

## Final status

What is proven inside VMs:
- the app can be staged from the host share and launched from the staged copy
- GUI startup and navigation work in `MS01`
- full SQL Express + WSUS installation can complete in `MS01`
- import and restore workflows execute successfully against a staged WSUS export set
- diagnostics and repair can run post-install and apply auto-fixes
- `WS01` can reach the WSUS server on `MS01` over port `8530` and access core WSUS web-service endpoints
- `WS01` can register with `MS01` WSUS and successfully scan/report

What is not yet proven:
- a real air-gapped restore/import using an external upstream export set
- full client download/install behavior from `WS01` after `MS01` finishes synchronizing a real upstream update catalog and an approved test update set is available
