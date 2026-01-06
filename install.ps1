<#
===============================================================================
Script: install.ps1
Purpose: Fully automated SQL Express 2022 + SSMS + WSUS installation (SQL mode).
Overview:
  - Extracts SQL Express and installs SQL Engine + SSMS silently.
  - Enables SQL networking, firewall rules, and WSUS role/services.
  - Configures WSUS content path, IIS virtual directory, and permissions.
Notes:
  - Logs to C:\SQLDB\install.log
  - Requires installer files in C:\SQLDB
  - Content folder must be C:\WSUS for correct DB file registration.
===============================================================================
#>

# -------------------------
# CONFIGURATION
# -------------------------
$LogFile         = "C:\SQLDB\install.log"
$Extractor       = "C:\SQLDB\SQLEXPRADV_x64_ENU.exe"
$ExtractPath     = "C:\SQLDB\SQL2022EXP"
$SSMSInstaller   = "C:\SQLDB\SSMS-Setup-ENU.exe"
$WSUSRoot        = "C:\WSUS"
$WSUSContent     = "C:\WSUS"
$ConfigFile      = "C:\SQLDB\ConfigurationFile.ini"
$PasswordFile    = "C:\SQLDB\sa.encrypted"

# -------------------------
# LOGGING SETUP
# -------------------------
New-Item -Path "C:\SQLDB" -ItemType Directory -Force | Out-Null
Start-Transcript -Path $LogFile -Append -ErrorAction Ignore | Out-Null
$ProgressPreference = "SilentlyContinue"
$ConfirmPreference  = "None"
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# =====================================================================
# SECURE SA PASSWORD (ONLY USER INPUT)
# =====================================================================
function Get-SAPassword {
    while ($true) {
        $pass1 = Read-Host "Enter SA password (15+ chars, 1 number, 1 special)" -AsSecureString
        $pass2 = Read-Host "Re-enter SA password" -AsSecureString

        $p1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass1))
        $p2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass2))

        if ($p1 -ne $p2) { Write-Host "Passwords do not match."; continue }
        if ($p1.Length -lt 15) { Write-Host "Must be >=15 chars."; continue }
        if ($p1 -notmatch "\d") { Write-Host "Must contain number."; continue }
        if ($p1 -notmatch "[^a-zA-Z0-9]") { Write-Host "Must contain special char."; continue }

        return $p1
    }
}

# Get or retrieve password
if (!(Test-Path $PasswordFile)) {
    $SA_Password = Get-SAPassword
    # Encrypt and store password
    $SA_Password | ConvertTo-SecureString -AsPlainText -Force | 
        ConvertFrom-SecureString | Set-Content $PasswordFile
} else {
    # Retrieve stored password
    $securePass = Get-Content $PasswordFile | ConvertTo-SecureString
    $SA_Password = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePass))
}

# =====================================================================
# 1. EXTRACT SQL EXPRESS ADV PACKAGE
# =====================================================================
Write-Host "[+] Extracting SQL package..."
if (!(Test-Path $Extractor)) { throw "SQL extractor missing at $Extractor" }

if (!(Test-Path "$ExtractPath\setup.exe")) {
    Start-Process $Extractor -ArgumentList "/Q", "/x:$ExtractPath" -Wait -NoNewWindow
    Write-Host "    Extraction complete."
} else {
    Write-Host "    Already extracted."
}

# =====================================================================
# 2. CREATE SQL CONFIGURATION FILE
# =====================================================================
Write-Host "[+] Creating SQL configuration file..."

