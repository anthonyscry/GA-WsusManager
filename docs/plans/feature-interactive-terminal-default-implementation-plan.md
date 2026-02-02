# Feature Plan: Interactive Terminal Enabled by Default

Short name: interactive-terminal-default

## Summary
Enable the interactive terminal in the log panel by default on first run, while preserving user preference stored in settings.json. Align the UI state with the default, and fix the exit command to disable interactive mode reliably.

## Acceptance Criteria (Checklist)
- [ ] Interactive terminal is ON by default when settings.json has no InteractiveMode value.
- [ ] Existing settings.json value continues to override the default.
- [ ] BtnInteractive shows "Interactive: On" with green background on startup when enabled.
- [ ] LogOutput is writable and displays a prompt when interactive mode is enabled.
- [ ] "exit" command disables interactive mode (sets state to false and makes LogOutput read-only).
- [ ] No new UI freezes introduced (logging remains non-blocking).

## Step 1 Recon Summary
### Domain + Data Flow
- Settings persisted at `C:\Users\<user>\AppData\Roaming\WsusManager\settings.json`.
- `Import-WsusSettings` reads `InteractiveMode` when present; `Save-Settings` writes it.
- Default state is currently `$script:InteractiveMode = $false` in `Scripts/WsusManagementGui.ps1`.

### Surface Area
- UI: `BtnInteractive` and `LogOutput` defined in embedded XAML in `Scripts/WsusManagementGui.ps1`.
- Handlers: `BtnInteractive.Add_Click`, `LogOutput.Add_KeyDown`, `Invoke-TerminalCommand`.
- Initialization: if `$script:InteractiveMode` then update button state + prompt.

### Tests + Build
- Pester tests in `Tests/Integration.Tests.ps1` can do static verification of defaults.
- CI/build gates: `build.ps1` blocks on Pester failures and PSScriptAnalyzer errors.

## Architecture (ASCII)
```
settings.json
   |
   v
Import-WsusSettings --> $script:InteractiveMode (default true)
   |                                |
   |                                v
   |                         UI initialization
   |                        (BtnInteractive, LogOutput)
   |
Save-Settings <--- BtnInteractive click / exit command
```

## Implementation Steps (File-by-File)

### 1) Scripts/WsusManagementGui.ps1
- Set default `$script:InteractiveMode = $true` before `Import-WsusSettings`.
- Keep `Import-WsusSettings` override only when `InteractiveMode` is present.
- Ensure initialization block uses `$script:InteractiveMode` to set button state and prompt.
- Fix `Invoke-TerminalCommand` "exit" branch to set `$script:InteractiveMode = $false`.
- Confirm `LogOutput.IsReadOnly` is set correctly when turning on/off.

### 2) Tests/Integration.Tests.ps1
- Add a Pester test that verifies:
  - Default assignment is `$script:InteractiveMode = $true`.
  - The "exit" command path sets `InteractiveMode` to false.
  (Static regex/AST check is acceptable for this scenario.)

## Task List + Dependencies
| ID | Task | Depends On |
|----|------|------------|
| T1 | Align defaults + exit behavior in WsusManagementGui.ps1 | - |
| T2 | Add static Pester checks in Integration.Tests.ps1 | T1 |

## Test Matrix
| Case | Layer | Test Type | Expected |
|------|-------|-----------|----------|
| Default interactive on without settings.json value | Unit/Static | Pester regex/AST | Pass |
| Interactive mode disabled via "exit" | Unit/Static | Pester regex/AST | Pass |
| UI shows On state on startup | Manual | GUI smoke test | Pass |
| Settings.json overrides default | Manual | Edit settings.json, restart | Pass |

## Rollout Steps
1. Implement code changes in `Scripts/WsusManagementGui.ps1`.
2. Add/adjust Pester tests.
3. Run `Invoke-Pester -Path .\Tests -Output Minimal`.
4. Launch GUI and confirm interactive mode starts ON.

## Rollback Steps
1. Revert commit(s) for tasks T1 and T2.
2. Remove test changes if needed.
3. Relaunch GUI to confirm behavior returns to previous default.

## Builder Notes
- Keep commits small and reference task IDs (e.g., `feat(T1): enable interactive default`).
- If you must deviate, update this plan file first with a "Deviations" section.

## Execution Notes
### Task Completion
- T1: Completed
- T2: Completed

### Tests
- T1 manual GUI smoke test not run (non-interactive environment).
- T2 `Invoke-Pester -Path .\Tests -Output Minimal` failed during discovery with ParameterBindingException in `Tests/ExeValidation.Tests.ps1` (WsusManager.exe) and failed in `Tests/Integration.Tests.ps1` (workflow path), then timed out after 120s.

## Deviations
None.
