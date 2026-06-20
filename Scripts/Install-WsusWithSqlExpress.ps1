<#
===============================================================================
Script: Install-WsusWithSqlExpress.ps1
Author: Tony Tran, ISSO, GA-ASI
Version: 1.1.0
Date: 2026-01-09
===============================================================================
Purpose: Fully automated SQL Express + WSUS installation (tested with SQL Server 2019 Express Advanced offline media). SSMS installed only if present.
Overview:
  - Extracts SQL Express and installs SQL Engine silently. Installs SSMS if installer is present.
  - Enables SQL networking, firewall rules, and WSUS role/services.
  - Configures WSUS content path, IIS virtual directory, and permissions.
Notes:
  - Run as Administrator on the WSUS server.
  - Logs to C:\WSUS\Logs\install.log
  - Requires installer files in specified InstallerPath (default: C:\WSUS\SQLDB)
  - Content folder must be C:\WSUS for correct DB file registration.
===============================================================================
#>

# Suppress PSScriptAnalyzer warning for ConvertTo-SecureString - this is necessary
# to convert plaintext passwords from CLI/GUI input to SecureString for secure storage
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '')]
param(
    [Parameter(HelpMessage = "Path to folder containing SQL Express installer (SSMS optional)")]
    [string]$InstallerPath = "C:\WSUS\SQLDB",
    [Parameter(HelpMessage = "SQL sa username")]
    [string]$SaUsername = "sa",
    [Parameter(HelpMessage = "SQL sa password (plain text; prefer -SaPasswordEnvVar for non-interactive runs)")]
    [string]$SaPassword,
    [Parameter(HelpMessage = "Name of environment variable containing the SQL sa password for non-interactive runs")]
    [string]$SaPasswordEnvVar = "WSUS_INSTALL_SA_PASSWORD",
    [Parameter(HelpMessage = "Run in non-interactive mode (no dialogs, fail on missing paths/passwords)")]
    [switch]$NonInteractive,
    [Parameter(HelpMessage = "Configure WSUS for HTTPS after install (default is HTTP on port 8530)")]
    [switch]$EnableHttps,
    [Parameter(HelpMessage = "Existing certificate thumbprint used when enabling HTTPS in non-interactive mode")]
    [string]$CertificateThumbprint,
    [Parameter(HelpMessage = "Hostname of the upstream WSUS server (makes this a downstream server)")]
    [string]$UpstreamServerHostname,
    [Parameter(HelpMessage = "Port of the upstream WSUS server (default 8530)")]
    [int]$UpstreamServerPort = 8530,
    [Parameter(HelpMessage = "Use SSL when connecting to the upstream server")]
    [switch]$UpstreamServerUseSsl,
    [switch]$IsReplica,
    [Parameter(HelpMessage = "Additional Windows accounts to grant SQL sysadmin during install")]
    [string[]]$SqlSysadminAccounts = @()
)

# -------------------------
# INSTALLER PATH VALIDATION
# -------------------------
$provisioningModule = Join-Path (Join-Path $PSScriptRoot '..\Modules') 'WsusProvisioning.psm1'
if (Test-Path $provisioningModule) {
    Import-Module $provisioningModule -Force -DisableNameChecking -ErrorAction SilentlyContinue
}

$installerCandidates = if (Get-Command Get-WsusSqlInstallerCandidates -ErrorAction SilentlyContinue) {
    Get-WsusSqlInstallerCandidates
} else {
    @("SQL2025-SSEI-Expr.exe", "SQLEXPRADV_x64_ENU.exe", "SQLEXPR_x64_ENU.exe")
}

function Find-SqlInstaller {
    param([string]$Dir)
    if (Get-Command Find-WsusSqlInstaller -ErrorAction SilentlyContinue) {
        $result = Find-WsusSqlInstaller -InstallerPath $Dir
        if ($result.Success) { return $result.InstallerFile }
        return $null
    }
    foreach ($name in $script:installerCandidates) {
        $p = Join-Path $Dir $name
        if (Test-Path $p) { return $p }
    }
    return $null
}

function Resolve-InstallerPath {
    param(
        [string]$Path,
        [switch]$NonInteractive
    )

    if (Get-Command Resolve-WsusInstallerPath -ErrorAction SilentlyContinue) {
        $resolution = Resolve-WsusInstallerPath -InstallerPath $Path
        if ($resolution.Success) {
            return $resolution.InstallerPath
        }

        if ($NonInteractive) {
            Write-Host "    ERROR: $($resolution.Message)" -ForegroundColor Red
            return $null
        }
    } elseif ($Path -and (Test-Path $Path) -and (Find-SqlInstaller $Path)) {
        return $Path
    } elseif ($NonInteractive) {
        if (-not $Path) {
            Write-Host "    ERROR: InstallerPath not specified and running in non-interactive mode." -ForegroundColor Red
        } elseif (-not (Test-Path $Path)) {
            Write-Host "    ERROR: InstallerPath does not exist: $Path" -ForegroundColor Red
        } else {
            Write-Host "    ERROR: No SQL Express installer found in $Path. Expected one of: $($script:installerCandidates -join ', ')" -ForegroundColor Red
        }
        return $null
    }

    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Select folder containing SQL Server Express installer (SQLEXPR_x64_ENU.exe or SQLEXPRADV_x64_ENU.exe). SSMS is optional."
    $dialog.SelectedPath = "C:\WSUS"

    if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        Write-Host "    Installation cancelled: SQL installer folder not selected." -ForegroundColor Yellow
        return $null
    }

    $selectedPath = $dialog.SelectedPath
    if (-not (Find-SqlInstaller $selectedPath)) {
        Write-Host "    No SQL Express installer found in: $selectedPath" -ForegroundColor Red
        return $null
    }

    return $selectedPath
}

$InstallerPath = Resolve-InstallerPath -Path $InstallerPath -NonInteractive:$NonInteractive
if (-not $InstallerPath) {
    Write-Host "    Aborting install: SQL installer files not found." -ForegroundColor Red
    exit 1
}

