# GA-WsusManager v4 — C# Rewrite

## What This Is

A production-ready C#/.NET 8 WPF application for managing WSUS servers with SQL Server Express on Windows Server 2019+. Delivers full feature parity with the PowerShell v3.8.12 in a single-file EXE with zero threading bugs, sub-second startup, and native async operations. Built for GA-ASI IT administrators managing critical WSUS infrastructure, including air-gapped networks.

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

### Active

## Current Milestone: v4.2 UX & Client Management

**Goal:** Polish the user experience and add client troubleshooting tools so admins can diagnose and fix stuck WSUS clients directly from the GUI.

**Target features:**
- Editable settings dialog (currently read-only)
- Operation progress feedback (progress bars, status indicators)
- Dialog polish (install, export/import, restore, schedule)
- Client troubleshooting tools (cancel stuck jobs, force check-in, mass GPUpdate, connectivity testing, diagnostics, error code lookup)
- Manual offline/Air-Gap mode override (dashboard toggle + settings persistence)

### Out of Scope

- Mobile or web-based interface — desktop-only for server administration
- Linux/macOS support — Windows Server only (WSUS is Windows-only)
- Server 2016 support — targeting 2019+ only
- Real-time multi-server management — single server at a time
- PowerShell script backward compatibility — clean break from PS codebase
- Building on C# POC — started fresh per user preference

## Context

### Current State
- **Version:** v4.1 shipped 2026-02-20
- **Codebase:** ~13,000 LOC C# across 88 .cs + 8 .xaml files
- **Tech stack:** C#/.NET 8, WPF, CommunityToolkit.Mvvm, Serilog, xUnit + Moq
- **Tests:** 263 xUnit tests (263 on WSL, ~277 on Windows CI with WPF)
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

## Constraints

- **Target OS**: Windows Server 2019+ (64-bit only)
- **Admin Required**: All operations require elevated privileges
- **SQL Express**: Must work with localhost\SQLEXPRESS and 10GB database limit
- **Air-Gap**: Export/import must work fully offline — no internet dependency
- **Single EXE**: Distribution must be a single executable file
- **WSUS APIs**: Must interact with Microsoft.UpdateServices.Administration and SUSDB directly

---
*Last updated: 2026-02-20 after v4.2 milestone start*
