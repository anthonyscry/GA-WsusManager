# Developer Guide

Current version: **4.1.0**

GA-WsusManager is a Windows PowerShell 5.1 / WPF app. The compiled release EXE wraps `Scripts/WsusManagementGui.ps1` and must be deployed with `Scripts\`, `Modules\`, and `icons\` beside it.

## Repository layout

```text
build.ps1
metadata.json
Scripts\
Modules\
DomainController\
icons\
docs\
wiki\
Tests\
dist\                 generated locally
```

Do not resurrect the archived C# rewrite. Current app code is PowerShell/WPF.

## Build

Use Windows PowerShell 5.1:

```powershell
.\build.ps1 -SkipTests -SkipCodeReview -NoPush
```

Outputs:

```text
dist\GA-WsusManager.exe
dist\GA-WsusManager-v4.1.0.zip
```

GitHub releases attach only the zip. The standalone EXE remains inside the zip.

## Versioning

`metadata.json` is the release version source of truth. `build.ps1`, CLI scripts, maintenance scripts, and the GUI version initialization use it through `Get-WsusAppVersion` when modules are available.

Update these together for a release:

1. `metadata.json`
2. `CHANGELOG.md`
3. `wiki/Changelog.md`
4. release notes on GitHub

## Packaging requirements

The zip must include:

```text
GA-WsusManager.exe
Scripts\
Modules\
icons\
DomainController\
metadata.json
README.md
QUICK-START.txt
```

`icons\` contains window/tray/sidebar/About assets. The app resolves icons from `icons\` first.

## Tests

Targeted commands:

```powershell
Invoke-Pester -Path .\Tests\Integration.Tests.ps1 -Output Detailed
Invoke-Pester -Path .\Tests\WsusHealth.Tests.ps1 -Output Detailed
Invoke-Pester -Path .\Tests\WsusGroupPolicy.Tests.ps1 -Output Detailed
Invoke-Pester -Path .\Tests\WsusPermissions.Tests.ps1 -Output Detailed
Invoke-Pester -Path .\Tests\ProductFilter.Tests.ps1 -Output Detailed
```

Use GUI/FlaUI tests only in an interactive Windows desktop session.

## Important implementation notes

- GUI long operations launch child `powershell.exe` processes.
- Secrets go through environment variables, not command-line arguments.
- SQL operations prefer SqlServer/Invoke-Sqlcmd when available and fall back where implemented.
- Robocopy exit codes `0..7` are success.
- Health Score is services/database/disk only.
- GPO deployment is handled by `DomainController\Set-WsusGroupPolicy.ps1`, not a GUI Create GPO menu item.

## Related pages

- [[Module Reference]]
- [[Configuration Guide]]
- [[Changelog]]
