# Coding Conventions

**Analysis Date:** 2026-02-19

## Naming Patterns

**Functions:**
- Use approved PowerShell verbs (Get-, Set-, Start-, Stop-, Test-, Invoke-, Remove-, etc.)
- WSUS-specific functions prefixed with `Wsus`: `Get-WsusDatabaseSize`, `Start-WsusService`, `Test-WsusHealth`
- Follow pattern: `Verb-Wsus{Noun}` or `Verb-{Wsus}{Category}{Noun}`
- Examples from codebase:
  - `Get-WsusDatabaseSize`, `Get-WsusDatabaseStats` (`Modules/WsusDatabase.psm1`)
  - `Test-ServiceRunning`, `Wait-ServiceState` (`Modules/WsusServices.psm1`)
  - `Repair-WsusHealth`, `Get-WsusSSLStatus` (`Modules/WsusHealth.psm1`)
  - `Write-Success`, `Write-Failure`, `Write-Info`, `Write-WsusWarning` (`Modules/WsusUtilities.psm1`)

**Variables:**
- Script-scope variables prefixed with `$script:`: `$script:WsusConfig`, `$script:SqlServerModuleVersion`, `$script:OperationRunning`
- Parameter names use camelCase: `$SqlInstance`, `$DatabaseName`, `$ServiceName`, `$QueryTimeout`
- Internal helper variables lowercase with underscores if needed: `$logFile`, `$baseConfig`
- Constants defined at module/script scope: `$script:WsusConfigPath = "C:\WSUS"`, `$script:WsusSqlCredentialFile = "sql_credential.xml"`

**Parameters:**
- Use named parameters, not positional (enforced by PSScriptAnalyzer rule `PSAvoidUsingPositionalParameters`)
- Use `[switch]` for boolean flags instead of boolean parameters where appropriate
- Validate parameter sets using `[Parameter(ParameterSetName = 'SetName')]`
- Example from `Scripts/Invoke-WsusManagement.ps1`:
  ```powershell
  param(
      [Parameter(ParameterSetName = 'Cleanup')]
      [switch]$Cleanup,

      [Parameter(Mandatory = $true)]
      [string]$BackupPath,

      [ValidateSet('Full', 'Differential')]
      [string]$CopyMode = "Full"
  )
  ```

**Files:**
- Module files: `{FunctionArea}.psm1` (e.g., `WsusDatabase.psm1`, `WsusHealth.psm1`)
- Script files: `Verb-{Description}.ps1` (e.g., `Invoke-WsusManagement.ps1`, `Set-WsusHttps.ps1`)
- Test files: `{ModuleName}.Tests.ps1` (e.g., `WsusDatabase.Tests.ps1`)

## Code Style

**Formatting:**
- Braces on same line: `function Get-Something {`
- New line after opening brace
- No empty line before closing brace
- Consistent indentation (standard PowerShell 4-space)
- Enforced by PSScriptAnalyzer rules `PSPlaceOpenBrace` and `PSPlaceCloseBrace`

**Linting:**
- Tool: PSScriptAnalyzer
- Config file: `.PSScriptAnalyzerSettings.psd1`
- Severity levels: Error and Warning
- Excluded rules:
  - `PSAvoidUsingWriteHost` (color output is appropriate for CLI tools)
  - `PSUseShouldProcessForStateChangingFunctions` (GUI internal functions exempt)
  - `PSUseSingularNouns` (Settings/Utilities naming conflicts with rule)
- Required rules (security + quality):
  - `PSAvoidUsingPlainTextForPassword`, `PSAvoidUsingConvertToSecureStringWithPlainText`
  - `PSAvoidUsingUserNameAndPasswordParams`, `PSAvoidUsingInvokeExpression`
  - `PSAvoidUsingCmdletAliases`, `PSAvoidUsingPositionalParameters`
  - `PSUseDeclaredVarsMoreThanAssignments`, `PSUseApprovedVerbs`

**Comment-Based Help:**
- Required for all exported functions
- Placement: Before function definition
- Block comment format (not inline)
- Include: SYNOPSIS, DESCRIPTION, PARAMETER sections, OUTPUTS, EXAMPLES where applicable
- Example from `Modules/WsusUtilities.psm1`:
  ```powershell
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
  ```