# -------------------------
# CONFIGURATION
# -------------------------
$LogFile         = "C:\WSUS\Logs\install.log"
$Extractor       = Find-SqlInstaller $InstallerPath
$ExtractPath     = Join-Path $InstallerPath "SQLExpressMedia"
$SSMSInstaller   = Join-Path $InstallerPath "SSMS-Setup-ENU.exe"
$WSUSRoot        = "C:\WSUS"
$WSUSContent     = "C:\WSUS"
$WSUSIisContent  = Join-Path $WSUSRoot "WsusContent"
$ConfigFile      = Join-Path $InstallerPath "ConfigurationFile.ini"
$PasswordFile    = Join-Path $InstallerPath "sa.encrypted"

# Detect existing installs to support reruns
$sqlService = Get-Service 'MSSQL$SQLEXPRESS' -ErrorAction SilentlyContinue
$sqlInstanceKey = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL"
$sqlInstanceExists = $false
if (Test-Path $sqlInstanceKey) {
    $sqlInstanceExists = $null -ne (Get-ItemProperty -Path $sqlInstanceKey -ErrorAction SilentlyContinue).SQLEXPRESS
}
$sqlInstalled = ($null -ne $sqlService) -or $sqlInstanceExists
$ssmsInstalled = $false
@(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
) | ForEach-Object {
    if (-not $ssmsInstalled) {
        $ssmsInstalled = (Get-ItemProperty $_ -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like "SQL Server Management Studio*" } |
            Select-Object -First 1) -ne $null
    }
}

# -------------------------
# LOGGING SETUP
# -------------------------
New-Item -Path "C:\WSUS\Logs" -ItemType Directory -Force | Out-Null
Start-Transcript -Path $LogFile -Append -ErrorAction Ignore | Out-Null
$ProgressPreference = "SilentlyContinue"
$ConfirmPreference  = "None"
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# =====================================================================
# SECURE SA PASSWORD (ONLY USER INPUT)
# =====================================================================
function Test-SAPasswordStrength {
    param([string]$Password)
    if ([string]::IsNullOrWhiteSpace($Password)) { return "Password is required." }
    if ($Password.Length -lt 15) { return "Must be >=15 chars." }
    if ($Password -notmatch "\d") { return "Must contain number." }
    if ($Password -notmatch "[^a-zA-Z0-9]") { return "Must contain special char." }
    return $null
}

function Get-SAPassword {
    <#
    .SYNOPSIS
        Prompts for SA password with validation, returns SecureString
    .OUTPUTS
        SecureString containing the validated password
    #>
    while ($true) {
        $pass1 = Read-Host "Enter SA password (15+ chars, 1 number, 1 special)" -AsSecureString
        $pass2 = Read-Host "Re-enter SA password" -AsSecureString

        # Convert to plain text only for validation (memory cleared after)
        $bstr1 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass1)
        $bstr2 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass2)
        try {
            $p1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr1)
            $p2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr2)

            if ($p1 -ne $p2) { Write-Host "Passwords do not match."; continue }
            $validationError = Test-SAPasswordStrength -Password $p1
            if ($validationError) { Write-Host $validationError; continue }

            # Return the SecureString, not plain text
            return $pass1
        } finally {
            # Zero out the BSTR memory for security
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr1)
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr2)
        }
    }
}

function New-SqlConnectionString {
    param(
        [Parameter(Mandatory)][string]$ServerInstance,
        [Parameter(Mandatory)][string]$Database,
        [System.Management.Automation.PSCredential]$Credential
    )

    $builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
    $builder['Data Source'] = $ServerInstance
    $builder['Initial Catalog'] = $Database
    $builder['Connect Timeout'] = 15
    $builder['Encrypt'] = $false
    if ($null -eq $Credential) {
        $builder['Integrated Security'] = $true
    } else {
        $builder['Integrated Security'] = $false
        $builder['User ID'] = $Credential.UserName
        $builder['Password'] = $Credential.GetNetworkCredential().Password
    }
    return $builder.ConnectionString
}

function Invoke-InstallSqlNonQuery {
    param(
        [Parameter(Mandatory)][string]$ServerInstance,
        [Parameter(Mandatory)][string]$Query,
        [System.Management.Automation.PSCredential]$Credential
    )

    $connectionString = New-SqlConnectionString -ServerInstance $ServerInstance -Database 'master' -Credential $Credential
    $connection = New-Object System.Data.SqlClient.SqlConnection $connectionString
    try {
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandText = $Query
        $command.CommandTimeout = 30
        [void]$command.ExecuteNonQuery()
    } finally {
        if ($command) { $command.Dispose() }
        $connection.Dispose()
    }
}

function Invoke-InstallSqlScalar {
    param(
        [Parameter(Mandatory)][string]$ServerInstance,
        [Parameter(Mandatory)][string]$Query,
        [System.Management.Automation.PSCredential]$Credential
    )

    $connectionString = New-SqlConnectionString -ServerInstance $ServerInstance -Database 'master' -Credential $Credential
    $connection = New-Object System.Data.SqlClient.SqlConnection $connectionString
    try {
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandText = $Query
        $command.CommandTimeout = 30
        return $command.ExecuteScalar()
    } finally {
        if ($command) { $command.Dispose() }
        $connection.Dispose()
    }
}

function Get-InstallSqlAdminAccounts {
    param([string[]]$AdditionalAccounts = @())

    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $accounts = New-Object System.Collections.Generic.List[string]
    if ($identity -and -not [string]::IsNullOrWhiteSpace($identity.Name)) {
        $accounts.Add($identity.Name)
    }
    if (-not [string]::IsNullOrWhiteSpace($env:USERDOMAIN)) {
        $accounts.Add("$env:USERDOMAIN\dod_admin")
    }
    foreach ($account in @($AdditionalAccounts)) {
        if (-not [string]::IsNullOrWhiteSpace($account)) {
            $accounts.Add($account)
        }
    }

    @($accounts | Select-Object -Unique)
}

