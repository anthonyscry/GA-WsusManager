# Changelog

All notable changes to WSUS Manager are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.8.13] - 2026-03-12

### Changed
- Restored PowerShell-only distribution by removing C# source/workflow/documentation tracks

### Added
- Monthly maintenance policy now auto-declines ARM64 and 25H2 updates and excludes them from auto-approval

## [3.8.12] - 2026-02-14

### Fixed
- Corrected TrustServerCertificate compatibility for older SqlServer module versions
- Updated SQL execution wrapper usage in maintenance/management scripts to avoid unsupported parameter errors

## [3.8.11] - 2026-02-14

### Fixed
- TrustServerCertificate compatibility fix for SqlServer module v21.1+ differences

## [3.8.10] - 2026-02-12

### Changed
- Deep Cleanup now performs full 6-step WSUS database maintenance workflow
- Consolidated health check + repair into a single Diagnostics operation

### Fixed
- GitHub Actions artifact/release packaging alignment improvements

## [3.8.9] - 2026-02-10

### Added
- Monthly Maintenance renamed to Online Sync in GUI and workflow text
- Differential export path and export age options
- Definition Updates auto-approval support
- Reset Content action for air-gap recovery workflows

### Changed
- Increased max auto-approve threshold to 200
- Moved GUI/retry magic numbers into `WsusConfig.psm1`

## [3.8.8] - 2026-01-14

### Fixed
- Declined update purge parameter parsing issue
- Shrink retry behavior while backups are active
- Reduced expected noisy purge output errors

[3.8.13]: https://github.com/anthonyscry/GA-WsusManager/compare/v3.8.12...v3.8.13
[3.8.12]: https://github.com/anthonyscry/GA-WsusManager/compare/v3.8.11...v3.8.12
[3.8.11]: https://github.com/anthonyscry/GA-WsusManager/compare/v3.8.10...v3.8.11
[3.8.10]: https://github.com/anthonyscry/GA-WsusManager/compare/v3.8.9...v3.8.10
[3.8.9]: https://github.com/anthonyscry/GA-WsusManager/compare/v3.8.8...v3.8.9
[3.8.8]: https://github.com/anthonyscry/GA-WsusManager/releases/tag/v3.8.8
