---
phase: 15-client-management-advanced
plan: "02"
subsystem: client-management
tags: [script-generator, winrm-fallback, powershell-scripts, cli-08]
dependency_graph:
  requires: [14-client-management-core]
  provides: [IScriptGeneratorService, ScriptGeneratorService, Script Generator UI]
  affects: [MainViewModel, MainWindow.xaml, Program.cs]
tech_stack:
  added: []
  patterns: [verbatim-string-templates, service-interface, observable-property, relay-command]
key_files:
  created:
    - src/WsusManager.Core/Services/Interfaces/IScriptGeneratorService.cs
    - src/WsusManager.Core/Services/ScriptGeneratorService.cs
    - src/WsusManager.Tests/Services/ScriptGeneratorServiceTests.cs
  modified:
    - src/WsusManager.App/ViewModels/MainViewModel.cs
    - src/WsusManager.App/Views/MainWindow.xaml
    - src/WsusManager.App/Program.cs
decisions:
  - "ScriptGeneratorService uses @\"...\" verbatim strings (not C# interpolated strings) for PowerShell templates — prevents C# compiler from interpreting PowerShell $() expressions as string interpolation holes"
  - "TestConnectivity script injects WSUS server name via string concatenation rather than an interpolated raw string to avoid the same C# vs PowerShell $ conflict"
  - "GenerateScript command is synchronous (no RunOperationAsync) — script generation is a local, instant operation with no I/O beyond the SaveFileDialog"
  - "MassGpUpdate script embeds hostnames from MassHostnames TextBox when populated; falls back to placeholder HOST1/HOST2/HOST3 template when empty"
  - "GenerateScriptCommand added to NotifyCommandCanExecuteChanged for consistency with all other commands, even though it has no CanExecute restriction"
metrics:
  duration: "~5 min"
  completed: "2026-02-21"
  tasks_completed: 2
  files_changed: 6
---

# Phase 15 Plan 02: Script Generator Summary

Implemented CLI-08 — the Script Generator fallback service for environments where WinRM is disabled or blocked. Admins can generate any of 5 self-contained PowerShell scripts, save them to disk, copy to the target machine, and run as Administrator without any WSUS Manager installation on the target.

## What Was Built

### IScriptGeneratorService + ScriptGeneratorService

`src/WsusManager.Core/Services/Interfaces/IScriptGeneratorService.cs`
- `GenerateScript(operationType, wsusServerUrl?, hostnames?)` — returns complete PS1 content
- `GetAvailableOperations()` — returns the 5 display names for the UI dropdown

`src/WsusManager.Core/Services/ScriptGeneratorService.cs`
- Maps display names ("Cancel Stuck Jobs") to internal keys ("CancelStuckJobs") and back
- **CancelStuckJobs**: Stop wuauserv + bits → clear SoftwareDistribution → restart services → verify with Get-Service
- **ForceCheckIn**: gpupdate /force → wuauclt resetauthorization/detectnow/reportnow → usoclient StartScan (if present)
- **TestConnectivity**: DNS resolution via `[System.Net.Dns]::GetHostAddresses` + Test-NetConnection on ports 8530/8531
- **RunDiagnostics**: Reads WUServer/WUStatusServer/UseWUServer registry keys + service status (wuauserv, bits, cryptsvc) + pending reboot key + WUA AgentVersion + LastWUStatusReportTime
- **MassGpUpdate**: Iterates provided hostnames via Test-WSMan check + Invoke-Command with gpupdate/wuauclt, logs pass/fail summary
- All scripts include `#Requires -RunAsAdministrator`, coloured Write-Host output, and a `Read-Host` pause at the end

### ViewModel (MainViewModel.cs)

Added to the Client Management section:
- `_scriptGeneratorService` field (constructor-injected)
- `SelectedScriptOperation` `[ObservableProperty]` — bound to ComboBox
- `ScriptOperations` computed property — delegates to `_scriptGeneratorService.GetAvailableOperations()`
- `GenerateScript` `[RelayCommand]` — validates selection, resolves wsusUrl from settings, parses MassHostnames for MassGpUpdate, calls service, opens SaveFileDialog, writes UTF-8 .ps1 file

### UI (MainWindow.xaml)

Added Script Generator card in the Client Tools panel, between Mass Operations and Error Code Lookup:
- Description text explaining WinRM fallback use case
- ComboBox (Operation) bound to `ScriptOperations` / `SelectedScriptOperation`
- "Generate Script" button bound to `GenerateScriptCommand`

### DI Registration (Program.cs)

```csharp
builder.Services.AddSingleton<IScriptGeneratorService, ScriptGeneratorService>();
```

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] C# interpolated raw string conflicts with PowerShell $() expressions**
- **Found during:** Task 1 (build attempt)
- **Issue:** `BuildMassGpUpdateScript` and `BuildTestConnectivityScript` used C# interpolated raw strings (`$"""..."""`). PowerShell's `$($hostname)` subexpressions caused 39 compile errors — C# tried to parse them as interpolation holes.
- **Fix:** Switched all PS script templates to `@"..."` verbatim strings. For scripts needing C# variable injection (TestConnectivity: wsusServer; MassGpUpdate: hostnamesBlock), used string concatenation to safely inject values before the verbatim template.
- **Files modified:** `src/WsusManager.Core/Services/ScriptGeneratorService.cs`
- **Commit:** (fixed in same Task 1 write)

## Test Results

- **Before:** 282 tests passing
- **After:** 336 tests passing (+54 new ScriptGeneratorServiceTests)
- **All tests pass** — no regressions

## Self-Check: PASSED

Files created/modified:
- FOUND: src/WsusManager.Core/Services/Interfaces/IScriptGeneratorService.cs
- FOUND: src/WsusManager.Core/Services/ScriptGeneratorService.cs
- FOUND: src/WsusManager.Tests/Services/ScriptGeneratorServiceTests.cs
- FOUND: src/WsusManager.App/ViewModels/MainViewModel.cs (modified)
- FOUND: src/WsusManager.App/Views/MainWindow.xaml (modified)
- FOUND: src/WsusManager.App/Program.cs (modified)

Commits:
- 3eebc7e: feat(15-02): add IScriptGeneratorService and ScriptGeneratorService
- 404f5a0: feat(15-02): add Script Generator UI card, ViewModel command, DI registration
