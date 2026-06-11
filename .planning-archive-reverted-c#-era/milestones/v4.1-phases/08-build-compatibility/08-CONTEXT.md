# Phase 8 Context: Build Compatibility

## Decisions

### .NET 8 Retargeting

**Already done (pre-phase):**
- All three csproj files retargeted from `net9.0-windows` to `net8.0-windows`:
  - `src/WsusManager.Core/WsusManager.Core.csproj`
  - `src/WsusManager.App/WsusManager.App.csproj`
  - `src/WsusManager.Tests/WsusManager.Tests.csproj`
- Package references downgraded from `9.0.*` to `8.0.*` for:
  - `Microsoft.Extensions.DependencyInjection.Abstractions`
  - `System.ServiceProcess.ServiceController`
  - `Microsoft.Extensions.DependencyInjection`
  - `Microsoft.Extensions.Hosting`
- `bin/` and `obj/` directories cleaned

**What remains (two items):**

1. **`ExeValidationTests.cs` line 36** — hardcoded path segment `net9.0-windows` in the fallback
   search path for the published EXE:
   ```csharp
   Path.Combine(testDir, "..", "..", "..", "..", "WsusManager.App", "bin", "Release",
       "net9.0-windows", "win-x64", "publish", ExeName),
   ```
   This path segment must be updated to `net8.0-windows`. The test only hits this path during
   local development (not CI, which uses `WSUS_EXE_PATH`), but it is still wrong and will cause
   the fallback EXE search to silently miss the file.

2. **`build-csharp.yml` line 42** — SDK setup step installs .NET 9, not .NET 8:
   ```yaml
   - name: Setup .NET 9 SDK
     uses: actions/setup-dotnet@v4
     with:
       dotnet-version: 9.0.x
   ```
   Both the step name and `dotnet-version` must change to `8.0.x`.

### CI/CD Updates

**`build-csharp.yml` changes required:**

| Location | Current | Required |
|----------|---------|---------|
| Step name (line 39) | `Setup .NET 9 SDK` | `Setup .NET 8 SDK` |
| `dotnet-version` (line 42) | `9.0.x` | `8.0.x` |

No other workflow changes are needed. The `windows-latest` runner in GitHub Actions ships with
the .NET 8 SDK already, so the `actions/setup-dotnet` step could technically be removed, but
pinning the SDK version explicitly is the safer practice for reproducible builds.

The restore, build, test, publish, and artifact steps are all framework-agnostic — they read
`TargetFramework` from the csproj files directly.

### API Compatibility

**`Stream.ReadExactly()`** is used in `ExeValidationTests.cs` (lines 67, 84, 90, 110, 117).
This method was introduced in .NET 7, so it is fully available in .NET 8. No change needed.

**WSUS Managed API comment** in `DeepCleanupService.cs` (line 109) says:
> "WSUS managed API is incompatible with .NET 9 — must use PS subprocess"

This comment is factually correct and still applies to .NET 8 as well (the WSUS managed API
`Microsoft.UpdateServices.Administration` targets .NET Framework only). The comment wording
will remain accurate under .NET 8; no code change is needed, but the comment can optionally be
updated to say ".NET" instead of ".NET 9" for accuracy.

**No other .NET 9-specific APIs are used** in the codebase. The code uses:
- `Microsoft.Extensions.*` 8.0.x — fully stable under .NET 8
- `CommunityToolkit.Mvvm` 8.4.0 — targets `netstandard2.0`; works on .NET 8
- `Microsoft.Data.SqlClient` 6.1.4 — targets `netstandard2.0` and `net8.0`; no issue
- `Serilog` 4.x and `Serilog.Sinks.File` 6.x — `netstandard2.0` targets; compatible
- `Moq` 4.20.x and `xunit` 2.9.x — fully .NET 8 compatible

**No API incompatibilities exist.** The downgrade from .NET 9 to .NET 8 is purely a TFM change
with no API surface differences affecting this codebase.

### Verification Approach

**Step 1 — Fix the two remaining items:**
- Update `ExeValidationTests.cs` path segment from `net9.0-windows` to `net8.0-windows`
- Update `build-csharp.yml` step name and `dotnet-version` from `9.0.x` to `8.0.x`

**Step 2 — Local build verification (on Windows with .NET 8 SDK):**
```powershell
cd src
dotnet restore
dotnet build --configuration Release
dotnet test --configuration Release --filter "FullyQualifiedName!~ExeValidation&FullyQualifiedName!~DistributionPackage"
dotnet publish WsusManager.App/WsusManager.App.csproj --configuration Release --output ../publish --self-contained true --runtime win-x64 -p:PublishSingleFile=true
```

**Step 3 — EXE validation (run after publish):**
```powershell
$env:WSUS_EXE_PATH = "../publish/WsusManager.App.exe"
dotnet test --configuration Release --filter "FullyQualifiedName~ExeValidation"
```

**Step 4 — Verify target framework in build output:**
```powershell
# Confirm net8.0-windows in publish path
ls ../publish
# Should produce: WsusManager.App.exe (single-file, ~15-20 MB)
```

**Step 5 — CI validation:** Push to `main` (or open a PR). The updated `build-csharp.yml` will
install the .NET 8 SDK and run the full pipeline. The build-and-test job must pass all stages:
restore → build → test → publish → EXE validation → smoke test.

**Acceptance criteria (COMPAT-01 / COMPAT-02 / COMPAT-03):**
- COMPAT-01: `dotnet build` succeeds with `net8.0-windows` TFM
- COMPAT-02: GitHub Actions pipeline passes using `dotnet-version: 8.0.x`
- COMPAT-03: Published single-file EXE runs on Windows Server 2019+ (x64) without requiring
  an installed .NET runtime (self-contained, `win-x64`)
