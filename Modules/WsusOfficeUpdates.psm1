<#
===============================================================================
Module: WsusOfficeUpdates.psm1
Author: Tony Tran, ISSO, GA-ASI
Version: 1.0.0
Date: 2026-06-07
===============================================================================

.SYNOPSIS
    Microsoft 365 Apps / Office Click-to-Run update management via ODT

.DESCRIPTION
    Provides shared functions for downloading and managing Office Click-to-Run
    update content using the Office Deployment Tool (ODT). Supports:
    - Downloading M365 Apps / Office LTSC 2024 C2R updates to a network share
    - Generating ODT configuration XML for download and client update paths
    - Validating share accessibility and ODT availability
    - Reporting download status and statistics

.NOTES
    Requires the Office Deployment Tool (setup.exe) downloaded from Microsoft.
    https://www.microsoft.com/en-us/download/details.aspx?id=49117

    The download share must be readable by Domain Computers for GPO-based
    client updates. ODT version must match the target Office channel.
#>

# ===========================
# OFFICE C2R DEFAULTS
# ===========================

$script:OfficeUpdateDefaults = @{
    # Default ODT tool search paths
    OdtPaths = @(
        "C:\Program Files\Office\ODT\setup.exe",
        "C:\ODT\setup.exe",
        "C:\Program Files\Microsoft Office\ODT\setup.exe",
        "$env:ProgramFiles\Office\ODT\setup.exe"
    )

    # Supported update channels (Product ID determines Office edition)
    Channels = @{
        "MonthlyEnterprise" = "Monthly Enterprise Channel"
        "Current"           = "Current Channel"
        "SemiAnnual"        = "Semi-Annual Enterprise Channel"
        "SemiAnnualPreview" = "Semi-Annual Enterprise Channel (Preview)"
        "LTSC"              = "PerpetualVL2024"
        "LTSCPreview"       = "PerpetualVL2024"
    }

    # Default channel
    DefaultChannel = "MonthlyEnterprise"

    # Default product ID (O365ProPlusRetail = M365 Apps, ProPlus2024Volume = Office LTSC 2024)
    ProductIds = @{
        "M365Apps"         = "O365ProPlusRetail"
        "OfficeLTSC2024"   = "ProPlus2024Volume"
        "VisioLTSC2024"    = "VisioPro2024Volume"
        "ProjectLTSC2024"  = "ProjectPro2024Volume"
    }

    # Path where downloads land relative to the share root
    DownloadSubfolder = "Office"
}

# ===========================
# ODT PATH DETECTION
# ===========================

function Get-WsusOfficeOdtPath {
    <#
    .SYNOPSIS
        Locates the Office Deployment Tool (setup.exe) on this machine

    .DESCRIPTION
        Searches common installation paths and PATH for setup.exe. Returns the
        first valid path or $null if not found.

    .PARAMETER CustomPath
        Optional explicit path to setup.exe

    .OUTPUTS
        String with full path to setup.exe, or $null if not found
    #>
    param(
        [string]$CustomPath
    )

    if ($CustomPath -and (Test-Path $CustomPath)) {
        return (Resolve-Path $CustomPath).Path
    }

    # Check common ODT locations
    foreach ($path in $script:OfficeUpdateDefaults.OdtPaths) {
        if (Test-Path $path) {
            return (Resolve-Path $path).Path
        }
    }

    # Check PATH
    try {
        $pathCmd = Get-Command "setup.exe" -ErrorAction SilentlyContinue
        if ($pathCmd -and $pathCmd.Source) {
            return $pathCmd.Source
        }
    } catch {
        Write-Verbose "setup.exe not found in PATH: $($_.Exception.Message)"
    }

    return $null
}

# ===========================
# XML CONFIGURATION GENERATION
# ===========================

