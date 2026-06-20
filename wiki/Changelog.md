# Changelog

This wiki page summarizes operator-facing release changes. For the full repository changelog, see [`CHANGELOG.md`](../CHANGELOG.md).

## 4.1.0 - 2026-06-20

### Added
- Fix SQL Login flow for granting the current operator SQL sysadmin access.
- Deeper diagnostics and auto-fixes for SQL, IIS, services, firewall, ACLs, and stuck downloads.
- Split server/workstation WSUS GPOs plus inbound/outbound firewall GPOs.
- OU creation for `Member Servers`, `WSUS Server`, and `Workstations` during GPO import.
- Live Terminal output for Robocopy and long-running operations.
- Product picker defaults for .NET Framework, Visual Studio 2022, Exchange 2019, and Defender.

### Changed
- Release package is now `GA-WsusManager-v4.1.0.zip`.
- GitHub release assets are zip-only; the EXE is inside the zip.
- Icon/logo assets now live in `icons/`.
- Navigation is organized as Setup, Maintenance, collapsed Online Operations, and collapsed Diagnostics.
- Health Score uses only services, SUSDB size, and disk free space.
- Air-gap documentation now uses approved USB/removable media, Restore DB, Robocopy, Reset Content, and Diagnostics.
- GPO deployment uses the packaged `DomainController/` script; there is no GUI Create GPO menu item.

### Fixed
- GPO import when target OUs are missing.
- WSUS server computer move into `Member Servers\WSUS Server`.
- SQL preflight failures when SQL tooling is limited.
- WSUS content ACL repair for IIS and client download principals.
- Tray minimize recovery, Robocopy live output, and popup readability.
- Product sync/approval filtering and health scores capped below 100.

### Removed
- Standalone EXE upload from release assets.
- Stale Pathfinder planning artifacts from the repository root.
- Scheduled task, last sync, and last operation history from Health Score calculation.

## 4.0.5 - 2026-05-11

- Added Exchange Server 2019 to default sync products.
- Changed product subscription behavior to additive instead of replacement.
- Stopped declining non-selected product updates that can include related Office/SSMS updates.
- Fixed missing Office LTSC 2024 and SQL Server Management Studio v20 updates after sync.

## Older releases

See [`CHANGELOG.md`](../CHANGELOG.md) for full historical details.