function Grant-InstallSqlSysadmin {
    param(
        [Parameter(Mandatory)][string]$ServerInstance,
        [Parameter(Mandatory)][string]$LoginName,
        [System.Management.Automation.PSCredential]$SqlCredential
    )

    $loginLiteral = $LoginName -replace "'", "''"
    $query = @"
DECLARE @LoginName sysname = N'$loginLiteral';
IF SUSER_ID(@LoginName) IS NULL
BEGIN
    DECLARE @CreateLogin nvarchar(max) = N'CREATE LOGIN ' + QUOTENAME(@LoginName) + N' FROM WINDOWS';
    EXEC (@CreateLogin);
END;
IF IS_SRVROLEMEMBER(N'sysadmin', @LoginName) <> 1
BEGIN
    DECLARE @GrantRole nvarchar(max) = N'ALTER SERVER ROLE [sysadmin] ADD MEMBER ' + QUOTENAME(@LoginName);
    EXEC (@GrantRole);
END;
"@

    try {
        Invoke-InstallSqlNonQuery -ServerInstance $ServerInstance -Query $query
    } catch {
        if ($null -eq $SqlCredential) { throw }
        Invoke-InstallSqlNonQuery -ServerInstance $ServerInstance -Query $query -Credential $SqlCredential
    }

    try {
        $check = Invoke-InstallSqlScalar -ServerInstance $ServerInstance -Query "SELECT COUNT(*) FROM sys.server_role_members rm JOIN sys.server_principals r ON rm.role_principal_id = r.principal_id JOIN sys.server_principals m ON rm.member_principal_id = m.principal_id WHERE r.name = 'sysadmin' AND m.name = N'$loginLiteral';"
    } catch {
        if ($null -eq $SqlCredential) { throw }
        $check = Invoke-InstallSqlScalar -ServerInstance $ServerInstance -Query "SELECT COUNT(*) FROM sys.server_role_members rm JOIN sys.server_principals r ON rm.role_principal_id = r.principal_id JOIN sys.server_principals m ON rm.member_principal_id = m.principal_id WHERE r.name = 'sysadmin' AND m.name = N'$loginLiteral';" -Credential $SqlCredential
    }
    return ([int]$check -gt 0)
}

function Stop-SqlExpressSetup {
    param(
        [string]$SetupPath
    )

    $setupProcesses = Get-CimInstance Win32_Process -Filter "Name='setup.exe'" |
        Where-Object {
            $_.CommandLine -and $_.CommandLine -like "*$SetupPath*setup.exe*"
        }

    if ($setupProcesses) {
        Write-Host "    Detected SQL setup already running from extraction. Stopping to avoid conflict."
        foreach ($process in $setupProcesses) {
            Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Seconds 3
    }
}

function Wait-WithHeartbeat {
    param(
        [Parameter(Mandatory)][System.Diagnostics.Process]$Process,
        [Parameter(Mandatory)][string]$Message
    )
    Write-Host "    $Message"
    while (-not $Process.HasExited) {
        Start-Sleep -Seconds 15
        Write-Host "." -NoNewline
        [Console]::Out.Flush()
    }
    # Ensure ExitCode is populated (Start-Process -PassThru can leave it null without this)
    $Process.WaitForExit()
    Write-Host ""
    [Console]::Out.Flush()
}

function Expand-SqlInstallerMedia {
    param(
        [Parameter(Mandatory)][string]$InstallerPath,
        [Parameter(Mandatory)][string]$ExtractPath
    )

    if (!(Test-Path $InstallerPath)) {
        throw "SQL installer missing at $InstallerPath"
    }

    if (Test-Path (Join-Path $ExtractPath 'setup.exe')) {
        return
    }

    $fileName = Split-Path $InstallerPath -Leaf
    $isBootstrapper = ($fileName -match 'SSEI|SQL20\d{2}-SSEI') -or ((Get-Item $InstallerPath).Length -lt 50MB)
    if ($isBootstrapper) {
        $downloadArgs = @('/Action=Download', "/MediaPath=$ExtractPath", '/MediaType=Core', '/Quiet')
        $downloadProcess = Start-Process $InstallerPath -ArgumentList $downloadArgs -PassThru -NoNewWindow
        Wait-WithHeartbeat -Process $downloadProcess -Message "Downloading SQL Express media (this can take several minutes)..."
        $resolvedAfterDownload = Resolve-SqlSetupExe -ExtractPath $ExtractPath
        if (-not $resolvedAfterDownload -and $null -ne $downloadProcess.ExitCode -and $downloadProcess.ExitCode -ne 0) {
            throw "SQL Express media download failed with exit code $($downloadProcess.ExitCode)"
        }
    } else {
        $extractArgs = @('/Q', "/x:$ExtractPath")
        $extractProcess = Start-Process $InstallerPath -ArgumentList $extractArgs -PassThru -NoNewWindow
        Wait-WithHeartbeat -Process $extractProcess -Message "Extracting SQL Express (this can take a few minutes)..."
        $resolvedAfterExtract = Resolve-SqlSetupExe -ExtractPath $ExtractPath
        if (-not $resolvedAfterExtract -and $null -ne $extractProcess.ExitCode -and $extractProcess.ExitCode -ne 0) {
            throw "SQL Express extraction failed with exit code $($extractProcess.ExitCode)"
        }
    }
}
function Resolve-SqlSetupExe {
    param([Parameter(Mandatory)][string]$ExtractPath)

    $direct = Join-Path $ExtractPath 'setup.exe'
    if (Test-Path $direct) { return $direct }

    $nested = Get-ChildItem -Path $ExtractPath -Recurse -Filter 'setup.exe' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if ($nested) { return $nested }

    foreach ($candidate in $script:installerCandidates) {
        $candidatePath = Join-Path $ExtractPath $candidate
        if (Test-Path $candidatePath) { return $candidatePath }
    }

    return $null
}

function Invoke-WsusHttpsSetup {
    param(
        [string]$CertificateThumbprint,
        [switch]$NonInteractive
    )

    $httpsScriptCandidates = @(
        (Join-Path $PSScriptRoot "Set-WsusHttps.ps1"),
        (Join-Path $PSScriptRoot "Scripts\Set-WsusHttps.ps1"),
        (Join-Path (Split-Path $PSScriptRoot -Parent) "Scripts\Set-WsusHttps.ps1")
    )

    $httpsScript = $httpsScriptCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $httpsScript) {
        throw "Set-WsusHttps.ps1 not found. Searched: $($httpsScriptCandidates -join '; ')"
    }

    if ($NonInteractive -and [string]::IsNullOrWhiteSpace($CertificateThumbprint)) {
        throw "-EnableHttps with -NonInteractive requires -CertificateThumbprint."
    }

    $powershellExe = Join-Path $PSHOME "powershell.exe"
    if (-not (Test-Path $powershellExe)) {
        $powershellExe = "powershell.exe"
    }

    $httpsArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $httpsScript)
    if (-not [string]::IsNullOrWhiteSpace($CertificateThumbprint)) {
        $httpsArgs += @("-CertificateThumbprint", $CertificateThumbprint)
    }

    & $powershellExe @httpsArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Set-WsusHttps.ps1 exited with code $LASTEXITCODE."
    }
}