function New-WsusOfficeDownloadConfig {
    <#
    .SYNOPSIS
        Generates an ODT configuration XML for downloading Office C2R updates

    .DESCRIPTION
        Creates the download configuration XML that setup.exe /download uses
        to fetch Office Click-to-Run update files to a network share.

    .PARAMETER SourcePath
        Path to the network share where updates will be downloaded

    .PARAMETER Channel
        Update channel: MonthlyEnterprise, Current, SemiAnnual, SemiAnnualPreview, LTSC, LTSCPreview

    .PARAMETER ProductId
        Product to download: M365Apps, OfficeLTSC2024, VisioLTSC2024, ProjectLTSC2024

    .PARAMETER Language
        Language code (default: en-us)

    .PARAMETER OfficeClientEdition
        Architecture: 64 or 32 (default: 64)

    .OUTPUTS
        XML string for ODT configuration file
    #>
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath,

        [ValidateSet("MonthlyEnterprise", "Current", "SemiAnnual", "SemiAnnualPreview", "LTSC", "LTSCPreview")]
        [string]$Channel = "MonthlyEnterprise",

        [ValidateSet("M365Apps", "OfficeLTSC2024", "VisioLTSC2024", "ProjectLTSC2024")]
        [string]$ProductId = "OfficeLTSC2024",

        [string]$Language = "en-us",

        [ValidateSet("64", "32")]
        [string]$OfficeClientEdition = "64"
    )

    $channelName = $script:OfficeUpdateDefaults.Channels[$Channel]
    $productGuid = $script:OfficeUpdateDefaults.ProductIds[$ProductId]

    # Ensure SourcePath ends without backslash for clean XML
    $cleanPath = $SourcePath.TrimEnd('\')

    if ($Channel -eq "LTSC" -or $Channel -eq "LTSCPreview") {
        # LTSC uses PerpetualVL2024 channel with explicit version
        $xml = [System.Text.StringBuilder]::new()
        $null = $xml.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
        $null = $xml.AppendLine('<Configuration>')
        $null = $xml.AppendLine("  <Add OfficeClientEdition=""$OfficeClientEdition"" Channel=""$channelName""")
        $null = $xml.AppendLine('       SourcePath="' + $cleanPath + '"')
        $null = $xml.AppendLine('       AllowCdnFallback="True">')
        $null = $xml.AppendLine("    <Product ID=""$productGuid"">")
        $null = $xml.AppendLine("      <Language ID=""$Language"" />")
        $null = $xml.AppendLine('    </Product>')
        # Add the Office 2024-specific update channel info
        $null = $xml.AppendLine('    <Product ID="DWNtCurrentChannels">')
        $null = $xml.AppendLine('    </Product>')
        $null = $xml.AppendLine('  </Add>')
        $null = $xml.AppendLine('</Configuration>')
        return $xml.ToString()
    }

    # Standard M365 Apps channel
    $xml = [System.Text.StringBuilder]::new()
    $null = $xml.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
    $null = $xml.AppendLine('<Configuration>')
    $null = $xml.AppendLine("  <Add OfficeClientEdition=""$OfficeClientEdition"" Channel=""$channelName""")
    $null = $xml.AppendLine('       SourcePath="' + $cleanPath + '"')
    $null = $xml.AppendLine('       AllowCdnFallback="True">')
    $null = $xml.AppendLine("    <Product ID=""$productGuid"">")
    $null = $xml.AppendLine("      <Language ID=""$Language"" />")
    $null = $xml.AppendLine('    </Product>')
    $null = $xml.AppendLine('  </Add>')
    $null = $xml.AppendLine('</Configuration>')
    return $xml.ToString()
}