## Import Organization

**Order:**
1. Module-level variables and initialization
2. Required modules (with error checking): `Import-Module`, dependency imports
3. Helper functions
4. Main functions (public, exported)
5. Exports: `Export-ModuleMember -Function @( ... )`

**Module Dependencies:**
- Modules import only what they need (no circular dependencies)
- Check if module already loaded before importing (prevents re-import issues)
- Example from `Modules/WsusHealth.psm1`:
  ```powershell
  $requiredModules = @('WsusUtilities', 'WsusServices', 'WsusFirewall', 'WsusPermissions')
  foreach ($modName in $requiredModules) {
      $modFile = Join-Path $modulePath "$modName.psm1"
      if (Test-Path $modFile) {
          Import-Module $modFile -Force -DisableNameChecking -ErrorAction Stop
      }
  }
  ```

**Path Aliases:**
- No aliases used in scripts (enforced by PSScriptAnalyzer)
- Always use full cmdlet names: `Get-Service`, not `gsv`

## Error Handling

**Strategy:** Defensive with try-catch blocks for operations that can fail, graceful degradation where appropriate

**Patterns:**

1. **Parameter validation with conditions:**
   ```powershell
   if (-not (Test-Path $path)) {
       Write-Warning "Path not found: $path"
       return $false
   }
   ```

2. **Try-catch with error logging:**
   ```powershell
   try {
       $result = Invoke-WsusSqlcmd -Query $query
       return $result
   } catch {
       Write-Warning "Failed to execute query: $($_.Exception.Message)"
       return 0
   }
   ```

3. **Centralized error handling wrapper:**
   - Function `Invoke-WithErrorHandling` in `WsusUtilities.psm1`
   - Executes script block with standardized error handling
   - Supports continue-on-error with default return value
   - Usage:
     ```powershell
     $result = Invoke-WithErrorHandling -ScriptBlock { Get-Service "WSUSService" } `
         -ErrorMessage "Failed to get WSUS service" -ContinueOnError
     ```

4. **Admin privilege checking:**
   - Function `Test-AdminPrivileges` in `WsusUtilities.psm1`
   - Many scripts require `#Requires -RunAsAdministrator`
   - Called at script entry point: `Test-AdminPrivileges -ExitOnFail $true`
   - Example from `Scripts/Invoke-WsusManagement.ps1`:
     ```powershell
     #Requires -RunAsAdministrator
     ```

5. **SQL-specific handling:**
   - Wrapper function `Invoke-WsusSqlcmd` handles TrustServerCertificate compatibility
   - Version detection at module load: `$script:SqlServerSupportsTrustCert = ($sqlMod.Version -ge [Version]"21.1.0")`
   - Automatically includes parameter only for SqlServer module v21.1+
   - Always use single-quote here-strings (`@'...'@`) with SQLCMD variables to prevent PowerShell evaluation
   - Example from `Modules/WsusUtilities.psm1`:
     ```powershell
     $query = @'
     DECLARE @UpdateGuid uniqueidentifier = '$(UpdateId)'
     SELECT * FROM tbUpdate WHERE UpdateID = @UpdateGuid
     '@
     Invoke-WsusSqlcmd -Query $query -Variable "UpdateId=$guid"
     ```

6. **Avoid empty catch blocks:**
   - PSScriptAnalyzer rule `PSAvoidUsingEmptyCatchBlock` enforced
   - If ignoring errors intentionally: `catch { # Expected error - suppressed }`
   - Example from `WsusUtilities.psm1`:
     ```powershell
     try {
         Stop-Transcript -ErrorAction Stop | Out-Null
     } catch {
         # Ignore error if transcript wasn't running
     }
     ```

## Logging

**Framework:** Built-in functions, not external logging library

**Color-coded output functions in `WsusUtilities.psm1`:**
- `Write-Success` - Green text (completion/success)
- `Write-Failure` - Red text (errors)
- `Write-Info` - Cyan text (informational)
- `Write-WsusWarning` - Yellow text (warnings; renamed to avoid conflict with built-in `Write-Warning`)
- `Write-ColorOutput` - Generic color output helper