# Get or retrieve password as SecureString. Non-interactive callers should pass
# only the environment variable name on the command line so the password value
# does not appear in process listings.
$envSaPassword = if (-not [string]::IsNullOrWhiteSpace($SaPasswordEnvVar)) {
    [Environment]::GetEnvironmentVariable($SaPasswordEnvVar)
} else {
    $null
}
$effectiveSaPassword = if (-not [string]::IsNullOrWhiteSpace($SaPassword)) { $SaPassword } else { $envSaPassword }

if ($effectiveSaPassword) {
    $validationError = Test-SAPasswordStrength -Password $effectiveSaPassword
    if ($validationError) {
        Write-Host "    Invalid SA password: $validationError" -ForegroundColor Red
        exit 1
    }
    $securePass = ConvertTo-SecureString $effectiveSaPassword -AsPlainText -Force
    $securePass | ConvertFrom-SecureString | Set-Content $PasswordFile
} elseif (!(Test-Path $PasswordFile)) {
    # In non-interactive mode, fail if password not provided
    if ($NonInteractive) {
        Write-Host "    ERROR: SA password is required in non-interactive mode. Use -SaPasswordEnvVar or set the named environment variable." -ForegroundColor Red
        exit 1
    }
    $securePass = Get-SAPassword
    # Store encrypted SecureString (Get-SAPassword now returns SecureString directly)
    $securePass | ConvertFrom-SecureString | Set-Content $PasswordFile
} else {
    # Retrieve stored password as SecureString
    $securePass = Get-Content $PasswordFile | ConvertTo-SecureString
}

# Convert to plain text only when needed for SQL setup config
$SA_Password = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePass))

# =====================================================================
# 1. EXTRACT SQL EXPRESS ADV PACKAGE
# =====================================================================
Write-Host "[+] Extracting SQL package..."
if ($sqlInstalled) {
    Write-Host "    SQL Server already installed. Skipping extraction."
} else {
    if (!(Test-Path $Extractor)) { throw "SQL extractor missing at $Extractor" }

    Expand-SqlInstallerMedia -InstallerPath $Extractor -ExtractPath $ExtractPath
    $resolvedSetupExe = Resolve-SqlSetupExe -ExtractPath $ExtractPath
    if (-not $resolvedSetupExe) {
        throw "Could not find setup.exe under $ExtractPath after preparing SQL media."
    }
    Write-Host "    SQL media ready: $resolvedSetupExe"
    Stop-SqlExpressSetup -SetupPath (Split-Path $resolvedSetupExe -Parent)
}

# =====================================================================
# 2. CREATE SQL CONFIGURATION FILE
# =====================================================================
Write-Host "[+] Creating SQL configuration file..."

if ($sqlInstalled) {
    Write-Host "    SQL Server already installed. Skipping config file generation."
} else {
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
UPDATEENABLED="0"
"@

    Set-Content -Path $ConfigFile -Value $configContent -Force
}

# =====================================================================
# 3. INSTALL SQL ENGINE VIA SETUP.EXE (FULLY SILENT)
# =====================================================================
Write-Host "[+] Installing SQL Server Express..."

