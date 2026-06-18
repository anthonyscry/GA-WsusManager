# Make Plan: Backup Verification Entry

## Source prompt

From `PATHFINDER-2026-06-18/04-handoff-prompts.md:40-61`.

Target unified system: backup verification.

Single entry point: `Test-WsusBackupIntegrity` in `Modules/WsusDatabase.psm1:527-596`.

Corrected rewrite target:
- Replace the inline restore verification block at `Scripts/Invoke-WsusManagement.ps1:520-573`.

## Phase 0 — Documentation and API discovery

### Sources to read first
- `PATHFINDER-2026-06-18/03-unified-proposal.md:30-42`
- `PATHFINDER-2026-06-18/02-duplication-report.md:71-81`
- `PATHFINDER-2026-06-18/01-flowcharts/air-gap-transfer-restore.md`
- `PATHFINDER-2026-06-18/01-flowcharts/database-maintenance-utilities.md`
- `Modules/WsusDatabase.psm1:527-596,806-870`
- `Modules/WsusProvisioning.psm1:73-126`
- `Scripts/Invoke-WsusManagement.ps1:474-596`
- `Tests/WsusDatabase.Tests.ps1:362-418`
- `Tests/CliIntegration.Tests.ps1:320-340`
- `wiki/Module-Reference.md:232-246`
- `docs/ROLLBACK.md:180-202`

### Allowed APIs and patterns
- Use `Resolve-WsusRestoreBackup` to select/validate the `.bak` file before integrity checks (`Modules/WsusProvisioning.psm1:73-126`).
- Use `Test-WsusBackupIntegrity` for the actual integrity check. It already does both `RESTORE HEADERONLY` and `RESTORE VERIFYONLY ... WITH CHECKSUM` through `Invoke-WsusSqlcmd` (`Modules/WsusDatabase.psm1:576-589`).
- Reuse the helper’s result shape: `IsValid`, `BackupFile`, `BackupSizeMB`, `DatabaseName`, `BackupDate`, `Message`.

### Disallowed assumptions
- Do not keep the inline restore verifier once the module helper is wired.
- Do not weaken verification to only `VERIFYONLY`.
- Do not assume the helper already supports UNC paths or SQL credentials; verify whether restore really needs either before extending it.
- Do not silently change actual restore execution SQL in this plan unless the dependency on `Invoke-CheckedSqlcmd` is deliberately addressed.

## Phase 1 — Tighten the shared verifier contract if needed

### What to implement
- Audit whether restore callers can pass non-drive-letter backups. The current helper regex only accepts local drive-letter `.bak` paths at `Modules/WsusDatabase.psm1:557-560`.
- If restore truly needs UNC/removable paths that fail the regex, extend path validation conservatively without reopening SQL injection risk.
- Decide whether the helper needs a stricter return contract for restore messaging. Prefer keeping the current hashtable and improving caller formatting rather than inventing a new verifier object.

### Verification checklist
- Enumerate supported restore path shapes from GUI and CLI inputs.
- Confirm any validation expansion still rejects malformed/non-`.bak` values.

### Anti-pattern guards
- No parallel verifier.
- No looser SQL string escaping.
- No credential-on-command-line workaround.

## Phase 2 — Cut restore flow to the helper

### What to implement
- In `Scripts/Invoke-WsusManagement.ps1:520-573`, replace the inline `RESTORE VERIFYONLY` block with:
  1. `Resolve-WsusRestoreBackup` result handling
  2. `Test-WsusBackupIntegrity -BackupPath <resolved file> -SqlInstance <instance>`
  3. caller-side logging from the helper result
- Keep the fail-fast ordering: verification must still happen before service stop/offline restore steps.
- Decide explicitly whether restore execution SQL at `Scripts/Invoke-WsusManagement.ps1:589-596` stays on `Invoke-CheckedSqlcmd` pending the SQL-adapter plan, or is cut over in the same change. Prefer keeping this plan focused on verification unless the execution helper becomes an unavoidable blocker.

### Verification checklist
- Search the restore path for direct `RESTORE VERIFYONLY` after the cutover.
- Confirm the restore path still aborts before `Stop-Service` / database restore when integrity fails.

### Anti-pattern guards
- Do not keep both verification paths.
- Do not start restore work before the helper result is checked.
- Do not bury helper failures as warnings; restore must stop.

## Phase 3 — Tests and docs

### Tests to add/update
- `Tests/WsusDatabase.Tests.ps1`: strengthen `Test-WsusBackupIntegrity` coverage to assert both `HEADERONLY` and `VERIFYONLY WITH CHECKSUM`, plus invalid-path behavior.
- `Tests/CliIntegration.Tests.ps1`: replace restore assertions that depend on inline verification or `Invoke-CheckedSqlcmd` with assertions that restore uses `Test-WsusBackupIntegrity` before restore SQL.
- Add a focused static assertion that `Scripts/Invoke-WsusManagement.ps1:520-573` no longer contains the inline verifier.

### Docs to update
- `wiki/Module-Reference.md:232-246` if path rules, return fields, or error text change.
- `docs/ROLLBACK.md:180-202` if emergency restore instructions should now include explicit verification.

## Final verification phase

Run targeted checks only:

```powershell
Invoke-Pester -Path .\Tests\WsusDatabase.Tests.ps1 -Output Detailed
Invoke-Pester -Path .\Tests\CliIntegration.Tests.ps1 -Output Detailed
```

Run static searches:
- Search `Scripts/Invoke-WsusManagement.ps1` for `RESTORE VERIFYONLY` outside the shared helper.
- Search repo for `Test-WsusBackupIntegrity`; expected hits are module, restore caller, tests, and docs.
