<#
.SYNOPSIS
    Force Windows Update Client to Check In with WSUS Server
.DESCRIPTION
    Restarts Windows Update services, clears cache if needed, and forces immediate check-in with WSUS
.PARAMETER ClearCache
    If specified, clears the Windows Update cache (SoftwareDistribution folder)
#>

param(
    [switch]$ClearCache
)

# Colors for output
function Write-ColorOutput($ForegroundColor) {
    $fc = $host.UI.RawUI.ForegroundColor
    $host.UI.RawUI.ForegroundColor = $ForegroundColor
    if ($args) {
        Write-Output $args
    }
    $host.UI.RawUI.ForegroundColor = $fc
}

function Write-Success { Write-ColorOutput Green $args }
function Write-Failure { Write-ColorOutput Red $args }
function Write-Warning { Write-ColorOutput Yellow $args }
function Write-Info { Write-ColorOutput Cyan $args }

Write-Info "=========================================="
Write-Info "Force WSUS Check-In Script"
Write-Info "=========================================="
Write-Info "Clear Cache: $($ClearCache.IsPresent)"
Write-Info ""

# Check if running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Failure "ERROR: This script must be run as Administrator!"
    exit 1
}

# ===========================
# 1. STOP WINDOWS UPDATE SERVICES
# ===========================
Write-Info "[1/6] Stopping Windows Update services..."
$services = @("wuauserv", "bits", "cryptsvc", "msiserver")

foreach ($service in $services) {
    try {
        $svc = Get-Service $service -ErrorAction Stop
        if ($svc.Status -eq "Running") {
            Write-Info "  Stopping $service..."
            Stop-Service $service -Force -ErrorAction Stop
            Write-Success "  ✓ $service stopped"
        } else {
            Write-Info "  $service already stopped"
        }
    } catch {
        Write-Warning "  ⚠ Could not stop $service : $_"
    }
}

# ===========================
# 2. CLEAR CACHE (OPTIONAL)
# ===========================
if ($ClearCache) {
    Write-Info "[2/6] Clearing Windows Update cache..."
    try {
        $sdPath = "C:\Windows\SoftwareDistribution"
        $backupPath = "C:\Windows\SoftwareDistribution.bak"
        
        if (Test-Path $backupPath) {
            Write-Warning "  Removing old backup..."
            Remove-Item $backupPath -Recurse -Force -ErrorAction Stop
        }
        
        if (Test-Path $sdPath) {
            Write-Info "  Backing up SoftwareDistribution folder..."
            Rename-Item $sdPath $backupPath -Force -ErrorAction Stop
            Write-Success "  ✓ Cache cleared (backup created)"
        } else {
            Write-Info "  No cache to clear"
        }
    } catch {
        Write-Failure "  ✗ Error clearing cache: $_"
    }
} else {
    Write-Info "[2/6] Skipping cache clear (use -ClearCache to enable)"
}

# ===========================
# 3. DELETE WSUS CLIENT ID (FORCE RE-REGISTRATION)
# ===========================
Write-Info "[3/6] Resetting WSUS client ID..."
try {
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update"
    )
    
    foreach ($regPath in $regPaths) {
        if (Test-Path $regPath) {
            $props = Get-ItemProperty $regPath -ErrorAction SilentlyContinue
            
            # Remove SusClientId and AccountDomainSid to force re-registration
            if ($props.PSObject.Properties.Name -contains "SusClientId") {
                Remove-ItemProperty -Path $regPath -Name "SusClientId" -ErrorAction SilentlyContinue
                Write-Success "  ✓ Removed SusClientId"
            }
            if ($props.PSObject.Properties.Name -contains "SusClientIDValidation") {
                Remove-ItemProperty -Path $regPath -Name "SusClientIDValidation" -ErrorAction SilentlyContinue
                Write-Success "  ✓ Removed SusClientIDValidation"
            }
        }
    }
} catch {
    Write-Warning "  ⚠ Error resetting client ID: $_"
}