$configContent = @"
[OPTIONS]
ACTION="Install"
QUIET="True"
IACCEPTSQLSERVERLICENSETERMS="True"
ENU="True"
FEATURES=SQLENGINE,CONN,BC,SDK
INSTANCENAME="SQLEXPRESS"
INSTANCEID="SQLEXPRESS"
SQLSVCACCOUNT="NT AUTHORITY\SYSTEM"
SQLSVCSTARTUPTYPE="Automatic"
AGTSVCACCOUNT="NT AUTHORITY\NETWORK SERVICE"
AGTSVCSTARTUPTYPE="Disabled"
SQLSYSADMINACCOUNTS="BUILTIN\Administrators"
SECURITYMODE="SQL"
SAPWD="$SA_Password"
TCPENABLED="1"
NPENABLED="1"
BROWSERSVCSTARTUPTYPE="Automatic"
INSTALLSHAREDDIR="C:\Program Files\Microsoft SQL Server"
INSTALLSHAREDWOWDIR="C:\Program Files (x86)\Microsoft SQL Server"
INSTANCEDIR="C:\Program Files\Microsoft SQL Server"
"@

Set-Content -Path $ConfigFile -Value $configContent -Force

# =====================================================================
# 3. INSTALL SQL ENGINE VIA SETUP.EXE (FULLY SILENT)
# =====================================================================
Write-Host "[+] Installing SQL Server Express 2022..."

$setupExe = "$ExtractPath\setup.exe"
if (!(Test-Path $setupExe)) {
    throw "Cannot find setup.exe at $setupExe"
}

$setupProcess = Start-Process $setupExe -ArgumentList "/CONFIGURATIONFILE=`"$ConfigFile`"" -Wait -PassThru -NoNewWindow

if ($setupProcess.ExitCode -ne 0 -and $setupProcess.ExitCode -ne 3010) {
    throw "SQL installation failed with exit code $($setupProcess.ExitCode). Check log at C:\Program Files\Microsoft SQL Server\160\Setup Bootstrap\Log\Summary.txt"
}

Write-Host "    SQL installation complete."

# =====================================================================
# 4. INSTALL SSMS (PASSIVE MODE, NO GUI INTERACTION)
# =====================================================================
Write-Host "[+] Installing SSMS..."
if (Test-Path $SSMSInstaller) {
    Start-Process $SSMSInstaller -ArgumentList "/install", "/passive", "/norestart" -Wait -NoNewWindow
    Write-Host "    SSMS installation complete."
} else {
    Write-Host "    SSMS installer not found, skipping."
}

# =====================================================================
# 5. ENABLE IFI (INSTANT FILE INITIALIZATION)
# =====================================================================
Write-Host "[+] Enabling Instant File Initialization..."

$account = "NT SERVICE\MSSQL`$SQLEXPRESS"
$tempCfg = "$env:TEMP\secpol-ifiset.cfg"

secedit /export /cfg $tempCfg /quiet | Out-Null
$content = Get-Content $tempCfg
$priv = "SeManageVolumePrivilege"

if ($content -match "^$priv") {
    $content = $content -replace "^$priv.*", "$priv = *$account"
    Set-Content -Path $tempCfg -Value $content
} else {
    Add-Content -Path $tempCfg -Value "$priv = *$account"
}

secedit /configure /db "$env:windir\security\local.sdb" /cfg $tempCfg /areas USER_RIGHTS /quiet | Out-Null
Remove-Item $tempCfg -Force -ErrorAction SilentlyContinue

Write-Host "    IFI enabled."

# =====================================================================
# 6. ENABLE TCP/IP + NAMED PIPES (REGISTRY MODE)
# =====================================================================
Write-Host "[+] Configuring SQL networking..."

$root = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL16.SQLEXPRESS\MSSQLServer\SuperSocketNetLib"

# Ensure TCP path exists
if (!(Test-Path "$root\Tcp\IPAll")) {
    New-Item -Path "$root\Tcp\IPAll" -Force | Out-Null
}

# Configure TCP/IP - ensure enabled
Set-ItemProperty "$root\Tcp" -Name Enabled -Value 1 -ErrorAction SilentlyContinue

# Configure Named Pipes - ensure enabled
Set-ItemProperty "$root\Np"  -Name Enabled -Value 1 -ErrorAction SilentlyContinue

# Set static port 1433 (clear dynamic ports first)
New-ItemProperty "$root\Tcp\IPAll" -Name TcpDynamicPorts -Value "" -PropertyType String -Force | Out-Null
New-ItemProperty "$root\Tcp\IPAll" -Name TcpPort -Value "1433" -PropertyType String -Force | Out-Null