if ($sqlInstalled) {
    Write-Host "    SQL Server already installed. Skipping SQL setup."
} else {
    $setupExe = Resolve-SqlSetupExe -ExtractPath $ExtractPath
    if (!(Test-Path $setupExe)) {
        throw "Cannot find setup.exe under $ExtractPath"
    }

    $setupProcess = Start-Process $setupExe -ArgumentList "/CONFIGURATIONFILE=`"$ConfigFile`"" -PassThru -NoNewWindow
    try {
        Wait-WithHeartbeat -Process $setupProcess -Message "Installing SQL Server Express (this can take several minutes)..."
    } finally {
        # Scrub SA password from config file immediately (don't leave it on disk)
        if (Test-Path $ConfigFile) {
            (Get-Content $ConfigFile) -replace 'SAPWD="[^"]*"', 'SAPWD=""' | Set-Content $ConfigFile -Force
        }
    }

    $sqlExitCode = $setupProcess.ExitCode
    if ($null -ne $sqlExitCode -and $sqlExitCode -ne 0 -and $sqlExitCode -ne 3010) {
        $logRoot = "C:\Program Files\Microsoft SQL Server"
        $summaryPath = Get-ChildItem "$logRoot\*\Setup Bootstrap\Log\Summary.txt" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
        if (-not $summaryPath) { $summaryPath = "$logRoot\Setup Bootstrap\Log\Summary.txt" }
        throw "SQL installation failed with exit code $sqlExitCode. Check log at $summaryPath"
    }

    Write-Host "    SQL installation complete."
}

# =====================================================================
# 4. INSTALL SSMS (PASSIVE MODE, NO GUI INTERACTION)
# =====================================================================
Write-Host "[+] Installing SSMS..."
if ($ssmsInstalled) {
    Write-Host "    SSMS already installed. Skipping."
} elseif (Test-Path $SSMSInstaller) {
    $ssmsProcess = Start-Process $SSMSInstaller -ArgumentList "/install", "/passive", "/norestart" -PassThru -NoNewWindow
    Wait-WithHeartbeat -Process $ssmsProcess -Message "Installing SSMS (this can take several minutes)..."
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

# Dynamically find the MSSQL registry key (MSSQL16 for 2022, MSSQL15 for 2019, etc.)
$instanceKey = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL"
$mssqlRoot = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server"
$instanceId = $null
if (Test-Path $instanceKey) {
    $instanceId = (Get-ItemProperty -Path $instanceKey -ErrorAction SilentlyContinue).SQLEXPRESS
}
if (-not $instanceId) {
    # Fallback: scan for the instance directory
    $instanceId = (Get-ChildItem "$mssqlRoot\MSSQL*.SQLEXPRESS" -ErrorAction SilentlyContinue |
        Select-Object -First 1).PSChildName
}
if (-not $instanceId) {
    $instanceId = "MSSQL15.SQLEXPRESS"  # Prefer SQL 2019 fallback when detection fails
    Write-Host "    Warning: Could not detect SQL instance registry key, using fallback: $instanceId" -ForegroundColor Yellow
}
$root = "$mssqlRoot\$instanceId\MSSQLServer\SuperSocketNetLib"

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
# 7. INSTALL WSUS ROLE
# =====================================================================
Write-Host "[+] Installing WSUS role..."

# Check if WSUS is currently installed with WID (Windows Internal Database).
# If so, fully uninstall WSUS and reinstall with UpdateServices-DB (external SQL).
# This is the only reliable way - wsusutil postinstall ignores SQL_INSTANCE_NAME
# when UpdateServices-WidDB feature is installed.
$widFeature = Get-WindowsFeature -Name UpdateServices-WidDB -ErrorAction SilentlyContinue

if ($widFeature -and $widFeature.InstallState -eq 'Installed') {
    Write-Host "    WSUS is installed with WID - removing to reinstall with SQL Express..."
    Stop-Service WSUSService -Force -ErrorAction SilentlyContinue
    Stop-Service W3SVC -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    Uninstall-WindowsFeature -Name UpdateServices -IncludeManagementTools -ErrorAction SilentlyContinue | Out-Null
    Write-Host "    WSUS role removed."

    # Remove leftover WID data files so postinstall creates SUSDB fresh on SQL Express
    # If these files exist, postinstall tries to re-attach them instead of creating new
    $widFiles = @("C:\Windows\WID\Data\SUSDB.mdf", "C:\Windows\WID\Data\SUSDB_log.ldf")
    foreach ($wf in $widFiles) {
        if (Test-Path $wf) {
            Remove-Item $wf -Force -ErrorAction SilentlyContinue
            Write-Host "    Cleaned up: $wf"
        }
    }

    # A reboot may be required after feature uninstall/reinstall.
    # Check if a reboot is pending and warn the user.
    $rebootPending = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing" -Name RebootPending -ErrorAction SilentlyContinue) -or
                     (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update" -Name RebootRequired -ErrorAction SilentlyContinue)
    if ($rebootPending) {
        Write-Host "    NOTE: A server restart may be required. If WSUS fails to start," -ForegroundColor Yellow
        Write-Host "    restart the server and run this installer again." -ForegroundColor Yellow
    }

    Start-Sleep -Seconds 3
    Start-Service W3SVC -ErrorAction SilentlyContinue
}

# Install WSUS with UpdateServices-DB (external SQL support).
# This is the key difference from the default install which uses UpdateServices-WidDB.
# With UpdateServices-DB, wsusutil postinstall accepts SQL_INSTANCE_NAME.
$dbFeature = Get-WindowsFeature -Name UpdateServices-DB -ErrorAction SilentlyContinue

if (-not $dbFeature -or $dbFeature.InstallState -ne 'Installed') {
    Write-Host "    Installing WSUS role with SQL Express support..."
    Install-WindowsFeature -Name UpdateServices-Services, UpdateServices-DB, UpdateServices-UI -IncludeManagementTools | Out-Null
    Write-Host "    WSUS role installed (SQL Express mode)."
} else {
    Write-Host "    WSUS role already installed with SQL Express support."
}

# =====================================================================
# 8. CREATE WSUS DIRECTORIES WITH FULL PERMISSIONS
# =====================================================================
Write-Host "[+] Creating WSUS directories with proper permissions..."

@($WSUSRoot, $WSUSIisContent, "$WSUSRoot\UpdateServicesPackages") | ForEach-Object {
    New-Item -Path $_ -ItemType Directory -Force | Out-Null
}

# Set comprehensive permissions (kept in sync with WsusPermissions.psm1)
# SYSTEM and Administrators - Full Control
icacls $WSUSRoot /grant "NT AUTHORITY\SYSTEM:(OI)(CI)F" /T /Q | Out-Null
icacls $WSUSRoot /grant "BUILTIN\Administrators:(OI)(CI)F" /T /Q | Out-Null

# NETWORK SERVICE - Full Control (required for WSUS service)
icacls $WSUSRoot /grant "NT AUTHORITY\NETWORK SERVICE:(OI)(CI)F" /T /Q | Out-Null

# LOCAL SERVICE - Full Control
icacls $WSUSRoot /grant "NT AUTHORITY\LOCAL SERVICE:(OI)(CI)F" /T /Q | Out-Null

# IIS_IUSRS and Authenticated Users - list folder/read/execute for content downloads
icacls $WSUSRoot /grant "BUILTIN\IIS_IUSRS:(OI)(CI)RX" /T /Q | Out-Null
icacls $WSUSRoot /grant "NT AUTHORITY\Authenticated Users:(OI)(CI)RX" /T /Q | Out-Null

# WsusPool application pool identity - Full Control (will be created after IIS setup)
$wsusPoolExists = $false
if (Get-Command Get-WebAppPoolState -ErrorAction SilentlyContinue) {
    if (Test-Path IIS:\AppPools\WsusPool) {
        $wsusPoolExists = $true
    }
}
if ($wsusPoolExists) {
    icacls $WSUSRoot /grant "IIS APPPOOL\WsusPool:(OI)(CI)F" /T /Q 2>$null
} else {
    Write-Host "    WsusPool application pool not found yet; will apply permissions after IIS setup."
}

Write-Host "    Directories created and secured."

# =====================================================================
# 9. SQL PERMISSIONS FOR WSUS
# =====================================================================
Write-Host "[+] Granting SQL permissions to WSUS..."

# Wait for SQL to be fully ready
Start-Sleep -Seconds 5

$sqlInstance = ".\SQLEXPRESS"
$saCredential = New-Object System.Management.Automation.PSCredential($SaUsername, (ConvertTo-SecureString $SA_Password -AsPlainText -Force))


$adminAccounts = Get-InstallSqlAdminAccounts -AdditionalAccounts $SqlSysadminAccounts
foreach ($adminAccount in $adminAccounts) {
    try {
        Write-Host "    Adding sysadmin for: $adminAccount"
        if (Grant-InstallSqlSysadmin -ServerInstance $sqlInstance -LoginName $adminAccount -SqlCredential $saCredential) {
            Write-Host "    sysadmin granted: $adminAccount"
        } else {
            Write-Host "    Warning: sysadmin verification failed for $adminAccount" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "    Warning: Could not grant sysadmin to $adminAccount. Error: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

try {
    $networkServiceQuery = @"
IF SUSER_ID(N'NT AUTHORITY\NETWORK SERVICE') IS NULL
    CREATE LOGIN [NT AUTHORITY\NETWORK SERVICE] FROM WINDOWS;
IF IS_SRVROLEMEMBER(N'dbcreator', N'NT AUTHORITY\NETWORK SERVICE') <> 1
    ALTER SERVER ROLE [dbcreator] ADD MEMBER [NT AUTHORITY\NETWORK SERVICE];
"@
    Invoke-InstallSqlNonQuery -ServerInstance $sqlInstance -Query $networkServiceQuery -Credential $saCredential
    Write-Host "    SQL permissions granted."
} catch {
    Write-Host "    Warning: Could not configure SQL service permissions. Error: $($_.Exception.Message)" -ForegroundColor Yellow
}

# =====================================================================
# 10. PRE-CONFIGURE WSUS REGISTRY (before postinstall)
# =====================================================================
# Set OobeInitialized/OobeComplete before postinstall to prevent the
# WSUS Configuration Wizard from launching when the console opens.
# These are re-applied in step 12 in case postinstall overwrites them.
$wsusRegPreSetup = "HKLM:\SOFTWARE\Microsoft\Update Services\Server\Setup"
if (!(Test-Path $wsusRegPreSetup)) {
    New-Item -Path $wsusRegPreSetup -Force | Out-Null
}
Set-ItemProperty -Path $wsusRegPreSetup -Name OobeInitialized -Value 1 -Force
Set-ItemProperty -Path $wsusRegPreSetup -Name OobeComplete -Value 1 -Force
Set-ItemProperty -Path $wsusRegPreSetup -Name ServerConfigurationComplete -Value 1 -Type DWord -Force
# Per-user wizard suppression (prevents MMC console wizard)
$userWsusKey = "HKCU:\Software\Microsoft\Update Services\Server\Setup"
if (!(Test-Path $userWsusKey)) { New-Item -Path $userWsusKey -Force | Out-Null }
Set-ItemProperty -Path $userWsusKey -Name WizardComplete -Value 1 -Type DWord -Force
Write-Host "[+] Pre-configured WSUS wizard suppression registry keys."

# =====================================================================
# 11. WSUS POSTINSTALL
# =====================================================================
$wsusProtocol = "HTTP"
$wsusPort = 8530

$wsusUtil = "C:\Program Files\Update Services\Tools\wsusutil.exe"

if (Test-Path $wsusUtil) {
    Write-Host "[+] Running WSUS postinstall (this may take several minutes)..."
    $postInstallArgs = "postinstall", "SQL_INSTANCE_NAME=`"$sqlInstance`"", "CONTENT_DIR=`"$WSUSContent`""

    $wsusProcess = Start-Process $wsusUtil -ArgumentList $postInstallArgs -PassThru -NoNewWindow
    Wait-WithHeartbeat -Process $wsusProcess -Message "Configuring WSUS post-install steps (this can take several minutes)..."

    $exitCode = $wsusProcess.ExitCode
    if ($null -eq $exitCode -or $exitCode -eq 0) {
        Write-Host "    WSUS postinstall complete."
    } else {
        Write-Host "    Warning: WSUS postinstall exited with code $exitCode"
    }
} else {
    Write-Host "    Warning: wsusutil.exe not found at $wsusUtil"
}