function New-WsusOfficeUpdateTrayConfig {
    <#
    .SYNOPSIS
        Generates a client-side update configuration XML for informational/reference use

    .DESCRIPTION
        Creates an update configuration XML that can be placed alongside the
        downloaded content as documentation. Not required for GPO-managed clients.

    .PARAMETER UpdatePath
        Path the client uses to check for updates (UNC or local)

    .PARAMETER Channel
        Update channel (must match what was downloaded)

    .PARAMETER OfficeClientEdition
        Architecture: 64 or 32 (default: 64)

    .OUTPUTS
        XML string for update config
    #>
    param(
        [Parameter(Mandatory)]
        [string]$UpdatePath,

        [ValidateSet("MonthlyEnterprise", "Current", "SemiAnnual", "SemiAnnualPreview", "LTSC", "LTSCPreview")]
        [string]$Channel = "MonthlyEnterprise",

        [ValidateSet("64", "32")]
        [string]$OfficeClientEdition = "64"
    )

    $channelName = $script:OfficeUpdateDefaults.Channels[$Channel]
    $cleanPath = $UpdatePath.TrimEnd('\')

    $xml = [System.Text.StringBuilder]::new()
    $null = $xml.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
    $null = $xml.AppendLine('<Configuration>')
    $null = $xml.AppendLine('  <Updates Enabled="True"')
    $null = $xml.AppendLine('           UpdatePath="' + $cleanPath + '"')
    $null = $xml.AppendLine('           UpdateChannel="' + $channelName + '"')
    $null = $xml.AppendLine('           OfficeClientEdition="' + $OfficeClientEdition + '" />')
    $null = $xml.AppendLine('</Configuration>')
    return $xml.ToString()
}

# ===========================
# DOWNLOAD OPERATION
# ===========================

function Invoke-WsusOfficeDownload {
    <#
    .SYNOPSIS
        Downloads Office C2R updates to a network share using ODT

    .DESCRIPTION
        Runs setup.exe /download with the generated XML configuration.
        Validates ODT location, creates directories, generates XML, and
        executes the download.

    .PARAMETER SourcePath
        Target path (network share) for downloaded update files

    .PARAMETER OdtPath
        Path to setup.exe. If not provided, searches common locations.

    .PARAMETER Channel
        Update channel (default: MonthlyEnterprise)

    .PARAMETER ProductId
        Product to download (default: OfficeLTSC2024)

    .PARAMETER Language
        Language code (default: en-us)

    .PARAMETER OfficeClientEdition
        Architecture (default: 64)

    .PARAMETER LogPath
        Optional path for download log file

    .OUTPUTS
        Hashtable with Success, Message, and details
    #>
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath,

        [string]$OdtPath,

        [ValidateSet("MonthlyEnterprise", "Current", "SemiAnnual", "SemiAnnualPreview", "LTSC", "LTSCPreview")]
        [string]$Channel = "MonthlyEnterprise",

        [ValidateSet("M365Apps", "OfficeLTSC2024", "VisioLTSC2024", "ProjectLTSC2024")]
        [string]$ProductId = "OfficeLTSC2024",

        [string]$Language = "en-us",

        [ValidateSet("64", "32")]
        [string]$OfficeClientEdition = "64",

        [string]$LogPath
    )

    $result = @{
        Success = $false
        OdtFound = $false
        SourceCreated = $false
        XmlFile = ""
        ExitCode = -1
        Message = ""
    }

    # Step 1: Find ODT
    $resolvedOdt = Get-WsusOfficeOdtPath -CustomPath $OdtPath
    if (-not $resolvedOdt) {
        $result.Message = "Office Deployment Tool (setup.exe) not found. Download from: https://www.microsoft.com/en-us/download/details.aspx?id=49117"
        return $result
    }
    $result.OdtFound = $true

    # Step 2: Create source directory if needed
    $targetDir = $SourcePath
    if ($Channel -ne "LTSC" -and $Channel -ne "LTSCPreview") {
        # Standard M365 channels use a subfolder named after the channel
        $targetDir = Join-Path $SourcePath $Channel
    }

    if (-not (Test-Path $targetDir)) {
        try {
            New-Item -Path $targetDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
            $result.SourceCreated = $true
        } catch {
            $result.Message = "Failed to create target directory: $($_.Exception.Message)"
            return $result
        }
    }

    # Step 3: Generate and write download config XML
    $configXml = New-WsusOfficeDownloadConfig -SourcePath $targetDir -Channel $Channel `
        -ProductId $ProductId -Language $Language -OfficeClientEdition $OfficeClientEdition

    $odtDir = Split-Path -Parent $resolvedOdt
    $xmlFile = Join-Path $odtDir "office-download-$Channel.xml"
    try {
        $configXml | Set-Content -Path $xmlFile -Encoding UTF8 -Force
        $result.XmlFile = $xmlFile
    } catch {
        $result.Message = "Failed to write XML config: $($_.Exception.Message)"
        return $result
    }

    # Step 4: Run ODT download
    Write-Host "Starting Office C2R download..." -ForegroundColor Yellow
    Write-Host "  Channel: $Channel" -ForegroundColor Gray
    Write-Host "  Product: $ProductId" -ForegroundColor Gray
    Write-Host "  Target:  $targetDir" -ForegroundColor Gray
    Write-Host "  ODT:     $resolvedOdt" -ForegroundColor Gray
    Write-Host "  XML:     $xmlFile" -ForegroundColor Gray
    Write-Host ""

    $downloadArgs = @(
        "/download",
        "`"$xmlFile`""
    )

    try {
        $proc = Start-Process -FilePath $resolvedOdt -ArgumentList $downloadArgs -Wait -PassThru -NoNewWindow
        $result.ExitCode = $proc.ExitCode

        if ($proc.ExitCode -eq 0) {
            $result.Success = $true
            $result.Message = "Office C2R download completed successfully"

            # Get download stats
            if (Test-Path $targetDir) {
                $officeDir = Join-Path $targetDir "Office"
                if (Test-Path $officeDir) {
                    $downloadedFiles = Get-ChildItem -Path $officeDir -Recurse -File -ErrorAction SilentlyContinue
                    $downloadedSize = [math]::Round(($downloadedFiles | Measure-Object -Property Length -Sum).Sum / 1GB, 2)
                    $result.DownloadedFiles = $downloadedFiles.Count
                    $result.DownloadedSizeGB = $downloadedSize
                }
            }
        } else {
            $result.Message = "ODT download failed with exit code $($proc.ExitCode). Check log for details."
        }
    } catch {
        $result.Message = "Failed to execute ODT download: $($_.Exception.Message)"
    }

    # Step 5: Log results if LogPath provided
    if ($LogPath -and (Test-Path (Split-Path -Parent $LogPath -ErrorAction SilentlyContinue))) {
        $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Channel=$Channel Product=$ProductId Target=$targetDir ExitCode=$($result.ExitCode) Success=$($result.Success) Size=$($result.DownloadedSizeGB)GB Files=$($result.DownloadedFiles)"
        Add-Content -Path $LogPath -Value $logEntry -ErrorAction SilentlyContinue
    }

    return $result
}

