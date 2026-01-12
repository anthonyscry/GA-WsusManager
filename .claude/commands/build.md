# Build WSUS Manager

Build the WSUS Manager executable and distribution package.

## Instructions

1. Full build with tests and code review:
```powershell
.\build.ps1
```

2. Quick build (skip tests):
```powershell
.\build.ps1 -SkipTests
```

3. Quick build (skip code review):
```powershell
.\build.ps1 -SkipCodeReview
```

4. Test only (no build):
```powershell
.\build.ps1 -TestOnly
```

## Build Process

The build script performs:
1. **Code Review**: PSScriptAnalyzer checks on Scripts and Modules
2. **Pester Tests**: Runs 323+ unit tests
3. **Compile**: Converts WsusManagementGui.ps1 to WsusManager.exe using PS2EXE
4. **Package**: Creates WsusManager-vX.X.X.zip distribution
5. **Distribute**: Copies to dist folder
6. **Git**: Commits and pushes dist folder

## Outputs

After successful build:
- `.\WsusManager.exe` - The executable
- `.\WsusManager-v3.8.0.zip` - Distribution package
- `.\dist\` - Git-tracked copies

## Version Updates

Update version in two places before release:
1. `build.ps1` line 45: `$Version = "X.X.X"`
2. `Scripts\WsusManagementGui.ps1`: `$script:AppVersion`