# ===========================
# 4. START WINDOWS UPDATE SERVICES
# ===========================
Write-Info "[4/6] Starting Windows Update services..."
foreach ($service in $services) {
    try {
        $svc = Get-Service $service -ErrorAction Stop
        if ($svc.Status -ne "Running") {
            Write-Info "  Starting $service..."
            Start-Service $service -ErrorAction Stop
            Write-Success "  ✓ $service started"
        } else {
            Write-Info "  $service already running"
        }
    } catch {
        Write-Warning "  ⚠ Could not start $service : $_"
    }
}

# Give services time to start
Start-Sleep -Seconds 3

# ===========================
# 5. FORCE DETECTION AND REPORTING
# ===========================
Write-Info "[5/6] Forcing WSUS detection and reporting..."
try {
    # Method 1: wuauclt (older method, still works)
    Write-Info "  Running wuauclt /detectnow /reportnow..."
    Start-Process "wuauclt.exe" -ArgumentList "/detectnow /reportnow" -WindowStyle Hidden -ErrorAction SilentlyContinue
    
    # Method 2: USOClient (Windows 10/11)
    if (Test-Path "C:\Windows\System32\usoclient.exe") {
        Write-Info "  Running USOClient StartScan..."
        Start-Process "usoclient.exe" -ArgumentList "StartScan" -WindowStyle Hidden -ErrorAction SilentlyContinue
    }
    
    # Method 3: PowerShell COM object
    Write-Info "  Using Windows Update COM object..."
    $updateSession = New-Object -ComObject Microsoft.Update.Session
    $updateSearcher = $updateSession.CreateUpdateSearcher()
    
    Write-Info "  Searching for updates..."
    $searchResult = $updateSearcher.Search("IsInstalled=0")
    
    $updateCount = $searchResult.Updates.Count
    Write-Success "  ✓ Found $updateCount updates available"
    
} catch {
    Write-Warning "  ⚠ Error forcing detection: $_"
}

# ===========================
# 6. CHECK WSUS CONFIGURATION
# ===========================
Write-Info "[6/6] Checking WSUS configuration..."
try {
    $wuServer = Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name WUServer -ErrorAction SilentlyContinue
    $wuStatusServer = Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name WUStatusServer -ErrorAction SilentlyContinue
    $useWUServer = Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name UseWUServer -ErrorAction SilentlyContinue
    
    if ($wuServer) {
        Write-Success "  ✓ WSUS Server: $($wuServer.WUServer)"
    } else {
        Write-Warning "  ⚠ No WSUS server configured (will use Windows Update)"
    }
    
    if ($wuStatusServer) {
        Write-Success "  ✓ WSUS Status Server: $($wuStatusServer.WUStatusServer)"
    }
    
    if ($useWUServer -and $useWUServer.UseWUServer -eq 1) {
        Write-Success "  ✓ Using WSUS server (UseWUServer = 1)"
    } else {
        Write-Warning "  ⚠ UseWUServer not enabled or not set to 1"
    }
    
} catch {
    Write-Warning "  ⚠ Error checking WSUS config: $_"
}

# ===========================
# SUMMARY AND NEXT STEPS
# ===========================
Write-Info ""
Write-Info "=========================================="
Write-Info "SUMMARY"
Write-Info "=========================================="
Write-Success "✓ Services restarted"
Write-Success "✓ Detection and reporting initiated"
Write-Info ""
Write-Info "Next steps:"
Write-Info "1. Wait 5-10 minutes for the client to check in with WSUS"
Write-Info "2. On WSUS server, check: Computers → All Computers → find this computer"
Write-Info "3. Check 'Last Status Report' time to confirm check-in"
Write-Info "4. Or open Windows Update on this client to see available updates"
Write-Info ""
Write-Info "To check update status on this client:"
Write-Info "  Get-WindowsUpdate (if PSWindowsUpdate module installed)"
Write-Info "  Or: Settings → Windows Update → Check for updates"
Write-Info ""

# Display current Windows Update status
Write-Info "Current Windows Update Service Status:"
Get-Service wuauserv, bits | Select-Object Name, Status, StartType | Format-Table -AutoSize