# Restart SQL services to apply networking changes
Write-Host "    Restarting SQL services..."
Restart-Service 'MSSQL$SQLEXPRESS' -Force
Start-Sleep -Seconds 5

# Start SQL Browser if not running (required for named instances)
$browser = Get-Service SQLBrowser -ErrorAction SilentlyContinue
if ($browser) {
    Set-Service SQLBrowser -StartupType Automatic
    if ($browser.Status -ne "Running") {
        Start-Service SQLBrowser -ErrorAction SilentlyContinue
    }
}

Write-Host "    Networking configured."

# =====================================================================
# 7. CONFIGURE SQL SERVER FIREWALL RULES
# =====================================================================
Write-Host "[+] Configuring SQL Server firewall rules..."

# Remove existing SQL firewall rules if they exist
Get-NetFirewallRule -DisplayName "SQL Server (TCP 1433)" -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
Get-NetFirewallRule -DisplayName "SQL Browser (UDP 1434)" -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue

# Create SQL Server firewall rule for port 1433
New-NetFirewallRule -DisplayName "SQL Server (TCP 1433)" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 1433 `
    -Action Allow `
    -Profile Domain,Private,Public `
    -Description "Allows inbound TCP traffic for SQL Server connections" | Out-Null

# Create SQL Browser firewall rule for UDP 1434 (required for named instances)
New-NetFirewallRule -DisplayName "SQL Browser (UDP 1434)" `
    -Direction Inbound `
    -Protocol UDP `
    -LocalPort 1434 `
    -Action Allow `
    -Profile Domain,Private,Public `
    -Description "Allows SQL Browser service to respond to instance queries" | Out-Null

Write-Host "    SQL firewall rules configured."

# =====================================================================
# 8. INSTALL WSUS ROLE
# =====================================================================
Write-Host "[+] Installing WSUS role..."

$wsusFeatures = Get-WindowsFeature -Name UpdateServices-DB, UpdateServices-UI
$needsInstall = $wsusFeatures | Where-Object { $_.InstallState -ne 'Installed' }

if ($needsInstall) {
    Install-WindowsFeature -Name UpdateServices-DB, UpdateServices-UI -IncludeManagementTools | Out-Null
    Write-Host "    WSUS role installed."
} else {
    Write-Host "    WSUS role already installed."
}

# =====================================================================
# 9. CREATE WSUS DIRECTORIES WITH FULL PERMISSIONS
# =====================================================================
Write-Host "[+] Creating WSUS directories with proper permissions..."

@($WSUSRoot, $WSUSContent, "$WSUSRoot\UpdateServicesPackages") | ForEach-Object {
    New-Item -Path $_ -ItemType Directory -Force | Out-Null
}

# Set comprehensive permissions (from Check-WSUSContent.ps1)
# SYSTEM and Administrators - Full Control
icacls $WSUSRoot /grant "SYSTEM:(OI)(CI)F" /T /Q | Out-Null
icacls $WSUSRoot /grant "Administrators:(OI)(CI)F" /T /Q | Out-Null

# NETWORK SERVICE - Full Control (required for WSUS service)
icacls $WSUSRoot /grant "NETWORK SERVICE:(OI)(CI)F" /T /Q | Out-Null

# LOCAL SERVICE - Full Control
icacls $WSUSRoot /grant "NT AUTHORITY\LOCAL SERVICE:(OI)(CI)F" /T /Q | Out-Null

# IIS_IUSRS - Read (for web access)
icacls $WSUSRoot /grant "IIS_IUSRS:(OI)(CI)R" /T /Q | Out-Null

# WsusPool application pool identity - Full Control (will be created after IIS setup)
icacls $WSUSRoot /grant "IIS APPPOOL\WsusPool:(OI)(CI)F" /T /Q 2>$null

Write-Host "    Directories created and secured."

# =====================================================================
# 10. SQL PERMISSIONS FOR WSUS
# =====================================================================
Write-Host "[+] Granting SQL permissions to WSUS..."

# Wait for SQL to be fully ready
Start-Sleep -Seconds 5

$sqlInstance = ".\SQLEXPRESS"

# Refresh environment PATH to pick up sqlcmd
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# Find sqlcmd.exe (multiple possible locations)
$sqlcmdPaths = @(
    "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\sqlcmd.exe",
    "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\180\Tools\Binn\sqlcmd.exe",
    "C:\Program Files\Microsoft SQL Server\160\Tools\Binn\sqlcmd.exe",
    "C:\Program Files\Microsoft SQL Server\150\Tools\Binn\sqlcmd.exe"
)

$sqlcmd = $sqlcmdPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($sqlcmd) {
    try {
        # Create NETWORK SERVICE login if not exists
        & $sqlcmd -S $sqlInstance -E -Q "IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name='NT AUTHORITY\NETWORK SERVICE') CREATE LOGIN [NT AUTHORITY\NETWORK SERVICE] FROM WINDOWS;" -b
        
        # Grant dbcreator role to NETWORK SERVICE
        & $sqlcmd -S $sqlInstance -E -Q "ALTER SERVER ROLE [dbcreator] ADD MEMBER [NT AUTHORITY\NETWORK SERVICE];" -b
        
        Write-Host "    SQL permissions granted."
    } catch {
        Write-Host "    Warning: Could not configure SQL permissions. Error: $_"
    }
} else {
    Write-Host "    Warning: sqlcmd.exe not found. SQL permissions must be set manually."
    Write-Host "    Run these commands after SSMS finishes installing:"
    Write-Host "    sqlcmd -S .\SQLEXPRESS -E -Q `"CREATE LOGIN [NT AUTHORITY\NETWORK SERVICE] FROM WINDOWS`""
    Write-Host "    sqlcmd -S .\SQLEXPRESS -E -Q `"ALTER SERVER ROLE [dbcreator] ADD MEMBER [NT AUTHORITY\NETWORK SERVICE]`""
}

# =====================================================================
# 11. WSUS POSTINSTALL
# =====================================================================
Write-Host "[+] Running WSUS postinstall (this may take several minutes)..."

$wsusUtil = "C:\Program Files\Update Services\Tools\wsusutil.exe"

if (Test-Path $wsusUtil) {
    $postInstallArgs = "postinstall", "SQL_INSTANCE_NAME=`"$sqlInstance`"", "CONTENT_DIR=`"$WSUSContent`""
    
    $wsusProcess = Start-Process $wsusUtil -ArgumentList $postInstallArgs -Wait -PassThru -NoNewWindow
    
    if ($wsusProcess.ExitCode -eq 0) {
        Write-Host "    WSUS postinstall complete."
    } else {
        Write-Host "    Warning: WSUS postinstall exited with code $($wsusProcess.ExitCode)"
    }
} else {
    Write-Host "    Warning: wsusutil.exe not found at $wsusUtil"
}

