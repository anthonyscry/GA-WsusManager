# GA-WsusManager v4 — C# Rewrite

## What This Is

A production-ready C#/.NET 8 WPF application for managing WSUS servers with SQL Server Express on Windows Server 2019+. Delivers full feature parity with the PowerShell v3.8.12 in a single-file EXE with zero threading bugs, sub-second startup, and native async operations. Includes a complete client troubleshooting toolkit with WinRM remote operations, mass host management, and PowerShell script generation for air-gapped environments. Built for GA-ASI IT administrators managing critical WSUS infrastructure.

## Core Value

Rock-solid stability — zero crashes, no threading bugs, no UI freezes — so administrators trust it to manage critical WSUS infrastructure on production servers.

## Requirements

### Validated

- ✓ Single-file EXE distribution (no Scripts/Modules folders) — v4.0
- ✓ Sub-second application startup — v4.0
- ✓ Native async operations (no threading hacks) — v4.0
- ✓ Modernized dark theme UI — v4.0
- ✓ Type-safe compiled code — v4.0
- ✓ All PowerShell module functionality ported — v4.0
- ✓ 257 xUnit tests covering all services and ViewModel logic — v4.0
- ✓ 62 v1 requirements implemented and verified — v4.0

- ✓ .NET 8 SDK compatibility (retarget from .NET 9) — v4.1
- ✓ App launches and UI renders correctly with active nav highlighting — v4.1
- ✓ 5 critical operation bugs fixed (sync, cleanup, health check) — v4.1
- ✓ Button CanExecute refresh for proper visual disabling — v4.1
- ✓ 263 xUnit tests passing — v4.1

- ✓ Editable settings dialog with JSON persistence and immediate effect — v4.2
- ✓ Dashboard mode toggle with manual Online/Air-Gap override — v4.2
- ✓ Operation progress bar, step tracking, success/failure banners — v4.2
- ✓ Real-time dialog validation (Install, Transfer, Schedule) — v4.2
- ✓ WinRM client management: cancel stuck jobs, force check-in, test connectivity, diagnostics — v4.2
- ✓ Error code lookup (20 common WSUS/WU codes) — v4.2
- ✓ Mass GPUpdate across multiple hosts — v4.2
- ✓ Script Generator producing self-contained PowerShell fallback scripts — v4.2
- ✓ 336 xUnit tests passing — v4.2

### Active

(Next milestone requirements will be defined via `/gsd:new-milestone`)

### Out of Scope

- Mobile or web-based interface — desktop-only for server administration
- Linux/macOS support — Windows Server only (WSUS is Windows-only)
- Server 2016 support — targeting 2019+ only
- Real-time multi-server management — single server at a time
- PowerShell script backward compatibility — clean break from PS codebase
- Building on C# POC — started fresh per user preference
- Active Directory browser — use existing AD tools, just accept hostnames
- Client-side agent/service — admin tool only, not a client endpoint
- SCCM/Intune integration — different tooling ecosystem

## Context

### Current State
- **Version:** v4.2 shipped 2026-02-21
- **Codebase:** ~21,000 LOC C# across 97 .cs + 8 .xaml files
- **Tech stack:** C#/.NET 8, WPF, CommunityToolkit.Mvvm, Serilog, xUnit + Moq
- **Tests:** 336 xUnit tests
- **CI/CD:** GitHub Actions `build-csharp.yml` — build, test, publish, release
- **Distribution:** Single self-contained win-x64 EXE + DomainController/ folder

### Technical Environment
- Windows Server 2019/2022 with WSUS role installed
- SQL Server Express 2022 (localhost\SQLEXPRESS) with 10GB limit
- SUSDB database for WSUS metadata
- Standard paths: C:\WSUS\ (content), C:\WSUS\Logs\ (logs)
- Ports: 8530 (HTTP), 8531 (HTTPS)
- Air-gapped networks require USB-based export/import workflow

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Full C# rewrite (not incremental port) | PowerShell had fundamental threading/deployment limitations | ✓ Good — eliminated 12+ anti-patterns |
| Start fresh (ignore C# POC) | Clean architecture with modern patterns | ✓ Good — cleaner DI and MVVM |
| Single-file EXE distribution | Simplifies deployment on production servers | ✓ Good — no Scripts/Modules folders |
| .NET 8 self-contained | No runtime installation required, .NET 8 LTS available on dev machines | ✓ Good — works on clean Windows Server |
| Drop Server 2016 support | Allows targeting modern .NET runtime | ✓ Good — simplified targeting |
| CommunityToolkit.Mvvm for MVVM | Source generators, less boilerplate | ✓ Good — clean ViewModel pattern |
| Runtime-load WSUS API assembly | Ships with WSUS role, not NuGet | ✓ Good — no compile-time dependency |
| schtasks.exe for scheduled tasks | Simpler than COM TaskScheduler API | ✓ Good — no NuGet dep needed |
| Shell out to PS for WSUS install | Install script too complex to rewrite | ✓ Good — reuses proven logic |
| Separate CI workflow (build-csharp.yml) | Keeps PowerShell build.yml untouched | ✓ Good — no conflicts |
| Settings dialog as modal (not panel) | Configuration is transient, not persistent view | ✓ Good — always accessible |
| Sequential WinRM for mass operations | Prevent network saturation on large batches | ✓ Good — reliable for 50+ hosts |
| Verbatim strings for PS script templates | Avoids C# interpolation conflicts with PowerShell $() | ✓ Good — clean separation |
| WinRM pre-check before every remote op | Fail fast with clear message and Script Generator guidance | ✓ Good — better UX than timeout |

## Constraints

- **Target OS**: Windows Server 2019+ (64-bit only)
- **Admin Required**: All operations require elevated privileges
- **SQL Express**: Must work with localhost\SQLEXPRESS and 10GB database limit
- **Air-Gap**: Export/import must work fully offline — no internet dependency
- **Single EXE**: Distribution must be a single executable file
- **WSUS APIs**: Must interact with Microsoft.UpdateServices.Administration and SUSDB directly

---
*Last updated: 2026-02-21 after v4.2 milestone completion*
