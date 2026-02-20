# Stack Research

**Domain:** Windows Server Administration GUI Tool (WSUS Manager Rewrite)
**Researched:** 2026-02-19
**Confidence:** HIGH (C# stack verified via official docs; alternatives confirmed as inferior via multiple sources)

---

## Decision Summary

**Use C# (.NET 9) with WPF.**

This is not a close call. Every alternative (Rust, Go) introduces fundamental blockers — fragile or non-existent GUI ecosystems, no viable COM interop path for WSUS APIs, or no production-quality Windows native tooling. C# with WPF is the only option that satisfies all hard constraints without workarounds.

The only real decision within C# is `.NET 8 LTS` vs `.NET 9`. Use **.NET 9** — it ships the Fluent dark theme natively, which is the key UI upgrade this rewrite targets. Server 2019+ supports it.

---

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| C# | 13 (.NET 9) | Application language | Only language with native WPF, .NET Framework COM interop, full Windows API access, and a production-quality single-EXE deployment model. Every alternative has a blocking gap. |
| .NET 9 | 9.0 (latest patch) | Runtime and SDK | Ships Fluent dark theme for WPF natively. Supported on Windows Server 2019+. STS (Nov 2024 – May 2026); use .NET 8 LTS if you need >18 months of security patches without upgrades. |
| WPF | Ships with .NET 9 | GUI framework | Microsoft's own, battle-tested, runs on Server 2019, supports DPI-aware rendering, produces single-EXE. The only full-featured Windows desktop GUI available in the .NET ecosystem with active development in 2025/2026. |
| CommunityToolkit.Mvvm | 8.4.0 | MVVM pattern, source generators | Microsoft-maintained. `[ObservableProperty]` and `[RelayCommand]` source generators eliminate 80% of ViewModel boilerplate. Prevents the threading bugs that plagued the PowerShell version by enforcing clean separation of UI and logic. Compatible with .NET 9. |

### Windows Integration Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Microsoft.Data.SqlClient | 6.1.4 | SQL Server Express (SUSDB) connectivity | All database operations — replace every `Invoke-Sqlcmd` call from PowerShell. Latest stable (Jan 2026). Targets .NET 8+. |
| System.ServiceProcess.ServiceController | Ships with .NET | Windows service management (SQL, WSUS, IIS) | Starting, stopping, querying service status. No NuGet package needed — use `System.ServiceProcess` namespace directly. |
| Microsoft.Win32 namespace | Ships with .NET | Registry access, open/save file dialogs | Settings storage, path lookups, Windows standard file pickers. |
| System.Net.NetworkInformation | Ships with .NET | Non-blocking network connectivity check | Use `Ping` with 500ms timeout for dashboard internet check — avoids the UI freeze documented in PowerShell v3.8.7. |

### WSUS API Strategy — Critical Decision

The `Microsoft.UpdateServices.Administration.dll` COM assemblies **do not work with .NET Core / .NET 5+**. This was confirmed as a known limitation (GitHub dotnet/core issue #5736): "DLLs built for Framework will generally not work with Core." The assemblies chain-load .NET Framework dependencies and throw `FileNotFoundException` on modern .NET.

**Workaround approach used by the existing PowerShell version:** Direct SQL against SUSDB, plus `wsusutil.exe` process invocation for operations that require the WSUS API. This pattern is fully reproducible in C#:

| WSUS Operation | Implementation in C# |
|---|---|
| Decline superseded updates | Direct SQL: `UPDATE tbUpdate SET IsDeclined = 1 WHERE ...` |
| Delete updates (spDeleteUpdate) | Direct SQL: `EXEC spDeleteUpdate @localUpdateId` |
| Rebuild indexes | Direct SQL: standard index maintenance T-SQL |
| Shrink database | Direct SQL: `DBCC SHRINKDATABASE (SUSDB)` |
| Sync/approval operations | `Process.Start("wsusutil.exe")` or PowerShell subprocess |
| Content reset | `Process.Start("wsusutil.exe reset")` |

The IUpdateServer COM object (for sync, approval, classification) can be accessed by loading the assembly via reflection with explicit .NET Framework targeting, **or** by running a short PowerShell subprocess. The existing codebase already shells out to PowerShell for these — in the rewrite, shell out to PowerShell for the true COM-dependent operations (sync, approval), and do everything else natively in C#.

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Serilog | 4.x (latest) | Structured file logging | Replace the WsusUtilities `Write-Log` pattern. Use `Serilog.Sinks.File` for rolling log files at `C:\WSUS\Logs\`. More robust than manual file writes — handles concurrent access, rotation, and structured events. |
| Serilog.Sinks.File | 6.x (latest) | File sink for Serilog | Provides rolling log files with size/date rotation. |
| Microsoft.Extensions.DependencyInjection | 9.0.x | DI container | Wire up services, repositories, and ViewModels for testability. Prevents the closure-capture and scope bugs that plagued the PowerShell version's event handlers. |
| Microsoft.Extensions.Hosting | 9.0.x | Application host, lifecycle | Provides hosted services pattern for background refresh timer (30s dashboard) without manual thread management. |
| xunit | 2.9.x | Unit testing | Current standard for .NET testing. Better test isolation than NUnit. Fast parallel execution. |
| Moq | 4.20.x | Mocking in tests | Interface-based mocking for services (SQL, process launchers, Windows API wrappers). |
| DarkNet (Aldaviva/DarkNet) | latest | Native dark title bar on Windows 10/11 | WPF .NET 9 Fluent dark theme styles the client area; this library extends dark mode to the title bar and system chrome. Optional — verify Windows Server 2019 compatibility. |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| Visual Studio 2022 or Rider | IDE | VS 2022 required for .NET 9 Native AOT compilation toolchain (not needed for regular single-file publish). |
| `dotnet publish -r win-x64 -p:PublishSingleFile=true --self-contained true` | Single-EXE build | Produces one EXE with embedded runtime. Add `-p:PublishTrimmed=true` to reduce size; add `-p:PublishReadyToRun=true` for faster startup. Expect 40-80MB for self-contained WPF. |
| GitHub Actions with `windows-latest` runner | CI/CD | Existing pipeline. Replace PS2EXE step with `dotnet publish`. |
| PSScriptAnalyzer | No longer needed | Replaced by C# compile-time analysis. |

---

## Installation

```xml
<!-- In .csproj — core packages -->
<PackageReference Include="CommunityToolkit.Mvvm" Version="8.4.0" />
<PackageReference Include="Microsoft.Data.SqlClient" Version="6.1.4" />
<PackageReference Include="Microsoft.Extensions.DependencyInjection" Version="9.0.*" />
<PackageReference Include="Microsoft.Extensions.Hosting" Version="9.0.*" />

<!-- Logging -->
<PackageReference Include="Serilog" Version="4.*" />
<PackageReference Include="Serilog.Sinks.File" Version="6.*" />

<!-- Testing (test project only) -->
<PackageReference Include="xunit" Version="2.9.*" />
<PackageReference Include="Moq" Version="4.20.*" />
<PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.*" />
<PackageReference Include="xunit.runner.visualstudio" Version="2.8.*" />
```

```xml
<!-- In .csproj — build configuration for single-file EXE -->
<PropertyGroup>
  <OutputType>WinExe</OutputType>
  <TargetFramework>net9.0-windows</TargetFramework>
  <RuntimeIdentifier>win-x64</RuntimeIdentifier>
  <UseWPF>true</UseWPF>
  <PublishSingleFile>true</PublishSingleFile>
  <SelfContained>true</SelfContained>
  <PublishReadyToRun>true</PublishReadyToRun>
  <PublishTrimmed>false</PublishTrimmed>  <!-- WPF is not trim-compatible -->
  <IncludeNativeLibrariesForSelfExtract>true</IncludeNativeLibrariesForSelfExtract>
</PropertyGroup>
```

> **Note on PublishTrimmed:** WPF is not trim-compatible as of .NET 9. Do not enable trimming — it will break XAML bindings and reflection-based features silently. This is confirmed in the WPF GitHub issues.

> **Note on NativeAOT:** WPF does not support NativeAOT as of .NET 9. Do not use it.

---

## Alternatives Considered and Rejected

### Rust

| Criterion | Assessment |
|---|---|
| GUI framework | No mature, production-ready Windows-native GUI framework. The 2025 survey of Rust GUI libraries confirms fragmentation — NWG (native-windows-gui), Freya, Dioxus all have significant gaps or are cross-platform (not Windows-native). |
| Windows API / COM | `windows-rs` crate provides COM access and is actively developed by Microsoft. Technically viable. |
| WSUS COM interop | No evidence of anyone successfully using WSUS COM API from Rust. Would require significant FFI work. |
| Single EXE | Yes — Rust produces small static binaries. |
| Developer productivity | Borrow checker adds significant overhead for GUI state management (shared mutable UI state is exactly what Rust makes hard). |
| Verdict | REJECTED. GUI ecosystem not production-ready for this use case. High risk, high cost. |

### Go

| Criterion | Assessment |
|---|---|
| GUI framework | `walk` (lxn/walk) is the most Windows-native option but is significantly behind WPF in feature maturity. Low active development in recent years. |
| Windows API | WMI access via several packages (StackExchange/wmi, microsoft/wmi). Functional but requires CGO or specialized wrappers for COM. |
| WSUS COM interop | WMI packages use COM under the hood for WMI queries. But WSUS API (IUpdateServer, IUpdateServer2) goes beyond WMI — no established Go path. |
| Single EXE | Yes — Go produces single static binaries natively. |
| SQL access | Available via `database/sql` + driver, but no SqlClient equivalent mature. |
| Developer productivity | Go ecosystem is excellent for backends/CLI; desktop GUI is second-class. Compared to C# for Windows admin tools, Go provides less value. |
| Verdict | REJECTED. No viable WSUS COM interop path, immature GUI framework. |

### Electron / Tauri (web-based)

| Criterion | Assessment |
|---|---|
| Admin tool fit | Admin tools on Windows with complex OS integration are a poor fit for web-stack GUIs. |
| Single EXE | Tauri can produce single EXE; Electron cannot easily. |
| Windows API | P/Invoke through native modules possible but cumbersome. |
| Air-gap deployment | Tauri (Rust backend) is viable; Electron requires Node.js runtime. |
| Verdict | REJECTED. Complexity for Windows API work outweighs benefits. Not the right tool. |

### .NET 8 LTS vs .NET 9 STS

Both are valid choices. The tradeoff:

- **.NET 9 (recommended):** Fluent dark theme ships built-in (the key UI upgrade). Supported until May 2026. Upgrade to .NET 10 LTS when it ships (Nov 2025 — already available).
- **.NET 8 LTS:** Supported until Nov 2026. No native Fluent theme (requires manual Fluent resource dictionary approach or third-party themes). More conservative choice if upgrade cadence is a concern.

**Recommendation:** Use .NET 9, then upgrade to .NET 10 as part of the v4.1 maintenance cycle. The Fluent theme is a core requirement of the rewrite and should not be a bolt-on.

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `System.Data.SqlClient` (old namespace) | Deprecated by Microsoft as of 2024. Security updates stopped. | `Microsoft.Data.SqlClient` 6.x |
| `BinaryFormatter` | Removed in .NET 9. Was unsafe (deserialization attacks). | `System.Text.Json` for settings |
| Native AOT with WPF | WPF does not support NativeAOT as of .NET 9. Compilation fails. | Standard self-contained publish |
| `PublishTrimmed=true` with WPF | WPF is not trim-compatible — breaks XAML binding reflection silently. | Omit `PublishTrimmed` |
| `Assembly.CodeBase` | Throws `PlatformNotSupportedException` in single-file apps. | `AppContext.BaseDirectory` |
| `Register-ObjectEvent` pattern | PowerShell-only threading workaround. Replaced by native `async/await`. | `async Task` methods throughout |
| Code-behind in XAML (beyond constructor) | Couples UI to business logic, same trap as the PowerShell version. | MVVM ViewModels with `[RelayCommand]` |
| Microsoft.UpdateServices.Administration | Does not work with .NET Core / .NET 5+. Throws `FileNotFoundException`. | Direct SQL against SUSDB + `wsusutil.exe` subprocess |
| PS2EXE | PowerShell-specific compile tool. Not applicable to C#. | `dotnet publish -p:PublishSingleFile=true` |
| WinForms | Less capable than WPF for the dark theme, XAML styling, and DPI-aware layout needed here. Lower-level API for complex UIs. | WPF |

---

## Version Compatibility Notes

| Package | Compatible With | Notes |
|---------|-----------------|-------|
| CommunityToolkit.Mvvm 8.4.0 | .NET 8, .NET 9, .NET Standard 2.0 | C# 13 partial properties feature for `[ObservableProperty]` requires .NET 9 SDK. Falls back gracefully on .NET 8. |
| Microsoft.Data.SqlClient 6.1.4 | .NET 8.0+, .NET Framework 4.6.2+ | Does NOT target .NET Standard 2.0 (dropped in v5+). Must use .NET 8+ target. |
| WPF Fluent ThemeMode API | .NET 9 on Windows 10+ (build 1809+) | Windows Server 2019 = build 1809. Fluent theme is confirmed compatible. Dark mode works. `ThemeMode` in code is experimental in .NET 9, stabilized in .NET 10. |
| Self-contained single EXE | Windows Server 2019 64-bit | `win-x64` RuntimeIdentifier required. Native libraries extract to `%TEMP%\.net` on first run. Subsequent runs use cached extraction — near-instant startup. |

---

## Stack Patterns

**For WSUS operations requiring COM API (sync, approval):**
- Shell out to a short PowerShell one-liner: `Start-Process powershell -ArgumentList "-NonInteractive -Command ..."`
- Or keep one thin PowerShell wrapper script alongside the EXE for these specific operations
- Do not attempt to load `Microsoft.UpdateServices.Administration.dll` in .NET 9 — it will fail

**For database operations (everything else):**
- Use `Microsoft.Data.SqlClient` directly with connection string `Server=localhost\SQLEXPRESS;Database=SUSDB;Integrated Security=true;TrustServerCertificate=true`
- Wrap in a `ISqlHelper` interface for unit testability

**For Windows service management:**
- Use `System.ServiceProcess.ServiceController` for status/start/stop
- No additional NuGet package needed

**For single-EXE with air-gapped deployment:**
- `SelfContained=true` + `PublishSingleFile=true` + `win-x64`
- EXE is fully self-contained — no .NET runtime on target machine required
- Expected size: 40-80MB (WPF + .NET runtime embedded)
- No internet dependency at runtime — all libraries embedded

---

## Sources

- [What's New in WPF for .NET 9 — Microsoft Learn](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/whats-new/net90) — Fluent theme, ThemeMode API, Windows Server 2019 compatibility (HIGH confidence)
- [Single-File Deployment Overview — Microsoft Learn](https://learn.microsoft.com/en-us/dotnet/core/deploying/single-file/overview) — PublishSingleFile constraints, NativeAOT limitations, extraction behavior (HIGH confidence)
- [NuGet: Microsoft.Data.SqlClient 6.1.4](https://www.nuget.org/packages/Microsoft.Data.SqlClient) — Latest stable version, target frameworks (HIGH confidence)
- [NuGet: CommunityToolkit.Mvvm 8.4.0](https://www.nuget.org/packages/CommunityToolkit.Mvvm) — Latest stable version, .NET 9 compatibility (HIGH confidence)
- [dotnet/core Issue #5736](https://github.com/dotnet/core/issues/5736) — Microsoft.UpdateServices.Administration.dll incompatibility with .NET Core/5+ (HIGH confidence — official repo)
- [2025 Survey of Rust GUI Libraries — boringcactus](https://www.boringcactus.com/2025/04/13/2025-survey-of-rust-gui-libraries.html) — Rust GUI ecosystem maturity assessment (MEDIUM confidence)
- [Rust for Windows — Microsoft Learn](https://learn.microsoft.com/en-us/windows/dev-environment/rust/rust-for-windows) — windows-rs crate COM capabilities (HIGH confidence)
- [Should You Use WPF with .NET in 2025? — Inedo Blog](https://blog.inedo.com/dotnet/wpf-on-dotnet) — WPF viability in 2025 (MEDIUM confidence)
- [CommunityToolkit.Mvvm Introduction — Microsoft Learn](https://learn.microsoft.com/en-us/dotnet/communitytoolkit/mvvm/) — MVVM Toolkit official docs (HIGH confidence)
- [Serilog .NET 9 Structured Logging — Medium](https://medium.com/@michaelmaurice410/how-structured-logging-with-serilog-in-net-9-980229322ebe) — Serilog .NET 9 compatibility (MEDIUM confidence)

---

*Stack research for: Windows Server WSUS Administration GUI Tool (GA-WsusManager v4)*
*Researched: 2026-02-19*