# ===========================
# STATUS & DIAGNOSTICS
# ===========================

function Test-WsusOfficeShareAccess {
    <#
    .SYNOPSIS
        Tests whether a share path is accessible for Office C2R updates

    .DESCRIPTION
        Validates that the target path exists, is reachable, and has
        appropriate read permissions. Useful for pre-flight checks.

    .PARAMETER Path
        UNC or local path to validate

    .OUTPUTS
        Hashtable with Accessible, Message, and path details
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $result = @{
        Accessible = $false
        Path = $Path
        PathType = "Unknown"
        FreeSpaceGB = 0
        Message = ""
    }

    # Determine if UNC or local
    if ($Path -match '^\\\\') {
        $result.PathType = "UNC"
    } else {
        $result.PathType = "Local"
    }

    # Test accessibility
    if (-not (Test-Path $Path)) {
        $result.Message = "Path does not exist or is not accessible: $Path"
        return $result
    }

    # Determine path type
    $item = Get-Item $Path -ErrorAction SilentlyContinue
    if (-not $item) {
        $result.Message = "Path exists but cannot be inspected"
        return $result
    }

    # Check free space on drive/share
    try {
        $drive = $item.PSDrive
        if ($drive -and $drive.Free) {
            $result.FreeSpaceGB = [math]::Round($drive.Free / 1GB, 2)
        }
    } catch {
        # Cannot determine free space for UNC paths without explicit credentials
        $result.FreeSpaceGB = -1
    }

    # Look for existing Office C2R data
    $officeDir = Join-Path $Path "Office"
    if (Test-Path $officeDir) {
        $existingFiles = Get-ChildItem -Path $officeDir -Recurse -File -ErrorAction SilentlyContinue
        $existingSize = [math]::Round(($existingFiles | Measure-Object -Property Length -Sum).Sum / 1GB, 2)
        $result.ExistingFiles = $existingFiles.Count
        $result.ExistingSizeGB = $existingSize
    } else {
        $result.ExistingFiles = 0
        $result.ExistingSizeGB = 0
    }

    $result.Accessible = $true
    $result.Message = "Path is accessible. Free: $($result.FreeSpaceGB)GB, Existing Office files: $($result.ExistingFiles) ($($result.ExistingSizeGB)GB)"

    return $result
}

