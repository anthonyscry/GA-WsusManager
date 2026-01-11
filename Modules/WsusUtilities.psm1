<#
===============================================================================
Module: WsusUtilities.psm1
Author: Tony Tran, ISSO, GA-ASI
Version: 1.1.0
Date: 2026-01-10
===============================================================================

.SYNOPSIS
    Common utility functions for WSUS scripts

.DESCRIPTION
    Provides shared functionality including:
    - Color output functions
    - Logging functions (Start-WsusLogging, Stop-WsusLogging, Write-Log)
    - Admin privilege checks
    - SQL command wrapper (Invoke-WsusSqlcmd)
    - Common helper functions

.NOTES
    Required functions exported: Start-WsusLogging, Stop-WsusLogging, Write-Log, Invoke-WsusSqlcmd
#>

# Module version for compatibility checking
$script:WsusUtilitiesVersion = '1.1.0'

# ===========================
# COLOR OUTPUT FUNCTIONS
# ===========================

function Write-ColorOutput {
    <#
    .SYNOPSIS
        Writes output in a specific color
    .PARAMETER ForegroundColor
        The color to use for the text
    .PARAMETER Message
        The message to write
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ConsoleColor]$ForegroundColor,

        [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
        [string[]]$Message
    )

    $fc = $host.UI.RawUI.ForegroundColor
    $host.UI.RawUI.ForegroundColor = $ForegroundColor

    if ($Message) {
        Write-Host ($Message -join ' ')
    }

    $host.UI.RawUI.ForegroundColor = $fc
}

function Write-Success {
    <#
    .SYNOPSIS
        Writes success message in green
    .PARAMETER Message
        The message to write
    #>
    param(
        [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
        [string[]]$Message
    )
    Write-ColorOutput -ForegroundColor Green -Message $Message
}

function Write-Failure {
    <#
    .SYNOPSIS
        Writes failure message in red
    .PARAMETER Message
        The message to write
    #>
    param(
        [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
        [string[]]$Message
    )
    Write-ColorOutput -ForegroundColor Red -Message $Message
}

function Write-WsusWarning {
    <#
    .SYNOPSIS
        Writes warning message in yellow (renamed to avoid conflict with built-in Write-Warning)
    .PARAMETER Message
        The message to write
    #>
    param(
        [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
        [string[]]$Message
    )
    Write-ColorOutput -ForegroundColor Yellow -Message $Message
}

function Write-Info {
    <#
    .SYNOPSIS
        Writes info message in cyan
    .PARAMETER Message
        The message to write
    #>
    param(
        [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
        [string[]]$Message
    )
    Write-ColorOutput -ForegroundColor Cyan -Message $Message
}

# ===========================
# LOGGING FUNCTIONS
# ===========================

function Write-Log {
    <#
    .SYNOPSIS
        Writes timestamped log message

    .PARAMETER Message
        The message to log
    #>
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Message
    )

    Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message"
}

function Start-WsusLogging {
    <#
    .SYNOPSIS
        Starts transcript logging with standardized naming

    .PARAMETER ScriptName
        Name of the script (used in log filename)

    .PARAMETER LogDirectory
        Directory to store logs (default: C:\WSUS\Logs)

    .PARAMETER UseTimestamp
        Include timestamp in filename (default: true)

    .EXAMPLE
        Start-WsusLogging -ScriptName "MyScript"
        # Creates C:\WSUS\Logs\MyScript_20250108_1430.log
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptName,

        [string]$LogDirectory = "C:\WSUS\Logs",

        [bool]$UseTimestamp = $true
    )

    # Create log directory if it doesn't exist
    New-Item -Path $LogDirectory -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

    # Generate log filename
    if ($UseTimestamp) {
        $logFile = Join-Path $LogDirectory "${ScriptName}_$(Get-Date -Format 'yyyyMMdd_HHmm').log"
    } else {
        $logFile = Join-Path $LogDirectory "${ScriptName}.log"
    }

    # Start transcript
    Start-Transcript -Path $logFile -Append -ErrorAction SilentlyContinue | Out-Null

    return $logFile
}

function Stop-WsusLogging {
    <#
    .SYNOPSIS
        Stops transcript logging
    #>
    try {
        Stop-Transcript -ErrorAction Stop | Out-Null
    } catch {
        # Ignore error if transcript wasn't running
    }
}

# ===========================
# ADMIN CHECK FUNCTIONS
# ===========================

function Test-AdminPrivileges {
    <#
    .SYNOPSIS
        Checks if the current user has administrator privileges

    .PARAMETER ExitOnFail
        If true, exits the script if not running as admin

    .OUTPUTS
        Boolean indicating if user is admin

    .EXAMPLE
        Test-AdminPrivileges -ExitOnFail $true
    #>
    param(
        [bool]$ExitOnFail = $false
    )

    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        if ($ExitOnFail) {
            Write-Failure "ERROR: This script must be run as Administrator!"
            exit 1
        }
        return $false
    }

    return $true
}

# ===========================
# ERROR HANDLING FUNCTIONS
# ===========================

function Write-LogError {
    <#
    .SYNOPSIS
        Writes an error message to both console and log

    .PARAMETER Message
        The error message to write

    .PARAMETER Exception
        Optional exception object to include details from

    .PARAMETER Throw
        If true, throws the error after logging
    #>
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Message,

        [System.Exception]$Exception,

        [switch]$Throw
    )

    $fullMessage = if ($Exception) {
        "$Message - $($Exception.Message)"
    } else {
        $Message
    }

    Write-Log "ERROR: $fullMessage"
    Write-Failure "ERROR: $fullMessage"

    if ($Throw) {
        throw $fullMessage
    }
}