# =====================================================================
# 12. CONFIGURE WSUS FIREWALL RULES
# =====================================================================
Write-Host "[+] Configuring Windows Firewall rules for WSUS..."

# Remove existing WSUS rules if they exist
$existingRules = @(
    "WSUS HTTP Traffic (Port 8530)",
    "WSUS HTTPS Traffic (Port 8531)",
    "WSUS API Remoting (Port 8530)",
    "WSUS API Remoting (Port 8531)"
)

foreach ($ruleName in $existingRules) {
    Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
}

# Create new WSUS firewall rules
New-NetFirewallRule -DisplayName "WSUS HTTP Traffic (Port 8530)" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 8530 `
    -Action Allow `
    -Profile Domain,Private,Public `
    -Description "Allows inbound HTTP traffic for WSUS client connections" | Out-Null

New-NetFirewallRule -DisplayName "WSUS HTTPS Traffic (Port 8531)" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 8531 `
    -Action Allow `
    -Profile Domain,Private,Public `
    -Description "Allows inbound HTTPS traffic for WSUS client connections" | Out-Null

New-NetFirewallRule -DisplayName "WSUS API Remoting (Port 8530)" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 8530 `
    -Action Allow `
    -Profile Domain,Private `
    -Program "C:\Program Files\Update Services\WebServices\ApiRemoting30\WebService\ApiRemoting30.asmx" `
    -Description "Allows WSUS API remoting traffic" -ErrorAction SilentlyContinue | Out-Null

