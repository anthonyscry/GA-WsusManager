# Pitfalls Research

**Domain:** C#/WPF Windows Server admin tool (WSUS management rewrite)
**Researched:** 2026-02-19
**Confidence:** HIGH (core WPF/C# pitfalls verified via official docs and multiple sources; WSUS API compatibility confirmed via GitHub issue #5736 and Microsoft Q&A)

---

## Critical Pitfalls

### Pitfall 1: Microsoft.UpdateServices.Administration Is Incompatible with Modern .NET

**What goes wrong:**
The WSUS managed API (`Microsoft.UpdateServices.Administration.dll`) was built for .NET Framework. When referenced from a .NET 5+ / .NET 9 project, it throws `FileNotFoundException` for its dependent assemblies (`Microsoft.UpdateServices.Utils`, `System.Configuration.ConfigurationManager`). Binding redirects — the .NET Framework escape hatch — do not exist in .NET Core. There is no NuGet package. The DLL must be sourced manually from the Windows SxS folder and its transitive dependencies cannot be resolved by modern .NET's loader.

**Why it happens:**
Developers assume "any .NET DLL works with any .NET." The WSUS API DLLs were compiled against .NET Framework 4.0 and depend on Framework-only infrastructure. Modern .NET has an entirely different assembly loader with no compatibility bridge for this particular dependency chain.

**How to avoid:**
Do not attempt to reference `Microsoft.UpdateServices.Administration` from a .NET 9 project. Instead, use two alternatives based on the operation type:
- **High-level WSUS operations** (approve updates, get update counts, trigger sync): Invoke `wsusutil.exe` or PowerShell's `Get-WsusServer` via `Process.Start()` with captured stdout. This is safe, well-tested, and the same approach the PowerShell version used anyway.
- **Database maintenance** (decline superseded, purge, index rebuild, shrink): Call SUSDB directly via `Microsoft.Data.SqlClient` with the documented stored procedures (`spDeleteUpdate`, `spGetObsoleteUpdatesToCleanup`) and raw T-SQL. The current PowerShell version already does this and the approach is proven.

The architecture must treat the WSUS managed API as inaccessible and design around it from day one.

**Warning signs:**
- Any project reference to `Microsoft.UpdateServices.Administration.dll`
- Any use of `AdminProxy.GetUpdateServer()` in C# code
- Build succeeds but app crashes on first WSUS API call at runtime (assembly chain failure)

**Phase to address:**
Phase 1 (Foundation) — Establish the integration strategy before writing any WSUS-touching code. Document the "no managed WSUS API" constraint in architecture docs.

---

### Pitfall 2: .NET Single-File EXE Extraction Blocked by Antivirus on Air-Gapped Servers

**What goes wrong:**
.NET single-file self-contained executables extract their payload to `%TEMP%\.net\<AppName>\<hash>\` on first run. On hardened Windows Server environments (especially air-gapped networks with strict endpoint protection), this extraction triggers antivirus heuristics and the extracted DLLs are deleted mid-startup, causing the app to crash with `FileNotFoundException` or simply refuse to launch.

This is a confirmed known issue in the .NET runtime (`dotnet/runtime#2300`): Symantec Endpoint Protection and similar products delete the extracted files.

**Why it happens:**
Security-hardened servers treat any EXE that unpacks binaries to a temp directory as suspicious. The behavior is identical to how malware droppers operate. Air-gapped networks are disproportionately likely to run strict AV because they handle sensitive data.

**How to avoid:**
Use `IncludeAllContentForSelfExtract` in the publish configuration. This embeds all content directly in the EXE so nothing is extracted to disk at runtime, eliminating the temp-folder attack surface. The trade-off is slower cold startup (everything decompresses in memory) but this is acceptable for an admin tool that administrators launch intentionally.

```xml
<PublishSingleFile>true</PublishSingleFile>
<IncludeAllContentForSelfExtract>true</IncludeAllContentForSelfExtract>
<SelfContained>true</SelfContained>
<RuntimeIdentifier>win-x64</RuntimeIdentifier>
```

Additionally, set `DOTNET_BUNDLE_EXTRACT_BASE_DIR` to a known, whitelisted directory as a fallback if `IncludeAllContentForSelfExtract` is unavailable for any reason.

**Warning signs:**
- App launches fine in dev environment but crashes on server
- App works once then stops working after AV scan runs
- `%TEMP%\.net\` directory missing or empty when app tries to start

**Phase to address:**
Phase 1 (Foundation/Build Setup) — Configure the publish profile correctly before any other code is written. Validate on a test server with AV enabled before assuming the deployment model works.

---

### Pitfall 3: Async Void Event Handlers Silently Swallow Exceptions

**What goes wrong:**
WPF button click handlers are `void` event handlers. When made `async void`, any unhandled exception inside them bypasses normal try/catch and is raised on the thread pool with no traceable context, crashing the application or — worse — silently terminating the operation with no user feedback.

In an admin tool where every operation has real consequences (database shrink, service restart, firewall rule changes), silent operation failure is a critical UX and reliability failure.

**Why it happens:**
`async void` is required for WPF event handlers because the event signature is `EventHandler` (returns `void`). Developers add `async` to use `await` inside them without understanding that exception propagation is fundamentally broken for `async void`. The application appears to work in happy-path testing but crashes unpredictably in production.

**How to avoid:**
Wrap every `async void` event handler body in a try/catch that routes exceptions to a centralized error handler:

```csharp
private async void BtnHealthCheck_Click(object sender, RoutedEventArgs e)
{
    try
    {
        await RunOperationAsync("Health Check", PerformHealthCheckAsync);
    }
    catch (Exception ex)
    {
        HandleFatalError(ex);
    }
}
```

All actual logic lives in `async Task` methods, never in the `async void` handler itself. The handler is only a thin dispatcher. This is the pattern mandated by `RelayCommand` in CommunityToolkit.Mvvm — use it.

**Warning signs:**
- Operations that start but produce no output and no error
- WPF application crash with `TaskScheduler.UnobservedTaskException` in event log
- Operations that work in debug but fail silently in release

**Phase to address:**
Phase 1 (Foundation) — Establish the operation execution pattern (`RunOperationAsync` wrapper or MVVM `RelayCommand`) before implementing any operations. Every operation goes through this gate.

---

### Pitfall 4: UI Thread Blocking from "Looks Async" Code

**What goes wrong:**
`await Task.Run(...)` offloads CPU work to a thread pool thread, but code that runs after the `await` resumes on the UI thread. If that code does any blocking I/O, network calls, or heavy computation synchronously, the UI freezes — even though the method is marked `async`.

Common manifestations in an admin tool:
- `ServiceController.WaitForStatus()` called on the UI thread after an `await`
- File I/O during export/import verification
- SQL connection establishment (which can take several seconds on a slow `localhost\SQLEXPRESS`)

**Why it happens:**
Developers see `async/await` and assume the entire method is off-thread. The SynchronizationContext means continuation code (after `await`) runs on the UI thread unless explicitly wrapped in another `Task.Run`.

**How to avoid:**
Keep the UI thread exclusively for UI updates. Any call that can block goes inside `Task.Run()`. The pattern:

```csharp
await Task.Run(async () =>
{
    // ALL blocking work here: SQL queries, service waits, file I/O
    var result = await DoSlowWorkAsync(cancellationToken);
    return result;
});
// UI updates only after this point
StatusText = "Operation complete";
```

Use `IProgress<string>` for log-line reporting from the background thread to the UI thread. Never call `Dispatcher.Invoke` manually — it is a sign the architecture is wrong.

**Warning signs:**
- UI feels "sticky" or non-responsive during operations
- `await`-heavy methods that still freeze the window
- `Dispatcher.Invoke` calls anywhere in the codebase

**Phase to address:**
Phase 1 (Foundation) — The `RunOperationAsync` pattern must enforce this separation. Code review checklist: no `Dispatcher.Invoke`, no blocking calls after `await` on UI thread.

---

### Pitfall 5: Rewrite Loses Accumulated Edge-Case Behavior

**What goes wrong:**
The PowerShell v3.8.x codebase has 3000+ LOC of GUI logic, 11 modules, and 323 tests. It encodes 3+ years of discovered edge cases: SQL command timeout differences between module versions, batched deletion to avoid lock timeouts, retry logic on DB shrink when backup is running, the `wsusutil reset` fix for air-gap post-import, etc.

A rewrite that treats the existing code as "documentation" rather than specification will silently drop these behaviors. The app will appear feature-complete but fail on the edge cases that made users trust the PowerShell version.

**Why it happens:**
Rewrites are seductive. The new code is clean, the old code is messy. Developers skim the old code for the "happy path" and miss the error handling, retry loops, and workarounds that are scattered in catch blocks and comments.

**How to avoid:**
Before writing any operation in C#:
1. Read the corresponding PowerShell module function in full, including catch blocks
2. Extract every retry, timeout override, batch size, and workaround as an explicit requirement comment
3. Write the C# implementation against those requirements, not against the "obvious" behavior
4. Port the Pester tests to xUnit before implementing (test-first reveals the edge cases)

Critical behaviors that must be explicitly preserved:
- SQL command timeout set to 0 (unlimited) for index rebuild and DB shrink operations
- Batched deletion (100 updates per batch) for `spDeleteUpdate` to avoid transaction log overflow
- Supersession record removal before declined update purge (two-step, not one)
- Retry on DB shrink (3 attempts, 30s delay) when backup is running
- Re-query service status instead of calling `Refresh()` (avoids stale cache)
- `BeginOutputReadLine()` required immediately after `Process.Start()` before any `WaitForExit()`

**Warning signs:**
- New implementation "works in testing" but fails in production on real WSUS servers with large databases
- Deep cleanup runs faster than expected (skipped a step)
- Services show wrong status (cached `ServiceController` not refreshed)

**Phase to address:**
Phase 2+ (each feature phase) — Each operation phase must begin with a review of the corresponding PowerShell source before writing C#.

---

## Moderate Pitfalls

### Pitfall 6: ServiceController Status Caching

**What goes wrong:**
`ServiceController` caches the service status. Calling `sc.Status` multiple times returns a stale value. The PowerShell version discovered this and explicitly re-queries services. The C# version will rediscover this bug if `ServiceController` is used naively.

**How to avoid:**
Always call `sc.Refresh()` immediately before reading `sc.Status`. Alternatively, create a new `ServiceController` instance each time status is needed — this avoids the caching entirely. The existing PowerShell workaround (re-query instead of using the `Refresh()` method) was needed because PSCustomObjects don't support `Refresh()`, but in C# `sc.Refresh()` works correctly.

```csharp
using var sc = new ServiceController("WsusService");
sc.Refresh();
var status = sc.Status; // Fresh value
```

Wrap `ServiceController` in a `using` block — it implements `IDisposable` and must be properly disposed.

**Phase to address:**
Phase 2 (Service Management) — establish the pattern before any service status reads.

---

### Pitfall 7: SQL Command Timeout Default of 30 Seconds

**What goes wrong:**
`SqlCommand.CommandTimeout` defaults to 30 seconds. WSUS database maintenance operations (index rebuild, statistics update, database shrink on large SUSDB) routinely take minutes. Operations will silently time out and report failure even though the underlying SQL work was progressing normally.

**How to avoid:**
Set `CommandTimeout = 0` (unlimited) for all maintenance operations. Use a named constant:

```csharp
private const int MaintenanceCommandTimeout = 0; // Unlimited for long-running DB ops
private const int StandardCommandTimeout = 30;    // Default for queries
```

Never use the default for operations involving index rebuild, statistics update, shrink, or stored procedure execution on SUSDB.

**Phase to address:**
Phase 3 (Database Operations) — add a code review gate: every `SqlCommand` must have an explicit `CommandTimeout`.

---

### Pitfall 8: Progress Flooding the UI Thread

**What goes wrong:**
Reporting progress too frequently from a background operation floods the UI thread's message queue. The WPF rendering pipeline has lower priority than input processing, so thousands of `IProgress.Report()` calls per second cause visible UI lag and apparent freezing — even when the background operation is fully off-thread.

This is confirmed in WPF documentation and community testing: sending 1,000,000 rapid updates causes the UI to stop repainting because the render/paint message is deprioritized.

**How to avoid:**
Rate-limit progress reporting. Only report when there is a meaningful status change, or throttle to a maximum of ~10 reports per second using a timestamp check:

```csharp
private DateTime _lastProgressReport = DateTime.MinValue;
private void ReportProgressIfThrottled(string message)
{
    var now = DateTime.UtcNow;
    if ((now - _lastProgressReport).TotalMilliseconds > 100)
    {
        _progress.Report(message);
        _lastProgressReport = now;
    }
}
```

For batch operations (e.g., deleting 5,000 updates in 50 batches), report once per batch, not once per update.

**Phase to address:**
Phase 3+ (any phase with long-running operations) — establish the throttling pattern in the `RunOperationAsync` infrastructure.

---

### Pitfall 9: Process stdout Deadlock from Synchronous Read

**What goes wrong:**
If the app uses `Process.StandardOutput.ReadToEnd()` synchronously while the child process is still running and waiting to write to stderr, both the parent and child deadlock. The child fills the stderr buffer waiting to write, the parent is blocking waiting for stdout to finish. Neither can proceed.

This is a well-documented .NET pitfall in `System.Diagnostics.Process` and directly relevant to operations that shell out to `wsusutil.exe`, `sqlcmd.exe`, or PowerShell scripts.

**How to avoid:**
Always use async output reading:
```csharp
process.OutputDataReceived += (s, e) => { if (e.Data != null) AppendLog(e.Data); };
process.ErrorDataReceived += (s, e) => { if (e.Data != null) AppendLog("[ERR] " + e.Data); };
process.Start();
process.BeginOutputReadLine();  // Required — must call this
process.BeginErrorReadLine();   // Required — must call this
await process.WaitForExitAsync(cancellationToken);
```

Never call `ReadToEnd()` or `ReadLine()` directly on redirected streams of a running process. Never mix sync and async reads on the same stream.

**Phase to address:**
Phase 2 (any phase that launches external processes) — establish the process-launching helper before first use.

---

### Pitfall 10: WPF Fluent/Dark Theme Is Experimental in .NET 9

**What goes wrong:**
WPF .NET 9 introduced `ThemeMode` with Fluent dark theme support, but it is marked experimental. Known crashes exist when the system theme is toggled between light and dark while the app is running (threading exception: "calling thread cannot access this object"). Generated elements like `DataGrid` rows use `ThemeStyle` rather than `Style`, causing inconsistent appearance.

**How to avoid:**
Do not rely on `Application.ThemeMode` (experimental API). Instead, implement dark theme using explicit `ResourceDictionary` entries with a custom color palette — the same approach the PowerShell version used. This is fully stable, completely predictable, and not subject to OS theme change events. Since this is an admin tool always deployed to server environments (not interactive desktops), there is no requirement to respond to system theme changes.

**Phase to address:**
Phase 1 (Foundation/UI Shell) — decide on the theming approach before any UI work begins.

---

### Pitfall 11: UAC Manifest Missing in Debug vs Release

**What goes wrong:**
Visual Studio runs the application under the IDE's elevated token during debugging. The admin privilege requirement appears satisfied. But when the compiled EXE is run by an administrator on the target server, if the application manifest does not specify `requireAdministrator`, Windows launches it as a standard user and all privileged operations (service start/stop, firewall rules, SQL Server access) fail with access denied errors.

**How to avoid:**
Embed `requireAdministrator` in the application manifest from the start:

```xml
<!-- app.manifest -->
<requestedExecutionLevel level="requireAdministrator" uiAccess="false" />
```

Test the build artifact directly from the command line (not from VS) before declaring it working.

**Phase to address:**
Phase 1 (Foundation) — set the manifest level before writing any privileged code. Test outside the IDE.

---

### Pitfall 12: WSUS Managed API Deprioritized Because It "Works on Dev"

**What goes wrong:**
On a developer's workstation where the WSUS role is installed alongside the WSUS management console, the `Microsoft.UpdateServices.Administration.dll` may actually be loadable under .NET Framework compatibility shims or because the dev machine happens to have all dependencies in the GAC. This leads to "it works here" confidence that collapses when deployed to a production Windows Server 2019 running the newer WinSxS version of the assembly.

**Why it happens:**
Dev machines accumulate years of installed software, SDK compatibility layers, and GAC entries that production servers don't have. The runtime assembly resolution path on a clean Windows Server 2019 deployment is completely different.

**How to avoid:**
Treat Pitfall 1 as absolute. Do not attempt to use the managed WSUS API regardless of whether it appears to work locally. The production failure mode is guaranteed and the workaround (direct SQL + process invocation) is already proven in v3.8.x.

**Phase to address:**
Phase 1 (Foundation) — document the constraint explicitly and add a CI check that the project has no reference to `Microsoft.UpdateServices.Administration`.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| `Dispatcher.Invoke` for UI updates | Works immediately | Signals wrong threading architecture; becomes unmaintainable | Never — use `IProgress<T>` or data binding instead |
| `async void` without try/catch wrapper | Less boilerplate | Silent exception swallowing, app crashes with no trace | Never in operation code; only allowed as a thin dispatcher to a task method |
| Hardcoded SQL command timeout (30s default) | No extra lines | Maintenance operations timeout on large databases | Never — always set explicitly |
| Using `ServiceController.Status` without `Refresh()` | Simpler code | Returns stale status, shows wrong service state in UI | Never — always refresh before reading |
| Single-threaded operation execution (blocking UI) | Simpler code path | UI freezes, users think app is broken, double-click triggers duplicate operations | Never for operations > 100ms |
| Loading WSUS API DLL with `Assembly.LoadFrom()` | Access to high-level API | Breaks on clean server deployment; unsupportable | Never |
| Copying edge-case logic from PS version "later" | Faster initial build | Edge cases surface in production on real WSUS databases | Never — port edge cases in the same phase as the feature |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| SQL Server Express (SUSDB) | Using default 30s `CommandTimeout` for maintenance | Set `CommandTimeout = 0` for all index rebuild, shrink, stored procedure calls |
| SQL Server Express (SUSDB) | Forgetting `TrustServerCertificate=true` for `localhost\SQLEXPRESS` | Always include in connection string; v3.8.11 fixed this after production failures |
| Windows Services (`ServiceController`) | Reading `Status` from cached instance | Call `sc.Refresh()` or instantiate fresh `ServiceController` before every status read |
| External processes (`wsusutil`, `sqlcmd`) | Synchronous stdout read while process is running | Use `BeginOutputReadLine()` + `BeginErrorReadLine()` immediately after `Start()` |
| External processes | Not calling `BeginOutputReadLine()` at all | Process output hangs in buffer; `WaitForExit` never returns |
| Windows Firewall (via NetFW COM or `netsh`) | COM interop for firewall on .NET 9 | Use `Process.Start("netsh", ...)` with captured output; proven reliable in v3.8.x |
| Scheduled Tasks | Using `Microsoft.Win32.TaskScheduler` NuGet without testing on Server 2019 | TaskScheduler library is well-tested on Server 2019; verify credential prompts work with domain accounts |
| WSUS content verification | Calling `wsusutil reset` without async output capture | Long-running; must use async process pattern or app appears to hang |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Dashboard polling on UI thread | UI freezes every 30 seconds during refresh | All DB queries run on background thread; only property binding updates UI | First time a DB query takes > 200ms |
| Unbatched `spDeleteUpdate` calls | SQL transaction log fills, operations fail or take hours | Batch at 100 updates per call (proven in v3.8.x) | When declined update count > ~200 |
| `IProgress.Report()` called per-row in SQL loops | UI lags during bulk operations, message queue floods | Throttle to ~10 reports/sec; report per-batch not per-row | When processing > 1,000 updates |
| `ServiceController` instance held open across operations | Stale status displayed in dashboard | Create fresh instance per status check; dispose in `using` | When services are restarted between checks |
| Export copy without buffering | Slow file transfer for large WSUS content directories | Use `File.Copy` or buffered stream copy, not byte-by-byte | When exporting > 1GB content |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Path interpolation in SQL strings | SQL injection via WSUS content path or server name | Use `SqlParameter` for all variable SQL; never interpolate paths |
| Path traversal in export/import | Attacker-controlled path escapes to system dirs | Validate all paths with `Path.GetFullPath()` + prefix check before use |
| Running EXE without `requireAdministrator` manifest | Operations silently fail as standard user; confusing UX | Embed manifest from project creation |
| Logging credentials or connection strings | Log file captures SQL Server auth | Never log connection strings; redact passwords from any logged CLI args |
| Trusting file names from import media | USB-sourced filenames could contain path traversal | Normalize all import source paths with `Path.GetFullPath()` and validate against allowed base path |

---

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| No visual feedback during long operations | Admins double-click, launching duplicate operations | Disable all operation buttons immediately when operation starts; show progress in log panel |
| Dialogs that block without explanation | Admin doesn't know if app is working or frozen | Show operation name and elapsed time in status bar; keep log panel auto-scrolling |
| Dialogs shown after switching to operation view | User sees blank operation panel before dialog | Show dialog first (before switching views); only switch view on confirmation |
| No cancel capability for long operations | Admins must kill the process to stop an errant operation | Every operation accepts `CancellationToken`; Cancel button always visible and functional |
| Error messages with stack traces | Non-technical admin sees exception gibberish | Wrap all operations with user-friendly error dialog; log full details to file |
| Buttons re-enabled but operation still running | User triggers second operation over the first | Reset `IsOperationRunning` flag and re-enable buttons only in the `finally` block |

---

## "Looks Done But Isn't" Checklist

- [ ] **Health Check:** Appears to pass — verify it actually checks SQL connection, WSUS service, IIS app pool, firewall ports 8530/8531, AND content directory permissions. Missing any one check is partial, not complete.
- [ ] **Deep Cleanup:** Shows "cleanup complete" — verify the 6-step sequence runs in order: WSUS built-in cleanup → supersession record removal (declined) → supersession record removal (superseded, batched) → `spDeleteUpdate` (batched, 100/call) → index rebuild → shrink. Each step is required.
- [ ] **Export/Import:** Files copy successfully — verify the content directory structure is preserved exactly (`C:\WSUS\` root, not `C:\WSUS\wsuscontent\`). Wrong root causes silent WSUS content mismatch.
- [ ] **Service Start:** Returns success — verify SQL Server starts before WSUS (dependency order). Starting WSUS before SQL fails silently on some configurations.
- [ ] **Cancel:** Button click stops spinner — verify the underlying process is actually killed (`Process.Kill()`), not just that the UI returns to idle while the process runs in the background.
- [ ] **Settings Persist:** Values save — verify settings survive application restart, not just session persistence in memory.
- [ ] **Single-EXE:** Runs on dev machine — verify it runs on a clean Windows Server 2019 installation with no .NET SDK installed and with AV enabled.

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| WSUS API incompatibility discovered mid-build | HIGH | Rearchitect the WSUS-touching operations to use direct SQL + process invocation; roughly 1-2 weeks of rework |
| Single-file AV blocking discovered in deployment | MEDIUM | Rebuild with `IncludeAllContentForSelfExtract`; requires publish pipeline change + re-test |
| Async void exceptions swallowing errors | MEDIUM | Audit all event handlers and wrap in try/catch; add global `TaskScheduler.UnobservedTaskException` handler as backstop |
| SQL timeout failures on large databases | LOW | Add `CommandTimeout = 0` to the specific failing command; targeted fix |
| Edge cases missing from ported operations | HIGH | Re-audit PowerShell source for each affected operation; write regression tests before fixing |
| Progress flooding causing UI lag | LOW | Add throttling wrapper to `IProgress.Report` call sites; minimal code change |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| WSUS managed API incompatibility | Phase 1 (Foundation) | CI check: no reference to `Microsoft.UpdateServices.Administration` |
| Single-file AV blocking | Phase 1 (Build Setup) | Deploy to clean Server 2019 VM with AV enabled; EXE launches without errors |
| Async void exception swallowing | Phase 1 (Foundation) | Code review gate: no `async void` without wrapping try/catch |
| UI thread blocking | Phase 1 (Foundation) | No `Dispatcher.Invoke` in codebase; all operations tested with UI responsiveness check |
| Rewrite missing edge cases | Phase 2+ (each feature) | Port Pester tests to xUnit before implementing each operation |
| ServiceController caching | Phase 2 (Service Management) | Unit test: read status twice with a stop/start between; both values correct |
| SQL command timeout | Phase 3 (Database Operations) | Code review gate: every `SqlCommand` has explicit `CommandTimeout` |
| Progress flooding | Phase 3+ (operations) | Log output panel remains responsive during 5,000-update cleanup operation |
| Process stdout deadlock | Phase 2 (any external process) | Integration test: `wsusutil check-health` runs to completion without hanging |
| Fluent theme crashes | Phase 1 (UI Shell) | Custom resource dictionary; no `Application.ThemeMode` usage |
| UAC manifest missing | Phase 1 (Foundation) | Run compiled EXE from command line as non-elevated user; UAC prompt appears |
| WSUS API "works on dev" false confidence | Phase 1 (Foundation) | CI runs on clean Server 2019 agent, not dev machine |

---

## Sources

- [dotnet/runtime#2300 — Single-file: Antivirus deletes extracted files](https://github.com/dotnet/runtime/issues/2300) — HIGH confidence (official .NET repo)
- [dotnet/core#5736 — FileNotFoundException with WSUS API DLL in .NET Core](https://github.com/dotnet/core/issues/5736) — HIGH confidence (official .NET repo)
- [Microsoft Q&A — How to use WSUS APIs with C# in Visual Studio](https://learn.microsoft.com/en-us/answers/questions/1298593/how-to-use-the-wsus-apis-with-c-in-visual-studio) — HIGH confidence (Microsoft official)
- [Microsoft Q&A — UI freezing due to Task.Run activity in async/await](https://learn.microsoft.com/en-us/answers/questions/1366732/ui-freezing-due-to-task-run-activity-in-async-awai) — HIGH confidence (Microsoft official)
- [dotnet/runtime#28583 — proc.StandardOutput.ReadAsync doesn't cancel if no output](https://github.com/dotnet/runtime/issues/28583) — HIGH confidence (official .NET repo)
- [Process.StandardOutput docs — deadlock warning](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.process.standardoutput) — HIGH confidence (Microsoft official)
- [ServiceController docs — Refresh() requirement](https://learn.microsoft.com/en-us/dotnet/api/system.serviceprocess.servicecontroller) — HIGH confidence (Microsoft official)
- [ServiceController wrong status GitHub issue #88105](https://github.com/dotnet/runtime/issues/88105) — HIGH confidence (official .NET repo)
- [Rick Strahl — Async void event handling in WPF](https://weblog.west-wind.com/posts/2022/Apr/22/Async-and-Async-Void-Event-Handling-in-WPF) — MEDIUM confidence (verified against official docs)
- [Brian Lagunas — Progress reporting WPF UI freeze](https://brianlagunas.com/does-reporting-progress-with-task-run-freeze-your-wpf-ui/) — MEDIUM confidence (WPF community expert, consistent with official rendering docs)
- [.NET Single-file deployment overview](https://learn.microsoft.com/en-us/dotnet/core/deploying/single-file/overview) — HIGH confidence (Microsoft official)
- [WPF .NET 9 ThemeMode experimental status](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/whats-new/net90) — HIGH confidence (Microsoft official)
- [UAC manifest configuration](https://learn.microsoft.com/en-us/cpp/build/reference/manifestuac-embeds-uac-information-in-manifest) — HIGH confidence (Microsoft official)
- [WSUS deprecation announcement — September 2024](https://techcommunity.microsoft.com/blog/windows-itpro-blog/windows-server-update-services-wsus-deprecation/4250436) — HIGH confidence (Microsoft official)
- GA-WsusManager CLAUDE.md — 12 documented anti-patterns from production PowerShell version — HIGH confidence (first-party production experience)

---

*Pitfalls research for: C#/WPF Windows Server WSUS admin tool rewrite*
*Researched: 2026-02-19*