function Write-LogWarning {
    <#
    .SYNOPSIS
        Writes a warning message to both console and log

    .PARAMETER Message
        The warning message to write
    #>
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Message
    )

    Write-Log "WARNING: $Message"
    Write-WsusWarning "WARNING: $Message"
}

function Invoke-WithErrorHandling {
    <#
    .SYNOPSIS
        Executes a script block with standardized error handling

    .PARAMETER ScriptBlock
        The code to execute

    .PARAMETER ErrorMessage
        Message to display if an error occurs

    .PARAMETER ContinueOnError
        If true, continues execution after an error (default: false)

    .PARAMETER ReturnDefault
        Value to return if an error occurs (when ContinueOnError is true)

    .EXAMPLE
        $result = Invoke-WithErrorHandling -ScriptBlock { Get-Service "WSUSService" } -ErrorMessage "Failed to get WSUS service"
    #>
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,

        [string]$ErrorMessage = "An error occurred",

        [switch]$ContinueOnError,

        $ReturnDefault = $null
    )

    try {
        return & $ScriptBlock
    } catch {
        if ($ContinueOnError) {
            $null = Write-LogWarning "$ErrorMessage : $($_.Exception.Message)"
            return $ReturnDefault
        } else {
            Write-LogError $ErrorMessage -Exception $_.Exception -Throw
        }
    }
}

# ===========================
# SQL HELPER FUNCTIONS
# ===========================

function Invoke-SqlScalar {
    <#
    .SYNOPSIS
        Executes a SQL query and returns a scalar result

    .PARAMETER Instance
        SQL Server instance name

    .PARAMETER Query
        SQL query to execute

    .PARAMETER Database
        Database name (default: SUSDB)

    .EXAMPLE
        Invoke-SqlScalar -Instance ".\SQLEXPRESS" -Query "SELECT COUNT(*) FROM tbUpdate"
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Instance,

        [Parameter(Mandatory = $true)]
        [string]$Query,

        [string]$Database = "SUSDB"
    )

    $result = sqlcmd -S $Instance -E -d $Database -b -h -1 -W -Q "SET NOCOUNT ON; $Query" 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw "SQL query failed: $result"
    }

    return $result.Trim()
}