function Get-WsusOfficeDownloadStatus {
    <#
    .SYNOPSIS
        Reports the status of downloaded Office C2R updates in a share

    .DESCRIPTION
        Scans the share for Office C2R update data, reporting what channels
        exist, their sizes, and last modified dates.

    .PARAMETER Path
        Path to the Office C2R update share root

    .OUTPUTS
        Array of channel status hashtables
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $results = @()

    if (-not (Test-Path $Path)) {
        return $results
    }

    # Check for per-channel subfolders
    $channels = Get-ChildItem -Path $Path -Directory -ErrorAction SilentlyContinue

    foreach ($channel in $channels) {
        $officeDir = Join-Path $channel.FullName "Office"
        if (-not (Test-Path $officeDir)) {
            # Check if channel folder directly contains Office data
            $officeDir = Join-Path $channel.FullName "Data"
        }

        $channelStatus = @{
            ChannelName = $channel.Name
            Path = $channel.FullName
            LastModified = $channel.LastWriteTime
            HasData = $false
            FileCount = 0
            SizeGB = 0
            Version = "Unknown"
            Message = ""
        }

        if (Test-Path $officeDir) {
            $files = Get-ChildItem -Path $officeDir -Recurse -File -ErrorAction SilentlyContinue
            $channelStatus.HasData = $true
            $channelStatus.FileCount = $files.Count
            $channelStatus.SizeGB = [math]::Round(($files | Measure-Object -Property Length -Sum).Sum / 1GB, 2)
            $channelStatus.LastModified = ($files | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime

            # Try to detect version from .cab metadata or folder names
            $cabFiles = Get-ChildItem -Path $officeDir -Filter "*.cab" -Recurse -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 5
            if ($cabFiles) {
                $channelStatus.Version = "Data present ($($cabFiles.Count) cabinet files)"
            }

            $channelStatus.Message = "$($channelStatus.FileCount) files, $($channelStatus.SizeGB)GB"
        } else {
            # Check if this channel folder has any Office-like subdirectories
            $subDirs = Get-ChildItem -Path $channel.FullName -Directory -ErrorAction SilentlyContinue
            if ($subDirs.Count -gt 0) {
                $channelStatus.Message = "$($subDirs.Count) subdirectories but no Office\Data folder"
            } else {
                $channelStatus.Message = "Empty folder"
            }
        }

        $results += $channelStatus
    }

    # If no channel subfolders, check root for Office data
    $rootOffice = Join-Path $Path "Office"
    if (Test-Path $rootOffice) {
        $files = Get-ChildItem -Path $rootOffice -Recurse -File -ErrorAction SilentlyContinue
        if ($files.Count -gt 0) {
            $results += @{
                ChannelName = "(root)"
                Path = $Path
                LastModified = ($files | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
                HasData = $true
                FileCount = $files.Count
                SizeGB = [math]::Round(($files | Measure-Object -Property Length -Sum).Sum / 1GB, 2)
                Version = "Direct Office data"
                Message = "Office data at share root"
            }
        }
    }

    return $results
}

# ===========================
# EXPORTS
# ===========================

Export-ModuleMember -Function @(
    'Get-WsusOfficeOdtPath',
    'New-WsusOfficeDownloadConfig',
    'New-WsusOfficeUpdateTrayConfig',
    'Invoke-WsusOfficeDownload',
    'Test-WsusOfficeShareAccess',
    'Get-WsusOfficeDownloadStatus'
)
