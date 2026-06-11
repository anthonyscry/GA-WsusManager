# Office C2R Updates

WSUS Manager includes a Microsoft 365 Apps / Office LTSC 2024 Click-to-Run (C2R) update downloader. It uses the [Office Deployment Tool](https://www.microsoft.com/en-us/download/details.aspx?id=49117) (ODT) to pull C2R update content from Microsoft into a local or network share, where clients can pull updates via Group Policy instead of from the Microsoft CDN.

## Why this exists

Office 2024 LTSC and Microsoft 365 Apps use **Click-to-Run** delivery, not Windows Update. WSUS only mirrors traditional Windows updates, so Office C2R update approval through WSUS shows updates as **stubs** that never receive content. The workaround Microsoft supports is to host C2R content on a local share and point clients at it through the [Office ADMX templates](https://www.microsoft.com/en-us/download/details.aspx?id=49030) (UpdatePath / Update Channel GPO settings).

WSUS Manager automates the download half of that workflow.

## Module Reference

Module: `Modules/WsusOfficeUpdates.psm1`

| Function | Purpose |
|----------|---------|
| `Get-WsusOfficeOdtPath` | Locates `setup.exe` (ODT) in standard install paths or via `-CustomPath` |
| `New-WsusOfficeDownloadConfig` | Generates ODT download XML for any product/channel/language |
| `New-WsusOfficeUpdateTrayConfig` | Generates client-side update configuration XML (reference / documentation) |
| `Invoke-WsusOfficeDownload` | Runs `setup.exe /download` with auto-generated XML, validates preconditions |
| `Test-WsusOfficeShareAccess` | Pre-flight check: share accessibility, free space, existing content |
| `Get-WsusOfficeDownloadStatus` | Scans share for per-channel content and reports sizes / last-modified |

## Supported Products

| Product | Product ID | Notes |
|---------|-----------|-------|
| Office LTSC 2024 (Volume) | `ProPlus2024Volume` | Default — most common ask for air-gapped environments |
| Microsoft 365 Apps | `O365ProPlusRetail` | Includes Word, Excel, PowerPoint, Outlook, etc. |
| Visio LTSC 2024 | `VisioPro2024Volume` | |
| Project LTSC 2024 | `ProjectPro2024Volume` | |

## Supported Channels

| Channel Key | Channel Name | Use |
|-------------|--------------|-----|
| `LTSC` | `PerpetualVL2024` | Office LTSC 2024 — slowest, most stable |
| `MonthlyEnterprise` | `Monthly Enterprise Channel` | M365 — monthly updates, most stable for managed envs |
| `Current` | `Current Channel` | M365 — latest features, frequent updates |
| `SemiAnnual` | `Semi-Annual Enterprise Channel` | M365 — twice per year |

The `LTSC` channel goes into the share root directly. The M365 channels are placed in a subfolder named after the channel (e.g. `\\server\share\MonthlyEnterprise\`).

## Interactive Use

```powershell
.\Scripts\Invoke-WsusManagement.ps1
```

Pick option **10** (Office C2R Updates → Download Office LTSC / M365 Apps Updates to Share). You'll be prompted for:

1. **Network share path** (required, no default — each environment is different)
2. **Product** (1-4 selection)
3. **Channel** (for M365 Apps)
4. **ODT location** (auto-detected if `setup.exe` is in `C:\ODT\`, `C:\Program Files\Office\ODT\`, or `C:\Program Files\Microsoft Office\ODT\`)
5. **Confirmation** before the download starts

The download runs `setup.exe /download` and reports:

- Exit code
- Total files downloaded
- Total GB downloaded
- Per-channel summary of existing content in the share

## Non-Interactive / Scheduled Use

```powershell
.\Scripts\Invoke-WsusManagement.ps1 -OfficeUpdates `
    -OfficeChannel LTSC `
    -OfficeProductId OfficeLTSC2024 `
    -OfficeSharePath "\\FILESERVER\Software\OfficeC2R" `
    -OfficeLanguage "en-us" `
    -OfficeClientEdition "64"
```

This form is suitable for scheduled tasks. The recommended pattern is:

- Run on a machine that can reach the internet (the staging/admin workstation, NOT the WSUS server)
- Run on a schedule (weekly or monthly) to refresh content
- Point the GPO UpdatePath to the resulting share

## Share Permissions

The share where downloads land must be readable by `Domain Computers` for GPO-managed clients to fetch updates (they read it as the computer account, not the user). Recommended:

| Principal | Share Permission | NTFS Permission |
|-----------|------------------|-----------------|
| `Domain Computers` | Read | Read & Execute, List, Read |
| `Admins` (your admin group) | Modify | Full Control |
| `SYSTEM` | Full Control | Full Control |

## GPO Client Configuration

After the share is populated, configure clients via GPO using the **Office ADMX/ADML templates** ([download](https://www.microsoft.com/en-us/download/details.aspx?id=49030)):

```
Computer Configuration
  └ Administrative Templates
    └ Microsoft Office 2016 (Machine)
      └ Updates
```

Recommended values:

| Setting | Value |
|---------|-------|
| Enable Automatic Updates | Enabled |
| Update Path | `\\YOURSERVER\OfficeC2R\MonthlyEnterprise` (or LTSC root) |
| Update Channel | Must match the downloaded channel exactly |
| Hide option to enable or disable updates | Enabled |
| Update Deadline | Enabled, 3-7 days |

The **Office Automatic Updates 2.0** scheduled task (`Microsoft\Office\Office Automatic Updates 2.0`) must exist and be enabled. If it doesn't, reinstall Click-to-Run Office and select "Use Office Updates from a location other than the internet" during setup, or run the ODT with an `Updates` block on the client.

## Client-Side Update Command

To force a client to check for updates right now:

```cmd
"C:\Program Files\Common Files\Microsoft Shared\ClickToRun\OfficeC2RClient.exe" /update user
```

Silently:

```cmd
"C:\Program Files\Common Files\Microsoft Shared\ClickToRun\OfficeC2RClient.exe" /update user displaylevel=false forceappshutdown=true
```

## Gotchas

- **Channel mismatch is the #1 cause of "updates don't apply" complaints.** If clients are on Current Channel but the share only has Monthly Enterprise Channel, they will silently fail to update. The downloaded channel and the client channel must match.
- **The share must be reachable by the computer account**, not just logged-in users. Verify by running `Get-SmbOpenFile -ClientComputerName (hostname)` from the share host as the Domain Computers principal would.
- **Click-to-Run only** — does not work for MSI-based Office installs (e.g. Office 2016 MSI).
- **Disk space**: A full M365 Apps Monthly Enterprise download is ~5-8 GB per language per architecture. Plan for ~20 GB for English 64-bit Monthly + 2-3 prior versions.
- **Air-gapped transfer**: If your WSUS environment is air-gapped, the staging machine with internet downloads into a local folder. Copy that folder onto the air-gapped share via sneaker-net / approved transfer. ODT is happy to read from any local path; just point `-OfficeSharePath` at the local path during the import or copy operation.
- **Multiple languages / architectures**: download each combination separately. The CLI `OfficeLanguage` and `OfficeClientEdition` parameters exist for this reason.
- **Visio / Project**: must be downloaded alongside Office (or have their own products) — there's no combined C2R product for all three.

## Verification

After a successful download, `Get-WsusOfficeDownloadStatus` reports per-channel content size and last-modified timestamps. The status function is exposed as a module command and can be called independently:

```powershell
Import-Module .\Modules\WsusOfficeUpdates.psm1 -Force -DisableNameChecking
Get-WsusOfficeDownloadStatus -Path "\\FILESERVER\Software\OfficeC2R" | Format-Table
```

Sample output:

```
ChannelName      HasData FileCount SizeGB LastModified
-----------      ------- --------- ------ ------------
MonthlyEnterprise   True       847   6.42 6/7/2026 3:14:22 PM
```

## Tests

`Tests/WsusOfficeUpdates.Tests.ps1` covers:

- Module loading + 6 exported functions
- ODT path detection (valid / non-existent / empty)
- XML generation for all 4 products × multiple channels
- Language and architecture parameters
- SourcePath and UpdatePath attribute handling
- Channel-to-channel mapping (LTSC ↔ PerpetualVL2024, etc.)
- Share access (non-existent / empty / valid local path)
- Download status (non-existent / empty / channel folders / root Office data)
- Download error paths (ODT not found, target inaccessible)

Run with:

```powershell
Invoke-Pester -Path .\Tests\WsusOfficeUpdates.Tests.ps1 -Output Detailed
```