function Invoke-WsusSqlcmd {
    <#
    .SYNOPSIS
        Wrapper for Invoke-Sqlcmd that handles TrustServerCertificate compatibility

    .DESCRIPTION
        Executes Invoke-Sqlcmd with automatic handling of the TrustServerCertificate
        parameter based on SqlServer module version. SqlServer module v21.1+ requires
        this parameter for encrypted connections.

    .PARAMETER ServerInstance
        SQL Server instance name (default: .\SQLEXPRESS)

    .PARAMETER Database
        Database name (default: SUSDB)

    .PARAMETER Query
        SQL query to execute

    .PARAMETER QueryTimeout
        Query timeout in seconds (default: 30, use 0 for unlimited)

    .PARAMETER Credential
        Optional PSCredential for SQL authentication

    .PARAMETER Variable
        Optional variable substitution (for parameterized queries)

    .EXAMPLE
        Invoke-WsusSqlcmd -Query "SELECT COUNT(*) FROM tbUpdate"

    .EXAMPLE
        Invoke-WsusSqlcmd -Query "BACKUP DATABASE SUSDB TO DISK=N'C:\WSUS\backup.bak'" -QueryTimeout 0
    #>
    [CmdletBinding()]
    param(
        [string]$ServerInstance = ".\SQLEXPRESS",

        [string]$Database = "SUSDB",

        [Parameter(Mandatory = $true)]
        [string]$Query,

        [int]$QueryTimeout = 30,

        [System.Management.Automation.PSCredential]$Credential,

        [string]$Variable
    )

    # Build base parameters using splatting
    $sqlParams = @{
        ServerInstance = $ServerInstance
        Database = $Database
        Query = $Query
        QueryTimeout = $QueryTimeout
        ErrorAction = 'Stop'
    }

    # Add optional parameters
    if ($Credential) {
        $sqlParams.Credential = $Credential
    }

    if ($Variable) {
        $sqlParams.Variable = $Variable
    }

    # Check if SqlServer module supports TrustServerCertificate (v21.1+)
    # This parameter is required for newer module versions to avoid certificate trust errors
    $sqlModule = Get-Module SqlServer -ListAvailable -ErrorAction SilentlyContinue |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if ($sqlModule) {
        # TrustServerCertificate was added in SqlServer module v21.1
        if ($sqlModule.Version -ge [Version]"21.1.0") {
            $sqlParams.TrustServerCertificate = $true
        }
    }

    # Execute the query
    return Invoke-Sqlcmd @sqlParams
}

# ===========================
# PATH HELPER FUNCTIONS
# ===========================

function Get-WsusContentPath {
    <#
    .SYNOPSIS
        Gets the WSUS content path from registry

    .OUTPUTS
        String containing the WSUS content path, or $null if not found
    #>
    try {
        $regPath = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Update Services\Server\Setup" -Name ContentDir -ErrorAction Stop
        return $regPath.ContentDir
    } catch {
        return $null
    }
}

function Test-WsusPath {
    <#
    .SYNOPSIS
        Validates that a path exists and creates it if needed

    .PARAMETER Path
        Path to validate

    .PARAMETER Create
        If true, creates the path if it doesn't exist

    .OUTPUTS
        Boolean indicating if path exists
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [bool]$Create = $false
    )

    if (Test-Path $Path) {
        return $true
    }

    if ($Create) {
        try {
            New-Item -Path $Path -ItemType Directory -Force | Out-Null
            return $true
        } catch {
            return $false
        }
    }

    return $false
}

# ===========================
# SQL CREDENTIAL FUNCTIONS
# ===========================

# Module-level constants for credential storage
$script:WsusConfigPath = "C:\WSUS\Config"
$script:WsusSqlCredentialFile = "sql_credential.xml"

function Get-WsusSqlCredentialPath {
    <#
    .SYNOPSIS
        Returns the full path to the SQL credential file
    #>
    return Join-Path $script:WsusConfigPath $script:WsusSqlCredentialFile
}

