# WSUS Manager

**Version:** 3.8.13
**Author:** Tony Tran, ISSO, GA-ASI

WSUS Manager is a PowerShell WPF automation suite for Windows Server Update Services (WSUS) with SQL Server Express 2022. It provides a modern GUI for managing WSUS servers in both connected and air-gapped environments.

## Features

- PowerShell WPF GUI with dark theme
- Auto-refresh dashboard (30-second interval)
- Unified Diagnostics operation (health check + repair)
- Deep Cleanup database maintenance workflow
- Online Sync with Full, Quick, and Sync Only profiles
- Air-gap export/import operations
- Scheduled task integration
- Client check-in and GPO deployment utilities

## Quick Start

1. Go to the [Releases](../../releases) page
2. Download `WsusManager-vX.X.X.zip`
3. Extract the archive
4. Run `WsusManager.exe` as Administrator

**Important:** Deploy the full package. `WsusManager.exe` requires `Scripts/` and `Modules/` in the same directory.

## Requirements

- Windows 10/11 or Windows Server 2019/2022
- PowerShell 5.1+
- Administrator privileges
- WSUS role and SQL Server Express 2022 (installed by setup workflow if needed)

## Build and Test

```powershell
# Full build (tests + code analysis + compile)
.\build.ps1

# Build without tests
.\build.ps1 -SkipTests

# Tests only
.\build.ps1 -TestOnly

# Run Pester directly
Invoke-Pester -Path .\Tests -Output Detailed

# Run code analysis
Invoke-ScriptAnalyzer -Path .\Scripts\WsusManagementGui.ps1 -Severity Error,Warning
```

Build output is placed in `dist/` as `WsusManager.exe` and `WsusManager-vX.X.X.zip`.

## Standard WSUS Paths

- Content path: `C:\WSUS\`
- SQL instance: `localhost\SQLEXPRESS`
- Logs: `C:\WSUS\Logs\`
- WSUS ports: 8530 (HTTP), 8531 (HTTPS)

## Project Structure

```
GA-WsusManager/
├── build.ps1
├── Scripts/
│   ├── WsusManagementGui.ps1
│   ├── Invoke-WsusManagement.ps1
│   ├── Invoke-WsusMonthlyMaintenance.ps1
│   ├── Install-WsusWithSqlExpress.ps1
│   ├── Invoke-WsusClientCheckIn.ps1
│   └── Set-WsusHttps.ps1
├── Modules/
│   ├── WsusUtilities.psm1
│   ├── WsusDatabase.psm1
│   ├── WsusHealth.psm1
│   ├── WsusServices.psm1
│   ├── WsusFirewall.psm1
│   ├── WsusPermissions.psm1
│   ├── WsusConfig.psm1
│   ├── WsusExport.psm1
│   ├── WsusScheduledTask.psm1
│   ├── WsusAutoDetection.psm1
│   └── AsyncHelpers.psm1
├── Tests/
├── DomainController/
├── docs/
├── CLAUDE.md
└── README.md
```

## Usage

Run `WsusManager.exe` as Administrator, then use:

- **Diagnostics** for health checks and auto-repair
- **Database** for backup, restore, and deep cleanup
- **WSUS Operations** for sync and transfer workflows
- **Client Tools** for client-side WSUS actions
- **Schedule** to automate recurring operations

## Troubleshooting

- **Operation window is blank before dialog**: show dialogs before switching panels
- **Curly brace object output in logs**: suppress return values with `$null =` or `| Out-Null`
- **No output from external process**: ensure async readers are started
- **UI update errors from background handlers**: marshal UI changes through dispatcher
- **Buttons remain enabled during long operations**: verify operation-state guard is active
- **Script not found errors**: validate script paths before invocation

See [CLAUDE.md](CLAUDE.md) for detailed development guidance and known issue patterns.

## Contributing

Please follow [CONTRIBUTING.md](CONTRIBUTING.md) for development workflow, testing expectations, and PR checklist.

## License

This project is proprietary software developed for GA-ASI internal use.