if ($EnableHttps) {
    Write-Host "[+] HTTPS mode requested. Configuring WSUS for SSL (port 8531)..."
    try {
        Invoke-WsusHttpsSetup -CertificateThumbprint $CertificateThumbprint -NonInteractive:$NonInteractive
        $wsusProtocol = "HTTPS"
        $wsusPort = 8531
        Write-Host "    WSUS HTTPS configuration complete."
    } catch {
        Write-Host "    ERROR: HTTPS configuration failed: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "    WSUS configured for HTTP on port 8530 (default)."
}

# =====================================================================
# 11. CONFIGURE WSUS FIREWALL RULES
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
New-NetFirewallRule -DisplayName "WSUS HTTP Traffic (Port 8530)" `
    -Direction Inbound -Protocol TCP -LocalPort 8530 -Action Allow `
    -Profile Domain,Private,Public `
    -Description "Allows inbound HTTP traffic for WSUS client connections" | Out-Null
New-NetFirewallRule -DisplayName "WSUS HTTPS Traffic (Port 8531)" `
    -Direction Inbound -Protocol TCP -LocalPort 8531 -Action Allow `
    -Profile Domain,Private,Public `
    -Description "Allows inbound HTTPS traffic for WSUS client connections" | Out-Null
New-NetFirewallRule -DisplayName "WSUS API Remoting (Port 8530)" `
    -Direction Inbound -Protocol TCP -LocalPort 8530 -Action Allow `
    -Profile Domain,Private `
    -Program "C:\Program Files\Update Services\WebServices\ApiRemoting30\WebService\ApiRemoting30.asmx" `
    -Description "Allows WSUS API remoting traffic" -ErrorAction SilentlyContinue | Out-Null
New-NetFirewallRule -DisplayName "WSUS API Remoting (Port 8531)" `
    -Direction Inbound -Protocol TCP -LocalPort 8531 -Action Allow `
    -Profile Domain,Private `
    -Program "C:\Program Files\Update Services\WebServices\ApiRemoting30\WebService\ApiRemoting30.asmx" `
    -Description "Allows WSUS API remoting traffic over HTTPS" -ErrorAction SilentlyContinue | Out-Null

# =====================================================================
# 12. CONFIGURE WSUS REGISTRY SETTINGS & SUPPRESS CONFIGURATION WIZARD
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

# Set content directory in registry
Set-ItemProperty -Path $wsusRegSetup -Name ContentDir -Value $WSUSContent -Force

# Suppress the WSUS Configuration Wizard (OOBE)
# These must be set AFTER postinstall completes, as postinstall may reset them.
# OobeInitialized=1 + OobeComplete=1 tells the WSUS console the wizard has already run.
# SyncFromMicrosoftUpdate=1 is REQUIRED for WSUS to actually sync with Microsoft.
$setupFlags = @{
    OobeInitialized          = 1
    OobeComplete             = 1
    SyncFromMicrosoftUpdate  = 1
    AllProductsEnabled       = 0
    AllClassificationsEnabled= 0
    AllLanguagesEnabled      = 0
}

foreach ($key in $setupFlags.Keys) {
    Set-ItemProperty -Path $wsusRegSetup -Name $key -Value $setupFlags[$key] -Force
}

# Mark role services as installed (Services + UI, NOT WidDatabase since we use SQL Express)
Set-ItemProperty -Path $wsusRegSetupInstalled -Name "UpdateServices-Services" -Value 2 -Force
Set-ItemProperty -Path $wsusRegSetupInstalled -Name "UpdateServices-UI" -Value 2 -Force

Write-Host "    WSUS registry configured."

# Restart WSUS service so it reads the updated registry values
Write-Host "    Restarting WSUS service to apply configuration..."
Restart-Service WsusService -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5
Write-Host "    WSUS service restarted."

# =====================================================================
# 12a. CONFIGURE UPDATE LANGUAGE (English only)
# =====================================================================
Write-Host "[+] Configuring update language to English..."
try {
    Add-Type -Path "$env:ProgramFiles\Update Services\Api\Microsoft.UpdateServices.Administration.dll" -ErrorAction SilentlyContinue
    $wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer("localhost", $false, 8530)
    $config = $wsus.GetConfiguration()
    $config.AllUpdateLanguagesEnabled = $false
    $config.SetEnabledUpdateLanguages(@("en"))
    # Suppress WSUS configuration wizard via API
    $config.OobeInitialized = $true
    $config.Save()
    Write-Host "    Language set to English only."
    Write-Host "    Configuration wizard suppressed."
    # Configure default classifications: Critical, Security, Definition, Updates, Update Rollups
    Write-Host "[+] Configuring default update classifications..."
    $sub = $wsus.GetSubscription()
    $allClassifications = $wsus.GetUpdateClassifications()
    $defaultClassNames = @("Critical Updates", "Security Updates", "Definition Updates", "Updates", "Update Rollups")
    $classColl = New-Object Microsoft.UpdateServices.Administration.UpdateClassificationCollection
    foreach ($name in $defaultClassNames) {
        $cls = $allClassifications | Where-Object { $_.Title -eq $name }
        if ($cls) { $classColl.Add($cls) }
    }
    $sub.SetUpdateClassifications($classColl)
    $sub.Save()
    Write-Host "    Classifications: $($defaultClassNames -join ', ')"
} catch {
    Write-Host "    Warning: Failed to set language/classifications: $($_.Exception.Message)"
}

# =====================================================================
# 12b. CONFIGURE UPSTREAM/DOWNSTREAM SERVER ROLE
# =====================================================================
if ($UpstreamServerHostname) {
    Write-Host "[+] Configuring as downstream server..."
    Write-Host "    Upstream: $UpstreamServerHostname`:$UpstreamServerPort (SSL: $UpstreamServerUseSsl)"
    Write-Host "    Mode: $(if ($IsReplica) { 'Replica' } else { 'Autonomous' })"

    try {
        [reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration") | Out-Null
        $wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer('localhost', $false, 8530)
        $config = $wsus.GetConfiguration()

        $config.SyncFromMicrosoftUpdate = $false
        $config.UpstreamWsusServerName = $UpstreamServerHostname
        $config.UpstreamWsusServerPortNumber = $UpstreamServerPort
        $config.UpstreamWsusServerUseSsl = [bool]$UpstreamServerUseSsl
        $config.IsReplicaServer = [bool]$IsReplica

        $config.Save()
        Write-Host "    Downstream configuration applied."

        # Set registry to match
        Set-ItemProperty -Path $wsusRegSetup -Name SyncFromMicrosoftUpdate -Value 0 -Force
    } catch {
        Write-Host "    Warning: Failed to configure downstream settings: $($_.Exception.Message)"
        Write-Host "    You can configure this manually in the WSUS console."
    }
} else {
    Write-Host "[+] Server role: Upstream (syncs from Microsoft Update)"
    # SyncFromMicrosoftUpdate=1 is set in registry flags above (step 12).
}

# =====================================================================
# 13. CONFIGURE SQL SERVER FIREWALL RULES
# =====================================================================
# Remove existing SQL firewall rules if they exist
Get-NetFirewallRule -DisplayName "SQL Server (TCP 1433)" -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
Get-NetFirewallRule -DisplayName "SQL Browser (UDP 1434)" -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue

# Create SQL Server firewall rules
New-NetFirewallRule -DisplayName "SQL Server (TCP 1433)" `
    -Direction Inbound -Protocol TCP -LocalPort 1433 -Action Allow `
    -Profile Domain,Private,Public `
    -Description "Allows inbound TCP traffic for SQL Server connections" | Out-Null
New-NetFirewallRule -DisplayName "SQL Browser (UDP 1434)" `
    -Direction Inbound -Protocol UDP -LocalPort 1434 -Action Allow `
    -Profile Domain,Private,Public `
    -Description "Allows SQL Browser service to respond to instance queries" | Out-Null

Write-Host "    SQL firewall rules configured."

# =====================================================================
# 14. VERIFY AND START SERVICES
# =====================================================================
Write-Host "[+] Verifying and starting services..."

# Verify and start WSUS-related services
$sqlService = Get-Service 'MSSQL$SQLEXPRESS' -ErrorAction SilentlyContinue
if ($sqlService -and $sqlService.Status -ne "Running") {
    Write-Host "    Starting SQL Server service..."
    Start-Service 'MSSQL$SQLEXPRESS' -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
}
Write-Host "    SQL Server: $((Get-Service 'MSSQL$SQLEXPRESS' -ErrorAction SilentlyContinue).Status)"
$browserService = Get-Service 'SQLBrowser' -ErrorAction SilentlyContinue
if ($browserService -and $browserService.Status -ne "Running") {
    Write-Host "    Starting SQL Browser service..."
    Start-Service 'SQLBrowser' -ErrorAction SilentlyContinue
}
Write-Host "    SQL Browser: $((Get-Service 'SQLBrowser' -ErrorAction SilentlyContinue).Status)"
$iisService = Get-Service 'W3SVC' -ErrorAction SilentlyContinue
if ($iisService -and $iisService.Status -ne "Running") {
    Write-Host "    Starting IIS service..."
    Start-Service 'W3SVC' -ErrorAction SilentlyContinue
}
Write-Host "    IIS (W3SVC): $((Get-Service 'W3SVC' -ErrorAction SilentlyContinue).Status)"
$wsusService = Get-Service 'WsusService' -ErrorAction SilentlyContinue
if ($wsusService -and $wsusService.Status -ne "Running") {
    Write-Host "    Starting WSUS service..."
    Start-Service 'WsusService' -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
}
Write-Host "    WSUS Service: $((Get-Service 'WsusService' -ErrorAction SilentlyContinue).Status)"

# Verify WsusPool application pool is running (WSUS-specific, not part of canonical baseline)
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
# 15. CONFIGURE IIS VIRTUAL DIRECTORY (from Repair-WsusContentPath.ps1)
# =====================================================================
Write-Host "[+] Verifying IIS virtual directory configuration..."

try {
    Import-Module WebAdministration -ErrorAction Stop
    $iisPath = Get-WebConfigurationProperty -Filter "/system.applicationHost/sites/site[@name='WSUS Administration']/application[@path='/']/virtualDirectory[@path='/Content']" -Name physicalPath -ErrorAction SilentlyContinue
    
    if ($iisPath -and $iisPath.Value -ne $WSUSIisContent) {
        Write-Host "    Updating IIS virtual directory path..."
        Set-WebConfigurationProperty -Filter "/system.applicationHost/sites/site[@name='WSUS Administration']/application[@path='/']/virtualDirectory[@path='/Content']" -Name physicalPath -Value $WSUSIisContent -ErrorAction SilentlyContinue
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

# Re-apply WsusPool and read principals now that IIS exists
icacls $WSUSIisContent /grant "IIS APPPOOL\WsusPool:(OI)(CI)F" /T /Q 2>$null
icacls $WSUSIisContent /grant "BUILTIN\IIS_IUSRS:(OI)(CI)RX" /T /Q | Out-Null
icacls $WSUSIisContent /grant "NT AUTHORITY\Authenticated Users:(OI)(CI)RX" /T /Q | Out-Null

Write-Host "    Permissions applied."

# =====================================================================
# CLEANUP & COMPLETION
# =====================================================================
Write-Host "[+] Cleaning up..."

# Remove password file for security
Remove-Item $PasswordFile -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "==============================================================="
Write-Host " SQL Express + WSUS Installation Complete!"
Write-Host "==============================================================="
Write-Host ""
Write-Host " SQL Server Instance: .\SQLEXPRESS"
Write-Host " TCP Port: 1433"
Write-Host " WSUS Protocol: $wsusProtocol"
Write-Host " WSUS Port: $wsusPort"
Write-Host " WSUS Root: $WSUSRoot"
Write-Host " IIS /Content: $WSUSIisContent"
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
Write-Host " If issues occur, run:"
Write-Host "   .\\Test-WsusHealth.ps1 -Repair -ContentPath $WSUSRoot -SqlInstance .\\SQLEXPRESS"
Write-Host "==============================================================="

Stop-Transcript | Out-Null
