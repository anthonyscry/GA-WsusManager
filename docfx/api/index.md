# WSUS Manager API Reference

Welcome to the WSUS Manager API documentation. This site provides comprehensive reference documentation for all public APIs in WsusManager.Core and WsusManager.App.

## Getting Started

- **[WsusManager.Core](xref:WsusManager.Core)** - Core library with business logic, services, and models
- **[WsusManager.App](xref:WsusManager.App)** - WPF application with ViewModels and Views

## Key Namespaces

### WsusManager.Core.Services

Service interfaces and implementations for WSUS operations:

- **[IHealthService](xref:WsusManager.Core.Services.IHealthService)** - Health check and diagnostics
- **[ISqlService](xref:WsusManager.Core.Services.ISqlService)** - SQL Server operations (cleanup, restore)
- **[ISyncService](xref:WsusManager.Core.Services.ISyncService)** - WSUS synchronization operations
- **[IWindowsServiceManager](xref:WsusManager.Core.Services.IWindowsServiceManager)** - Windows service management
- **[IFirewallService](xref:WsusManager.Core.Services.IFirewallService)** - Firewall rule management
- **[IClientService](xref:WsusManager.Core.Services.IClientService)** - WinRM client operations
- **[IDatabaseBackupService](xref:WsusManager.Core.Services.IDatabaseBackupService)** - Database backup and restore
- **[IDeepCleanupService](xref:WsusManager.Core.Services.IDeepCleanupService)** - Deep database cleanup and optimization
- **[IExportService](xref:WsusManager.Core.Services.IExportService)** - Export operations for air-gap transfers
- **[IImportService](xref:WsusManager.Core.Services.IImportService)** - Import operations for air-gap transfers

### WsusManager.Core.Models

Data models for WSUS entities:

- **[OperationResult](xref:WsusManager.Core.Models.OperationResult)** - Standard operation result
- **[ProcessResult](xref:WsusManager.Core.Models.ProcessResult)** - Process execution result
- **[DashboardData](xref:WsusManager.Core.Models.DashboardData)** - Dashboard information
- **[AppSettings](xref:WsusManager.Core.Models.AppSettings)** - Application settings
- **[DiagnosticCheckResult](xref:WsusManager.Core.Models.DiagnosticCheckResult)** - Individual diagnostic check result
- **[DiagnosticReport](xref:WsusManager.Core.Models.DiagnosticReport)** - Complete diagnostic report
- **[ExportOptions](xref:WsusManager.Core.Models.ExportOptions)** - Export operation options
- **[ImportOptions](xref:WsusManager.Core.Models.ImportOptions)** - Import operation options
- **[SyncProfile](xref:WsusManager.Core.Models.SyncProfile)** - Sync configuration profiles
- **[SyncResult](xref:WsusManager.Core.Models.SyncResult)** - Synchronization result

### WsusManager.App.ViewModels

MVVM view models for UI logic:

- **[MainViewModel](xref:WsusManager.App.ViewModels.MainViewModel)** - Main application view model
- **[SettingsViewModel](xref:WsusManager.App.ViewModels.SettingsViewModel)** - Settings dialog view model
- **[DiagnosticsViewModel](xref:WsusManager.App.ViewModels.DiagnosticsViewModel)** - Diagnostics panel view model

## Architecture

WSUS Manager follows the MVVM pattern with CommunityToolkit.Mvvm:

1. **Models** (WsusManager.Core) - Business entities
2. **Services** (WsusManager.Core) - Business logic and external operations
3. **ViewModels** (WsusManager.App) - UI state and commands
4. **Views** (WsusManager.App) - XAML UI definition

## Version

Current API documentation is for **WSUS Manager v4.4.0**.

## License

This project is proprietary software developed for GA-ASI internal use.