function Set-WsusSqlCredential {
    <#
    .SYNOPSIS
        Stores SQL Server credentials for unattended maintenance tasks

    .DESCRIPTION
        Stores encrypted credentials that can be used by scheduled maintenance tasks.
        The credentials are encrypted using Windows DPAPI and can only be decrypted
        by the same user account on the same machine.

    .PARAMETER Username
        SQL Server username (default: dod_admin)

    .PARAMETER Credential
        PSCredential object (will prompt if not provided)

    .PARAMETER Force
        Overwrite existing credentials without prompting

    .EXAMPLE
        Set-WsusSqlCredential
        # Prompts for credentials and stores them

    .EXAMPLE
        Set-WsusSqlCredential -Username "sa"
        # Prompts for password for specified username

    .OUTPUTS
        Boolean indicating success or failure
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Username = "dod_admin",

        [Parameter(Position = 1)]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential,

        [switch]$Force
    )

    $credFile = Get-WsusSqlCredentialPath

    # Check if credential already exists
    if ((Test-Path $credFile) -and -not $Force) {
        $existing = Get-WsusSqlCredential
        if ($existing) {
            Write-Host "Existing credential found for user: $($existing.UserName)" -ForegroundColor Yellow
            $confirm = Read-Host "Overwrite? (Y/N)"
            if ($confirm -notmatch '^[Yy]') {
                Write-Host "Cancelled" -ForegroundColor Yellow
                return $false
            }
        }
    }

    # Create config directory if needed
    if (-not (Test-Path $script:WsusConfigPath)) {
        try {
            New-Item -Path $script:WsusConfigPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
        } catch {
            Write-Warning "Failed to create config directory: $($_.Exception.Message)"
            return $false
        }
    }

    # Get credential if not provided
    if (-not $Credential) {
        Write-Host "Enter SQL Server credentials for unattended maintenance:" -ForegroundColor Yellow
        $Credential = Get-Credential -Message "SQL Server credentials" -UserName $Username
    }

    # Validate credential
    if (-not $Credential) {
        Write-Warning "No credentials provided"
        return $false
    }

    if ([string]::IsNullOrWhiteSpace($Credential.UserName)) {
        Write-Warning "Username cannot be empty"
        return $false
    }

    if ($Credential.Password.Length -eq 0) {
        Write-Warning "Password cannot be empty"
        return $false
    }

    try {
        # Export credential (encrypted with DPAPI - user/machine specific)
        # IMPORTANT: DPAPI encryption is per-user. Credentials stored by one user
        # cannot be decrypted by another user account, including SYSTEM.
        # If you need to use credentials in scheduled tasks running as SYSTEM,
        # store them while running as SYSTEM, or use Windows Credential Manager instead.
        $Credential | Export-Clixml -Path $credFile -Force -ErrorAction Stop

        # Restrict file permissions
        $acl = Get-Acl $credFile
        $acl.SetAccessRuleProtection($true, $false)
        $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "BUILTIN\Administrators", "FullControl", "Allow")
        $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "NT AUTHORITY\SYSTEM", "FullControl", "Allow")
        $acl.AddAccessRule($adminRule)
        $acl.AddAccessRule($systemRule)
        Set-Acl -Path $credFile -AclObject $acl -ErrorAction Stop

        Write-Host "SQL credentials stored at: $credFile" -ForegroundColor Green
        Write-Host "Note: Credentials are encrypted with DPAPI and can only be decrypted by the same user account on this machine." -ForegroundColor Cyan
        Write-Host "      Scheduled tasks running as SYSTEM will not be able to use these credentials." -ForegroundColor Yellow
        return $true
    } catch {
        Write-Warning "Failed to store credentials: $($_.Exception.Message)"
        # Clean up partial file if it exists
        if (Test-Path $credFile) {
            Remove-Item -Path $credFile -Force -ErrorAction SilentlyContinue
        }
        return $false
    }
}

