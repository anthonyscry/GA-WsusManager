# Contributing to WSUS-SQL

Thank you for your interest in contributing to WSUS-SQL! This document provides guidelines and information for contributors.

## Getting Started

### Prerequisites

- Windows Server 2016 or later (for testing)
- PowerShell 5.1 or later
- Visual Studio 2022 or VS Code (for GUI development)
- .NET 8.0 SDK (for GUI builds)
- PSScriptAnalyzer module (`Install-Module PSScriptAnalyzer`)

### Development Setup

1. Clone the repository:
   ```powershell
   git clone https://github.com/anthonyscry/wsus-sql.git
   cd wsus-sql
   ```

2. Install development dependencies:
   ```powershell
   Install-Module PSScriptAnalyzer -Force -Scope CurrentUser
   ```

3. For GUI development, restore NuGet packages:
   ```powershell
   cd GUI
   dotnet restore
   ```

## Code Style Guidelines

### PowerShell

- **Naming:** Use approved verbs (`Get-`, `Set-`, `New-`, `Remove-`, `Test-`, `Invoke-`)
- **Prefix:** All WSUS functions use the `Wsus` prefix: `Test-WsusHealth`, `Start-WsusServer`
- **Output:** Use `Write-Success`/`Write-Failure`/`Write-Info`/`Write-WsusWarning` from WsusUtilities
- **Admin check:** Always verify admin privileges with `Test-AdminPrivileges`
- **Error handling:** Use try/catch with meaningful error messages
- **Logging:** Use `Start-WsusLogging`, `Write-Log`, `Stop-WsusLogging`

### Logging Pattern

```powershell
Start-WsusLogging -LogPath "C:\WSUS\Logs\script.log"
Write-Log "Operation started"
# ... operations ...
Write-Log "Operation completed"
Stop-WsusLogging
```

### Error Handling Pattern

```powershell
try {
    # Operation
    Write-Success "Operation completed"
} catch {
    Write-Failure "Operation failed: $($_.Exception.Message)"
    Write-Log "Error: $($_.Exception.Message)"
}
```

### C# / GUI

- Follow standard .NET naming conventions
- Use MVVM pattern for WPF components
- Keep PowerShell interop in dedicated service classes

## Running Code Analysis

Before submitting a PR, run PSScriptAnalyzer:

```powershell
# From repository root
Invoke-ScriptAnalyzer -Path . -Recurse -Settings PSScriptAnalyzerSettings.psd1
```

Fix all errors before submitting. Warnings should be addressed where practical.

## Testing

### PowerShell Scripts

Test scripts on a Windows Server environment with:
- WSUS role installed
- SQL Server Express 2022
- Administrator privileges

### GUI Application

Build and test with:
```powershell
cd GUI
dotnet build
dotnet run
```

## Submitting Changes

### Pull Request Process

1. Create a feature branch from `main`
2. Make your changes following the style guidelines
3. Run PSScriptAnalyzer and fix any issues
4. Test your changes locally
5. Submit a PR using the template
6. Address any review feedback

### Commit Messages

- Use clear, descriptive messages
- Start with a verb: "Add", "Fix", "Update", "Remove"
- Reference issues where applicable: "Fix #123"

Examples:
- `Add health check for SQL connection timeout`
- `Fix database backup failing on large SUSDB`
- `Update documentation for air-gapped setup`

## Project Structure

```
wsus-sql/
├── Invoke-WsusManagement.ps1    # Main entry point
├── Modules/                      # PowerShell modules
│   ├── WsusUtilities.psm1       # Logging, colors, SQL
│   ├── WsusDatabase.psm1        # Database operations
│   ├── WsusServices.psm1        # Service management
│   ├── WsusHealth.psm1          # Health checking
│   └── ...
├── Scripts/                      # Standalone scripts
├── GUI/                          # WPF application
│   ├── Models/
│   ├── ViewModels/
│   ├── Views/
│   └── Services/
└── DomainController/            # GPO deployment
```

## Questions?

- Check existing [issues](https://github.com/anthonyscry/wsus-sql/issues)
- Review [CLAUDE.md](CLAUDE.md) for detailed architecture info
- Open a new issue for questions not covered here

## License

By contributing, you agree that your contributions will be licensed under the same license as the project.