New-NetFirewallRule -DisplayName "WSUS API Remoting (Port 8531)" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 8531 `
    -Action Allow `
    -Profile Domain,Private `
    -Program "C:\Program Files\Update Services\WebServices\ApiRemoting30\WebService\ApiRemoting30.asmx" `
    -Description "Allows WSUS API remoting traffic over HTTPS" -ErrorAction SilentlyContinue | Out-Null

Write-Host "    Firewall rules configured."

# =====================================================================
# 13. CONFIGURE WSUS REGISTRY SETTINGS
# =====================================================================
Write-Host "[+] Configuring WSUS registry settings..."

$wsusRegSetup = "HKLM:\SOFTWARE\Microsoft\Update Services\Server\Setup"
$wsusRegSetupInstalled = "HKLM:\SOFTWARE\Microsoft\Update Services\Server\Setup\Installed Role Services"

# Ensure registry paths exist
if (!(Test-Path $wsusRegSetup)) {
    New-Item -Path $wsusRegSetup -Force | Out-Null
}
if (!(Test-Path $wsusRegSetupInstalled)) {
    New-Item -Path $wsusRegSetupInstalled -Force | Out-Null
}

# Set content directory in registry (from Check-WSUSContent.ps1)
Set-ItemProperty -Path $wsusRegSetup -Name ContentDir -Value $WSUSContent -Force

# Disable the initial configuration wizard
$setupFlags = @{
    OobeInitialized          = 1
    OobeComplete             = 1
    SyncFromMicrosoftUpdate  = 0
    AllProductsEnabled       = 0
    AllClassificationsEnabled= 0
    AllLanguagesEnabled      = 0
}

foreach ($key in $setupFlags.Keys) {
    Set-ItemProperty -Path $wsusRegSetup -Name $key -Value $setupFlags[$key] -Force
}

# Mark role services as installed to prevent wizard
Set-ItemProperty -Path $wsusRegSetupInstalled -Name "UpdateServices-WidDatabase" -Value 2 -Force
Set-ItemProperty -Path $wsusRegSetupInstalled -Name "UpdateServices-Services" -Value 2 -Force
Set-ItemProperty -Path $wsusRegSetupInstalled -Name "UpdateServices-UI" -Value 2 -Force

Write-Host "    WSUS registry configured."

# =====================================================================
# 14. VERIFY AND START SERVICES
# =====================================================================
Write-Host "[+] Verifying and starting services..."

# Verify SQL Server is running
$sqlService = Get-Service 'MSSQL$SQLEXPRESS' -ErrorAction SilentlyContinue
if ($sqlService -and $sqlService.Status -ne "Running") {
    Write-Host "    Starting SQL Server service..."
    Start-Service 'MSSQL$SQLEXPRESS' -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
}
Write-Host "    SQL Server: $((Get-Service 'MSSQL$SQLEXPRESS' -ErrorAction SilentlyContinue).Status)"

# Verify SQL Browser is running
$browserService = Get-Service 'SQLBrowser' -ErrorAction SilentlyContinue
if ($browserService -and $browserService.Status -ne "Running") {
    Write-Host "    Starting SQL Browser service..."
    Start-Service 'SQLBrowser' -ErrorAction SilentlyContinue
}
Write-Host "    SQL Browser: $((Get-Service 'SQLBrowser' -ErrorAction SilentlyContinue).Status)"

# Verify IIS is running
$iisService = Get-Service 'W3SVC' -ErrorAction SilentlyContinue
if ($iisService -and $iisService.Status -ne "Running") {
    Write-Host "    Starting IIS service..."
    Start-Service 'W3SVC' -ErrorAction SilentlyContinue
}
Write-Host "    IIS (W3SVC): $((Get-Service 'W3SVC' -ErrorAction SilentlyContinue).Status)"