function Get-WsusSqlCredential {
    <#
    .SYNOPSIS
        Retrieves stored SQL Server credentials

    .PARAMETER Quiet
        Suppress warning messages if credential not found

    .OUTPUTS
        PSCredential object or $null if not found
    #>
    [CmdletBinding()]
    param(
        [switch]$Quiet
    )

    $credFile = Get-WsusSqlCredentialPath

    if (-not (Test-Path $credFile)) {
        if (-not $Quiet) {
            Write-Verbose "No stored credential file found at: $credFile"
        }
        return $null
    }

    try {
        $credential = Import-Clixml -Path $credFile -ErrorAction Stop

        # Validate the imported credential
        if (-not $credential -or -not ($credential -is [System.Management.Automation.PSCredential])) {
            Write-Warning "Stored credential file is corrupted or invalid"
            return $null
        }

        return $credential
    } catch {
        Write-Warning "Failed to load stored credentials: $($_.Exception.Message)"
        return $null
    }
}

function Test-WsusSqlCredential {
    <#
    .SYNOPSIS
        Tests if stored SQL credentials can connect to SUSDB

    .PARAMETER Credential
        Credential to test (uses stored credential if not specified)

    .PARAMETER SqlInstance
        SQL Server instance (default: .\SQLEXPRESS)

    .OUTPUTS
        Boolean indicating if connection succeeded
    #>
    [CmdletBinding()]
    param(
        [System.Management.Automation.PSCredential]$Credential,

        [string]$SqlInstance = ".\SQLEXPRESS"
    )

    # Get stored credential if not provided
    if (-not $Credential) {
        $Credential = Get-WsusSqlCredential
        if (-not $Credential) {
            Write-Warning "No credential provided and no stored credential found"
            return $false
        }
    }

    Write-Host "Testing SQL connection as $($Credential.UserName)..." -ForegroundColor Cyan

    try {
        # Test connection using Invoke-WsusSqlcmd wrapper
        $testQuery = "SELECT 1 AS TestResult"
        $result = Invoke-WsusSqlcmd -ServerInstance $SqlInstance -Database "SUSDB" `
            -Query $testQuery -Credential $Credential -QueryTimeout 10

        if ($result.TestResult -eq 1) {
            Write-Host "SQL connection successful" -ForegroundColor Green
            return $true
        } else {
            Write-Warning "Unexpected result from test query"
            return $false
        }
    } catch {
        Write-Warning "SQL connection failed: $($_.Exception.Message)"
        return $false
    }
}

function Remove-WsusSqlCredential {
    <#
    .SYNOPSIS
        Removes stored SQL Server credentials

    .PARAMETER Force
        Remove without confirmation

    .OUTPUTS
        Boolean indicating success
    #>
    [CmdletBinding()]
    param(
        [switch]$Force
    )

    $credFile = Get-WsusSqlCredentialPath

    if (-not (Test-Path $credFile)) {
        Write-Host "No stored credentials found" -ForegroundColor Yellow
        return $false
    }

    if (-not $Force) {
        $existing = Get-WsusSqlCredential -Quiet
        $userName = if ($existing) { $existing.UserName } else { "unknown" }
        $confirm = Read-Host "Remove stored credentials for '$userName'? (Y/N)"
        if ($confirm -notmatch '^[Yy]') {
            Write-Host "Cancelled" -ForegroundColor Yellow
            return $false
        }
    }

    try {
        Remove-Item -Path $credFile -Force -ErrorAction Stop
        Write-Host "SQL credentials removed" -ForegroundColor Green
        return $true
    } catch {
        Write-Warning "Failed to remove credentials: $($_.Exception.Message)"
        return $false
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Write-ColorOutput',
    'Write-Success',
    'Write-Failure',
    'Write-WsusWarning',
    'Write-Info',
    'Write-Log',
    'Write-LogError',
    'Write-LogWarning',
    'Invoke-WithErrorHandling',
    'Start-WsusLogging',
    'Stop-WsusLogging',
    'Test-AdminPrivileges',
    'Invoke-SqlScalar',
    'Invoke-WsusSqlcmd',
    'Get-WsusContentPath',
    'Test-WsusPath',
    'Get-WsusSqlCredentialPath',
    'Set-WsusSqlCredential',
    'Get-WsusSqlCredential',
    'Test-WsusSqlCredential',
    'Remove-WsusSqlCredential'
)
