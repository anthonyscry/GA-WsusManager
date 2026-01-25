# WSUS Manager

**Version:** 3.8.10
**Author:** Tony Tran, ISSO, Classified Computing, GA-ASI

A comprehensive PowerShell-based automation suite for Windows Server Update Services (WSUS) with SQL Server Express 2022. Provides both a modern WPF GUI application and CLI scripts for managing WSUS servers, including support for air-gapped networks.

## Features

- **Modern WPF GUI** - Dark theme dashboard with real-time status monitoring
- **Unified Diagnostics** - Comprehensive health checks with automatic repair in one operation
- **Deep Cleanup** - Full database maintenance including supersession cleanup, index optimization, and compaction
- **Air-Gap Support** - Export/import operations for offline networks with Reset Content for post-import fixes
- **Definition Updates** - Security definitions (antivirus signatures) now auto-approved alongside critical updates
- **Scheduled Maintenance** - Automated online sync with configurable profiles
- **HTTPS/SSL Support** - Easy SSL certificate configuration
- **Enhanced UI Feedback** - Real-time progress bars, password strength validation, confirmation dialogs
- **Improved Navigation** - Visual selected state indicator on sidebar buttons
- **Advanced Log Management** - Filter logs by type (Info/Warning/Error) and search functionality

## Quick Start

### Download Pre-built EXE

1. Go to the [Releases](../../releases) page
2. Download `WsusManager-vX.X.X.zip`
3. Extract to `C:\WSUS\` (recommended) or any folder
4. Run `WsusManager.exe` as Administrator

**Important:** Keep the `Scripts/` and `Modules/` folders in the same directory as the EXE.

### Building from Source

```powershell
# Clone the repository
git clone https://github.com/anthonyscry/GA-WsusManager.git
cd GA-WsusManager

# Run the build script (requires PS2EXE module)
.\build.ps1

# Output will be in dist/WsusManager.exe
```

Build options:
```powershell
.\build.ps1              # Full build with tests and code review
.\build.ps1 -SkipTests   # Build without running tests
.\build.ps1 -TestOnly    # Run tests only (no build)
```

## Requirements

- **Windows Server** 2016, 2019, 2022, or Windows 10/11
- **PowerShell** 5.1 or later
- **Administrator privileges** (required for WSUS operations)
- **SQL Server Express** 2022 (installed by the Install WSUS feature)

## Project Structure

```
GA-WsusManager/
├── Scripts/                 # PowerShell operation scripts
│   ├── WsusManagementGui.ps1       # Main GUI application
│   ├── Invoke-WsusManagement.ps1   # CLI for all operations
│   ├── Invoke-WsusMonthlyMaintenance.ps1
│   ├── Install-WsusWithSqlExpress.ps1
│   ├── Set-WsusHttps.ps1
│   └── Invoke-WsusClientCheckIn.ps1
├── Modules/                 # Reusable PowerShell modules (11 total)
├── Tests/                   # Pester unit tests (323 tests)
├── DomainController/        # GPO deployment scripts
├── build.ps1               # Build script
└── CLAUDE.md               # Development documentation
```

## CLI Usage

```powershell
# Run comprehensive diagnostics (scans and auto-fixes issues)
.\Scripts\Invoke-WsusManagement.ps1 -Diagnostics

# Run deep cleanup (supersession records, indexes, compaction)
.\Scripts\Invoke-WsusManagement.ps1 -Cleanup -Force

# Reset content verification (use after database import on air-gapped servers)
.\Scripts\Invoke-WsusManagement.ps1 -Reset

# Export for air-gapped network
.\Scripts\Invoke-WsusManagement.ps1 -Export -DestinationPath "E:\WSUS-Export"

# Schedule online sync
.\Scripts\Invoke-WsusManagement.ps1 -Schedule -MaintenanceProfile Full
```

## Recent Changes (v3.8.10)

### Deep Cleanup Fix
The Deep Cleanup operation now performs all advertised database maintenance:
1. **WSUS built-in cleanup** - Decline superseded, remove obsolete updates
2. **Supersession record cleanup** - Removes stale records from `tbRevisionSupersedesUpdate`
3. **Declined update deletion** - Purges declined updates via `spDeleteUpdate`
4. **Index optimization** - Rebuilds/reorganizes fragmented indexes
5. **Statistics update** - Refreshes query optimizer statistics
6. **Database compaction** - Shrinks database to reclaim disk space

### Unified Diagnostics
Health Check and Repair have been consolidated into a single **Diagnostics** operation that:
- Scans all WSUS components (services, database, firewall, permissions)
- Automatically fixes detected issues
- Reports results with clear pass/fail status

### Security Definitions Auto-Approval
Definition Updates (antivirus signatures, security definitions) are now automatically approved alongside other update classifications:
- Critical Updates, Security Updates, Update Rollups, Service Packs, Updates, **Definition Updates**
- Upgrades still require manual review

### Reset Content Button
New button for air-gapped servers to fix "content is still downloading" status after database import:
- Runs `wsusutil reset` to re-verify content files against database
- Use after importing a database backup when content files are already present

## Important Notes

### Database Restore / Reset Time

After restoring a WSUS database or performing a reset operation, the WSUS server will need to re-verify and re-download update content. **This process can take 30+ minutes depending on the size of your update content.** During this time:

- The dashboard may show "Update is downloading" status
- This is normal behavior - do not interrupt the process
- Content verification happens automatically in the background
- Large content stores (50GB+) may take several hours to fully re-verify

## Documentation

- **[CLAUDE.md](CLAUDE.md)** - Comprehensive development documentation
- **[Modules/README.md](Modules/README.md)** - PowerShell module reference
- **[wiki/](wiki/)** - User guides and troubleshooting

## Testing

```powershell
# Run all tests
Invoke-Pester -Path .\Tests -Output Detailed

# Run specific module tests
Invoke-Pester -Path .\Tests\WsusHealth.Tests.ps1

# Run tests with code coverage
Invoke-Pester -Path .\Tests -CodeCoverage .\Modules\*.psm1
```

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Run tests before committing (`.\build.ps1 -TestOnly`)
4. Commit your changes (`git commit -m 'Add amazing feature'`)
5. Push to the branch (`git push origin feature/amazing-feature`)
6. Open a Pull Request

## License

This project is proprietary software developed for GA-ASI internal use.

## Support

- **Issues:** [GitHub Issues](../../issues)
- **Documentation:** See [CLAUDE.md](CLAUDE.md) for detailed development docs