# Verify WSUS service is running
$wsusService = Get-Service 'WsusService' -ErrorAction SilentlyContinue
if ($wsusService -and $wsusService.Status -ne "Running") {
    Write-Host "    Starting WSUS service..."
    Start-Service 'WsusService' -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
}
Write-Host "    WSUS Service: $((Get-Service 'WsusService' -ErrorAction SilentlyContinue).Status)"

# Verify WsusPool application pool is running
try {
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    $appPool = Get-WebAppPoolState -Name "WsusPool" -ErrorAction SilentlyContinue
    if ($appPool -and $appPool.Value -ne "Started") {
        Write-Host "    Starting WsusPool application pool..."
        Start-WebAppPool -Name "WsusPool" -ErrorAction SilentlyContinue
    }
    Write-Host "    WsusPool: $((Get-WebAppPoolState -Name 'WsusPool' -ErrorAction SilentlyContinue).Value)"
} catch {
    Write-Host "    WsusPool: Could not verify (WebAdministration module not available)"
}

# =====================================================================
# 15. CONFIGURE IIS VIRTUAL DIRECTORY (from Check-WSUSContent.ps1)
# =====================================================================
Write-Host "[+] Verifying IIS virtual directory configuration..."

try {
    Import-Module WebAdministration -ErrorAction Stop
    $iisPath = Get-WebConfigurationProperty -Filter "/system.applicationHost/sites/site[@name='WSUS Administration']/application[@path='/']/virtualDirectory[@path='/Content']" -Name physicalPath -ErrorAction SilentlyContinue
    
    if ($iisPath -and $iisPath.Value -ne $WSUSContent) {
        Write-Host "    Updating IIS virtual directory path..."
        Set-WebConfigurationProperty -Filter "/system.applicationHost/sites/site[@name='WSUS Administration']/application[@path='/']/virtualDirectory[@path='/Content']" -Name physicalPath -Value $WSUSContent -ErrorAction SilentlyContinue
        Write-Host "    IIS virtual directory updated."
    } else {
        Write-Host "    IIS virtual directory is correct."
    }
} catch {
    Write-Host "    Could not verify IIS virtual directory: $_"
}

# =====================================================================
# 16. FINAL PERMISSIONS UPDATE (after WsusPool exists)
# =====================================================================
Write-Host "[+] Applying final permissions to WSUS content directory..."

# Re-apply WsusPool permissions now that it exists
icacls $WSUSContent /grant "IIS APPPOOL\WsusPool:(OI)(CI)F" /T /Q 2>$null

Write-Host "    Permissions applied."

# =====================================================================
# CLEANUP & COMPLETION
# =====================================================================
Write-Host "[+] Cleaning up..."

# Remove password file for security
Remove-Item $PasswordFile -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "==============================================================="
Write-Host " SQL Express 2022 + SSMS + WSUS Installation Complete!"
Write-Host "==============================================================="
Write-Host ""
Write-Host " SQL Server Instance: .\SQLEXPRESS"
Write-Host " TCP Port: 1433"
Write-Host " WSUS Content: $WSUSContent"
Write-Host " Full log: $LogFile"
Write-Host ""
Write-Host " Service Status:"
Write-Host "   SQL Server: $((Get-Service 'MSSQL$SQLEXPRESS' -ErrorAction SilentlyContinue).Status)"
Write-Host "   SQL Browser: $((Get-Service 'SQLBrowser' -ErrorAction SilentlyContinue).Status)"
Write-Host "   IIS: $((Get-Service 'W3SVC' -ErrorAction SilentlyContinue).Status)"
Write-Host "   WSUS: $((Get-Service 'WsusService' -ErrorAction SilentlyContinue).Status)"
Write-Host ""
Write-Host " Next steps:"
Write-Host " 1. Test SQL: sqlcmd -S .\SQLEXPRESS -U sa -P [your_password]"
Write-Host " 2. Configure WSUS via Update Services console"
Write-Host ""
Write-Host " If issues occur, run autofix.ps1 or Check-WSUSContent.ps1"
Write-Host "==============================================================="

Stop-Transcript | Out-Null
