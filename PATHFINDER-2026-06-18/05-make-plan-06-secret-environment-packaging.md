# Make Plan: Secret Environment Packaging

## Source prompt

From `PATHFINDER-2026-06-18/04-handoff-prompts.md:145-170`.

Target unified system: secret environment propagation and cleanup.

Single entry point: `New-WsusSecretEnvironment` in `Modules/WsusUtilities.psm1:923-942`.

## Phase 0 — Documentation and API discovery

### Sources to read first
- `PATHFINDER-2026-06-18/03-unified-proposal.md:91-104`
- `PATHFINDER-2026-06-18/02-duplication-report.md:83-93`
- `PATHFINDER-2026-06-18/01-flowcharts/gui-shell-operation-orchestration.md`
- `PATHFINDER-2026-06-18/01-flowcharts/configuration-shared-support.md`
- `Modules/WsusUtilities.psm1:923-954,989-993`
- `Modules/WsusOperationPlan.psm1:19-52,82-105,137-160`
- `Modules/WsusOperationCompletion.psm1:10-73`
- `Scripts/WsusManagementGui.ps1:3224-3267`
- `Scripts/Install-WsusWithSqlExpress.ps1:29-33,346-365`
- `Tests/WsusArchitectureInterfaces.Tests.ps1:100-135,191-243`
- `wiki/Configuration-Guide.md:1-31`

### Allowed APIs and patterns
- Use `New-WsusSecretEnvironment` to create both the environment hashtable and cleanup-key list.
- Use `Clear-WsusSecretEnvironment` to remove env vars after completion or startup failure.
- Reuse `New-WsusGuiOperationCompletion` / `Invoke-WsusGuiOperationCompletion`; they already have an explicit `CleanupKeys` seam.
- Preserve the existing rule that secrets go through environment variables, not command-line arguments.

### Disallowed assumptions
- Do not assume `Wsus.OperationPlan` already has a `CleanupKeys` field.
- Do not keep GUI cleanup inferred from `.Environment.Keys` once the plan carries explicit cleanup keys.
- Do not change child-script password acquisition away from env vars.
- Do not trust `wiki/Configuration-Guide.md` over source; it is stale here.

## Phase 1 — Extend the plan object to carry cleanup keys

### What to implement
- Add an explicit `CleanupKeys` field to the `Wsus.OperationPlan` object built by `New-WsusOperationPlan`.
- Keep `Environment` as the child-process input payload.
- Decide whether `CleanupKeys` is always present as an array or optional/null. Prefer always-present array for simpler GUI cleanup code.

### Verification checklist
- Existing plan constructors still return the same core fields.
- Plan objects can now carry cleanup keys without the GUI reconstructing them.

### Anti-pattern guards
- No second secret object type.
- No magic inference from environment keys after this phase.

## Phase 2 — Cut install and schedule builders to the helper

### What to implement
- In `Modules/WsusOperationPlan.psm1:98-103`, replace inline install env packaging with `New-WsusSecretEnvironment -Values @{ WSUS_INSTALL_SA_PASSWORD = <plaintext> }`.
- In `Modules/WsusOperationPlan.psm1:153-157`, replace inline schedule env packaging with `New-WsusSecretEnvironment -Values @{ WSUS_TASK_PASSWORD = <plaintext> }`.
- Pass both `.Environment` and `.CleanupKeys` into the plan object.
- Keep the existing plaintext lifetime narrow: convert from `SecureString`, package, and drop references.

### Verification checklist
- Install plan still feeds `WSUS_INSTALL_SA_PASSWORD` to the child script.
- Schedule plan still feeds `WSUS_TASK_PASSWORD` to the scheduled-task registration path.
- Existing env-var names do not change.

### Anti-pattern guards
- Do not widen secret lifetime.
- Do not create ad-hoc env hashtables beside the helper.

## Phase 3 — Cut GUI cleanup to explicit cleanup keys

### What to implement
- Replace `Scripts/WsusManagementGui.ps1:3224-3239` cleanup-key derivation from `.Environment.Keys` with plan-provided `.CleanupKeys`.
- Keep the catch/startup-failure cleanup at `Scripts/WsusManagementGui.ps1:3266-3267`, but make it consume the same explicit list.
- Preserve `Invoke-WsusGuiOperationCompletion` cleanup callback behavior.

### Verification checklist
- Success path cleanup uses the explicit keys.
- Start failure path cleanup uses the same keys.
- No GUI code reconstructs keys from the environment afterward.

### Anti-pattern guards
- No duplicated cleanup logic.
- No implicit contract hidden in dictionary keys.

## Phase 4 — Tests and docs

### Tests to add/update
- `Tests/WsusArchitectureInterfaces.Tests.ps1`: extend install/schedule plan tests to assert `.CleanupKeys` contains the expected env-var names.
- Keep the `Wsus.SecretEnvironment` object-shape test and add blank-key filtering coverage.
- Keep the completion cleanup callback assertions.

### Docs to update
- Fix stale cleanup-key claims and signatures in `wiki/Configuration-Guide.md`.
- Update any module-reference docs that describe plan shape or secret flow.

## Final verification phase

Run targeted checks only:

```powershell
Invoke-Pester -Path .\Tests\WsusArchitectureInterfaces.Tests.ps1 -Output Detailed
Invoke-Pester -Path .\Tests\Integration.Tests.ps1 -Output Detailed
```

Run static searches:
- Search `Modules/WsusOperationPlan.psm1` for raw install/schedule secret env hashtables.
- Search `Scripts/WsusManagementGui.ps1` for cleanup-key inference from `.Environment.Keys`.
