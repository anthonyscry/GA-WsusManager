# Make Plan: Per-User JSON Store Helper

## Source prompt

From `PATHFINDER-2026-06-18/04-handoff-prompts.md:172-198`.

Target unified system: AppData JSON persistence mechanics.

Single entry point: new `Invoke-WsusJsonStore` in `Modules/WsusUtilities.psm1`, near `Get-WsusAppDataPath` at `Modules/WsusUtilities.psm1:901-917`.

## Phase 0 — Documentation and API discovery

### Sources to read first
- `PATHFINDER-2026-06-18/03-unified-proposal.md:106-119`
- `PATHFINDER-2026-06-18/02-duplication-report.md:95-106`
- `PATHFINDER-2026-06-18/01-flowcharts/gui-shell-operation-orchestration.md`
- `PATHFINDER-2026-06-18/01-flowcharts/dashboard-auto-detection-health.md`
- `PATHFINDER-2026-06-18/01-flowcharts/configuration-shared-support.md`
- `Modules/WsusUtilities.psm1:901-917`
- `Scripts/WsusManagementGui.ps1:67-68,207-236,3694-3698`
- `Modules/WsusHistory.psm1:19-99,134-190,215-287`
- `Modules/WsusTrending.psm1:3-72,75-125,250-276`
- `Tests/WsusHistory.Tests.ps1`
- current absence of trend tests and JSON-store helper

### Allowed APIs and patterns
- Reuse `Get-WsusAppDataPath` for path resolution.
- Preserve separate files: `settings.json`, `history.json`, `trends.json`.
- Preserve history retry semantics, corrupt-file backup, and array-shape handling.
- Preserve trends oversized-file reset and corrupt-file backup behavior.
- Preserve GUI corrupt-settings warning behavior.

### Disallowed assumptions
- Do not build a generic persistence framework.
- Do not merge all UI data into one file.
- Do not reintroduce literal `%APPDATA%\WsusManager` path building in feature modules.
- Do not assume a JSON-store helper already exists.

## Phase 1 — Define the smallest useful JSON-store contract

### What to implement
- Add one narrow helper in `WsusUtilities` that owns:
  - AppData file path resolution via `Get-WsusAppDataPath`
  - parent directory creation
  - UTF-8 read/write
  - corrupt-file backup/reset
  - optional retry for IO-locked writes where callers need it
- Keep data-shape logic in the owning modules. The helper should unify persistence mechanics, not schema semantics.
- Decide the lightest interface that supports current callers. Prefer a small action-oriented contract over a generic object model.

### Verification checklist
- The helper can support settings, history, and trends without schema knowledge.
- Callers keep ownership of defaults, trimming, filtering, and warnings.

### Anti-pattern guards
- No single giant settings/history/trends file.
- No framework-style serializer abstraction.
- No helper-owned domain rules like history caps or trend summaries.

## Phase 2 — Move GUI settings to the helper

### What to implement
- Replace literal settings path and raw JSON IO at `Scripts/WsusManagementGui.ps1:67-68,207-236` with the helper.
- Preserve the existing keys and defaults.
- Preserve the corrupt-settings behavior that sets `$script:SettingsCorrupt = $true` and triggers the startup warning at `Scripts/WsusManagementGui.ps1:3694-3698`.
- Resolve the current ordering quirk where settings load happens before the code switches to `Get-WsusAppDataPath`.

### Verification checklist
- Settings still load before the GUI is shown.
- Save still writes the same keys.
- Corrupt settings still reset and warn.

### Anti-pattern guards
- Do not let the helper silently swallow the GUI’s corrupt-settings signal.
- Do not change settings keys or file location.

## Phase 3 — Move history and trends disk IO to the helper

### What to implement
- In `Modules/WsusHistory.psm1`, replace `Get-HistoryFilePath`, `Read-HistoryFile`, and `Write-HistoryFile` disk mechanics with the helper while preserving:
  - newest-first prepend
  - max 100 entries
  - IO retry loop
  - corrupt backup/reset
  - array bracket preservation for 0/1 entries
- In `Modules/WsusTrending.psm1`, replace literal path/read/save mechanics with the helper while preserving:
  - >1MB reset behavior
  - corrupt backup/reset
  - 90-day trim
  - `Clear-WsusTrendData` behavior
- Keep public APIs unchanged unless a targeted test proves otherwise.

### Verification checklist
- History tests continue to pass with `$env:APPDATA` overrides.
- Trends behavior stays identical for missing, corrupt, oversized, and clear scenarios.

### Anti-pattern guards
- Do not move history-specific retry semantics into GUI settings unless explicitly needed.
- Do not change trend-domain logic while refactoring its file IO.

## Phase 4 — Add missing tests and clean docs

### Tests to add/update
- `Tests/WsusUtilities.Tests.ps1`: add dedicated coverage for `Get-WsusAppDataPath` and the new JSON-store helper.
- `Tests/WsusHistory.Tests.ps1`: update only where internals changed; preserve existing behavior assertions.
- Add a new `Tests/WsusTrending.Tests.ps1` covering oversized reset, corrupt backup, daily update, trim, summary defaults, and clear behavior.
- Add one focused GUI/static assertion for settings path/IO if a utility-only test cannot cover it.

### Docs to update
- Update module/configuration docs to point to the shared AppData helper.
- Remove stale literal-path guidance from feature-specific docs where the helper becomes canonical.

## Final verification phase

Run targeted checks only:

```powershell
Invoke-Pester -Path .\Tests\WsusUtilities.Tests.ps1 -Output Detailed
Invoke-Pester -Path .\Tests\WsusHistory.Tests.ps1 -Output Detailed
Invoke-Pester -Path .\Tests\WsusTrending.Tests.ps1 -Output Detailed
```

Run static searches:
- Search repo for literal `%APPDATA%\WsusManager` path building in settings/history/trends modules after the cutover.
- Search repo for `Invoke-WsusJsonStore`; expected hits are utilities, settings/history/trends callers, tests, and docs.