**File-based logging functions:**
- `Start-WsusLogging -ScriptName "Name" [-SharedLog] [-LogDirectory "path"] [-UseTimestamp $bool]`
  - Creates timestamped log file or shared daily log
  - Default location: `C:\WSUS\Logs\{ScriptName}_{timestamp}.log`
  - Shared mode: `C:\WSUS\Logs\WsusOperations_yyyy-MM-dd.log`
  - Returns path to log file
- `Stop-WsusLogging` - Stops transcript
- `Write-Log -Message "text"` - Writes timestamped message: `yyyy-MM-dd HH:mm:ss - message`

**Error logging functions:**
- `Write-LogError -Message "text" [-Exception $ex] [-Throw]` - Logs error to console and file, optionally throws
- `Write-LogWarning -Message "text"` - Logs warning to console and file

**Logging patterns:**
1. Start logging at script entry: `Start-WsusLogging -ScriptName "OperationName"`
2. All output automatically captured to transcript
3. Manual logging for key milestones: `Write-Log "Starting operation X"`
4. Stop logging at exit: `Stop-WsusLogging`
5. Example from `Scripts/Invoke-WsusManagement.ps1`:
   ```powershell
   $sessionMarker = @"
   ================================================================================
   SESSION START: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
   ================================================================================
   "@
   Add-Content -Path $script:LogFilePath -Value $sessionMarker -ErrorAction SilentlyContinue
   ```

## Function Design

**Size guidelines:**
- Single responsibility: each function does one thing
- Typical length: 20-100 lines for most functions
- Longer functions (200+ lines) must be documented with internal comments

**Parameters:**
- Use parameter sets for mutually exclusive parameter combinations
- Always use `[Parameter(Mandatory = $true)]` for required parameters
- Always use `[ValidateSet(...)]` for restricted values
- Example from `Modules/WsusConfig.psm1`:
  ```powershell
  param(
      [Parameter(Mandatory)]
      [ValidateSet('Small', 'Medium', 'Large', 'ExtraLarge', 'Schedule')]
      [string]$Type
  )
  ```

**Return values:**
- Suppress unintended output with `$null =` or `| Out-Null`
- For status operations: return boolean or status object
- For queries: return data object or array
- For void operations: suppress all output

**Hashtables for configuration:**
- Nested hashtables for related settings: `$config.Services.SqlExpress`, `$config.Timeouts.SqlQueryDefault`
- Configuration accessed via getter functions: `Get-WsusConfig -Key "SqlInstance"`
- Central config module: `Modules/WsusConfig.psm1` - single source of truth for all configurable values

## Module Design

**Exports:**
- Explicit function export list at end of module
- Only export public functions
- Helper functions remain internal (not exported)
- Pattern from all modules:
  ```powershell
  Export-ModuleMember -Function @(
      'Function1',
      'Function2',
      'Function3'
  )
  ```

**Module scope variables:**
- Use `$script:` prefix for module-level state
- Document purpose and usage in header comment
- Performance optimization caching example from `WsusUtilities.psm1`:
  ```powershell
  # Cache SqlServer module version at load time
  $script:SqlServerModuleVersion = $null
  $script:SqlServerSupportsTrustCert = $false

  $sqlMod = Get-Module SqlServer -ListAvailable -ErrorAction SilentlyContinue
  if ($sqlMod) {
      $script:SqlServerModuleVersion = $sqlMod.Version
      $script:SqlServerSupportsTrustCert = ($sqlMod.Version -ge [Version]"21.1.0")
  }
  ```

**Barrel files:**
- Not used in this codebase
- Each module is focused and self-contained

## Comments

**When to comment:**
- Complex algorithms or non-obvious logic
- Important performance optimizations
- Known limitations or workarounds
- Business logic that requires explanation
- Do NOT comment obvious code: `$x = 5  # Set x to 5` is wrong

**Comment style:**
- Single-line comments: `# Comment text`
- Multi-line comments: Use multiple `#` lines, not `<# #>`
- Section dividers for major code blocks:
  ```powershell
  # ===========================
  # DATABASE SIZE FUNCTIONS
  # ===========================
  ```

**JSDoc/TSDoc (not used):**
- Comment-based help used instead (in function headers)
- No inline JSDoc style comments

---

*Convention analysis: 2026-02-19*
