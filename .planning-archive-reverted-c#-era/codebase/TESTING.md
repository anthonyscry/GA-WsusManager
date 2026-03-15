# Testing Patterns

**Analysis Date:** 2026-02-19

## Test Framework

**Runner:**
- Pester v5.x (PowerShell unit testing framework)
- Config: No separate config file (uses Pester defaults)
- Invoked via: `Invoke-Pester -Path .\Tests`

**Assertion Library:**
- Pester built-in assertions: `Should -Be`, `Should -BeNullOrEmpty`, `Should -Throw`, `Should -Match`, etc.

**Run Commands:**
```bash
# Run all tests
Invoke-Pester -Path .\Tests -Output Detailed

# Run specific test file
Invoke-Pester -Path .\Tests\WsusDatabase.Tests.ps1

# Run tests with code coverage
Invoke-Pester -Path .\Tests -CodeCoverage .\Modules\*.psm1

# Run only via build script (recommended)
.\build.ps1 -TestOnly

# Full build with tests
.\build.ps1
```

## Test File Organization

**Location:**
- Co-located with modules: `Tests/` folder parallel to `Modules/` and `Scripts/`
- Pattern: Test files mirror module names
  - Module: `Modules/WsusDatabase.psm1` → Test: `Tests/WsusDatabase.Tests.ps1`
  - Module: `Modules/WsusHealth.psm1` → Test: `Tests/WsusHealth.Tests.ps1`

**Naming:**
- Format: `{ModuleName}.Tests.ps1`
- All test files use `.Tests.ps1` suffix (consistency)
- Examples: `WsusUtilities.Tests.ps1`, `WsusServices.Tests.ps1`, `WsusDatabase.Tests.ps1`

**Structure:**
```
Tests/
├── TestSetup.ps1                    # Shared setup script (module pre-loading)
├── WsusUtilities.Tests.ps1          # Tests for WsusUtilities module
├── WsusDatabase.Tests.ps1           # Tests for WsusDatabase module
├── WsusHealth.Tests.ps1             # Tests for WsusHealth module
├── WsusServices.Tests.ps1           # Tests for WsusServices module
├── WsusConfig.Tests.ps1             # Tests for WsusConfig module
├── WsusAutoDetection.Tests.ps1      # Tests for WsusAutoDetection module
├── CliIntegration.Tests.ps1         # CLI script parameter validation
├── Integration.Tests.ps1            # End-to-end integration tests
├── ExeValidation.Tests.ps1          # EXE validation (runs after build)
├── FlaUI.Tests.ps1                  # GUI automation tests (optional)
└── Invoke-Tests.ps1                 # Main test runner script
```

## Test Structure

**Suite Organization:**
```powershell
BeforeAll {
    # Import the module under test
    $ModulePath = Join-Path $PSScriptRoot "..\Modules\WsusDatabase.psm1"
    Import-Module $ModulePath -Force -DisableNameChecking
}

AfterAll {
    # Clean up
    Remove-Module WsusDatabase -ErrorAction SilentlyContinue
}

Describe "WsusDatabase Module" {
    Context "Module Loading" {
        It "Should import the module successfully" {
            Get-Module WsusDatabase | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "Get-WsusDatabaseSize" {
    Context "With mocked SQL query" {
        BeforeAll {
            Mock Invoke-WsusSqlcmd {
                [PSCustomObject]@{ SizeGB = 5.25 }
            } -ModuleName WsusDatabase
        }

        It "Should return database size in GB" {
            $result = Get-WsusDatabaseSize
            $result | Should -Be 5.25
        }
    }
}
```

**Patterns:**

1. **Setup (BeforeAll):**
   - Import module under test
   - Set up shared test data
   - Initialize mocks that apply to entire context
   - Example from `Tests/WsusUtilities.Tests.ps1`:
     ```powershell
     BeforeAll {
         $ModulePath = Join-Path $PSScriptRoot "..\Modules\WsusUtilities.psm1"
         Import-Module $ModulePath -Force -DisableNameChecking
     }
     ```

2. **Teardown (AfterAll/AfterEach):**
   - Remove module to avoid state pollution
   - Clean up temporary test files/folders
   - Reset any state changes
   - Example from `Tests/WsusUtilities.Tests.ps1`:
     ```powershell
     AfterEach {
         Stop-WsusLogging
         if (Test-Path $TestLogDir) {
             Remove-Item $TestLogDir -Recurse -Force -ErrorAction SilentlyContinue
         }
     }
     ```

3. **Assertion patterns:**
   - Type checking: `$result | Should -BeOfType [bool]`
   - Value checking: `$result | Should -Be 5.25`
   - Null checks: `$result | Should -Not -BeNullOrEmpty`
   - String matching: `$output | Should -Match "pattern"`
   - Exception testing: `{ operation } | Should -Throw`

## Mocking

**Framework:** Pester built-in `Mock` and `Assert-MockCalled` commands

**Patterns:**

1. **Basic mocking:**
   ```powershell
   Mock Get-Service {
       [PSCustomObject]@{
           Name = "MockService"
           Status = "Running"
       }
   } -ModuleName WsusServices
   ```

2. **Multiple mock returns (per test):**
   ```powershell
   Context "With mocked SQL error" {
       BeforeAll {
           Mock Invoke-WsusSqlcmd {
               throw "SQL connection failed"
           } -ModuleName WsusDatabase
       }

       It "Should return 0 on error" {
           $result = Get-WsusDatabaseSize
           $result | Should -Be 0
       }
   }
   ```

3. **Mocking with parameters:**
   ```powershell
   Mock Invoke-WsusSqlcmd {
       if ($Query -match "SELECT COUNT") {
           return [PSCustomObject]@{ Count = 100 }
       } else {
           return [PSCustomObject]@{ Result = "OK" }
       }
   } -ModuleName WsusDatabase
   ```

4. **Verifying mock calls:**
   - Not commonly used in these tests
   - Pattern (if needed): `Assert-MockCalled Get-Service -Times 1`

**What to mock:**
- External dependencies: `Get-Service`, `Invoke-WsusSqlcmd`, `Get-Website`
- Network operations: `Test-Connection`, HTTP calls
- File system when testing logic not I/O: `Test-Path`, `Get-Content`
- Complex operations: Database queries, service status checks

**What NOT to mock:**
- Built-in PowerShell functions like `Write-Output`, `Write-Host` (unless testing output specifically)
- Functions you're testing (test the real implementation)
- Pure utility functions that don't have side effects

## Fixtures and Factories

**Test data:**
```powershell
BeforeAll {
    $TestLogDir = Join-Path $env:TEMP "WsusTestLogs_$(Get-Random)"
}

AfterAll {
    if (Test-Path $TestLogDir) {
        Remove-Item $TestLogDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
```

**Location:**
- Created in BeforeAll/BeforeEach blocks within test file
- Temporary paths use: `$env:TEMP` + unique folder names
- Example from `Tests/WsusUtilities.Tests.ps1`:
  ```powershell
  BeforeAll {
      $TestPath = Join-Path $env:TEMP "WsusTestPath_$(Get-Random)"
  }
  ```

**Shared setup:**
- `Tests/TestSetup.ps1` pre-loads all modules to improve test performance
- Reduces test suite time by 20-30 seconds (module loading only once)
- Provides helper functions and test configuration:
  ```powershell
  $script:TestConfig = @{
      DefaultTimeout = 30
      ServiceStartTimeout = 5
      AppStartTimeout = 10
      SkipServiceTests = -not (Get-Service -Name 'W3SVC' -ErrorAction SilentlyContinue)
      SkipFlaUITests = -not (Test-Path "C:\projects\FlaUI-TestHarness\FlaUITestHarness.psm1")
  }
  ```

## Coverage

**Requirements:** No formal coverage requirement enforced

**View coverage:**
```powershell
Invoke-Pester -Path .\Tests -CodeCoverage .\Modules\*.psm1 -Output Detailed
```

**Current coverage:**
- 14 test files with ~4,000 lines of test code
- Tests for all 11 core modules in `Modules/`
- Tests for CLI scripts and integration scenarios
- Focus on unit tests with real service tests where applicable

## Test Types

**Unit Tests:**
- Scope: Single function/feature
- Approach: Mock external dependencies, test logic in isolation
- Examples: `WsusDatabase.Tests.ps1`, `WsusUtilities.Tests.ps1`
- Each test validates one aspect of a function
- Pattern:
  ```powershell
  Describe "Get-WsusDatabaseSize" {
      It "Should return database size in GB" { ... }
      It "Should accept SqlInstance parameter" { ... }
      It "Should return 0 on error" { ... }
  }
  ```

**Integration Tests:**
- File: `Tests/Integration.Tests.ps1`
- Scope: Multiple modules working together
- Approach: Minimal mocking, test realistic workflows
- Examples: Module dependency loading, cross-module function calls
- Pattern:
  ```powershell
  Context "WsusHealth with dependent modules" {
      It "Should import all dependent modules" { ... }
      It "Should run diagnostics without error" { ... }
  }
  ```

**CLI Integration Tests:**
- File: `Tests/CliIntegration.Tests.ps1`
- Scope: Command-line script parameters and help documentation
- Approach: Validate parameter sets, help presence, configuration
- Validates: `Invoke-WsusManagement.ps1`, `Invoke-WsusMonthlyMaintenance.ps1`, `Install-WsusWithSqlExpress.ps1`
- Example from file:
  ```powershell
  Describe "Invoke-WsusManagement Parameters" {
      It "Should have -Health parameter" { ... }
      It "Should have -Repair parameter" { ... }
      It "Should accept parameter combinations" { ... }
  }
  ```

**EXE Validation Tests:**
- File: `Tests/ExeValidation.Tests.ps1`
- Scope: Compiled executable validation
- Approach: Check PE header, version info, architecture
- Skipped when exe doesn't exist (using `BeforeDiscovery` for proper Pester 5 behavior)
- Important: Run AFTER build, not before

**GUI Automation Tests (Optional):**
- File: `Tests/FlaUI.Tests.ps1`
- Scope: GUI application automation
- Tool: FlaUI library for UI automation
- Skipped if FlaUI test harness not available
- Tests: Button clicks, dialog interactions, log panel updates

## Common Patterns

**Async testing:**
```powershell
# Not commonly used - PowerShell tests are synchronous
# When needed, use Start-Sleep to wait for async operations
It "Should complete operation within timeout" {
    $result = Get-SomeAsyncValue
    $timeout = 0
    while (-not $result -and $timeout -lt 5) {
        Start-Sleep -Milliseconds 100
        $timeout += 0.1
    }
    $result | Should -Not -BeNullOrEmpty
}
```

**Error testing:**
```powershell
Context "With error condition" {
    BeforeAll {
        Mock Invoke-WsusSqlcmd {
            throw "SQL connection failed"
        } -ModuleName WsusDatabase
    }

    It "Should handle error gracefully" {
        $result = Get-WsusDatabaseSize
        $result | Should -Be 0
    }

    It "Should write warning" {
        { Get-WsusDatabaseSize -WarningAction Continue 3>&1 } | Should -Not -BeNullOrEmpty
    }
}
```

**Real service tests:**
```powershell
Context "With real services" {
    It "Should return true for existing service" {
        $result = Test-ServiceExists -ServiceName "Spooler"
        $result | Should -Be $true
    }

    It "Should return false for non-existent service" {
        $result = Test-ServiceExists -ServiceName "NonExistentService12345"
        $result | Should -Be $false
    }
}
```

**Module dependency validation:**
```powershell
BeforeAll {
    # Import dependent modules first
    $ModulesPath = Join-Path $PSScriptRoot "..\Modules"
    Import-Module (Join-Path $ModulesPath "WsusUtilities.psm1") -Force -DisableNameChecking
    Import-Module (Join-Path $ModulesPath "WsusServices.psm1") -Force -DisableNameChecking
    Import-Module (Join-Path $ModulesPath "WsusFirewall.psm1") -Force -DisableNameChecking

    # Then import module under test
    $ModulePath = Join-Path $ModulesPath "WsusHealth.psm1"
    Import-Module $ModulePath -Force -DisableNameChecking
}
```

**Skipping tests based on conditions:**
```powershell
# Using BeforeDiscovery for Pester 5 compatibility
BeforeDiscovery {
    $script:ExeExists = Test-Path ".\dist\WsusManager.exe"
}

Context "EXE Tests" -Skip:(-not $script:ExeExists) {
    It "EXE should exist and be valid" { ... }
}
```

## Build Integration

**Build process steps (from `build.ps1`):**
1. Run Pester unit tests: `Invoke-Pester -Path .\Tests` (excludes ExeValidation.Tests.ps1)
2. Run PSScriptAnalyzer code review
3. Block build if errors found, warn but continue if only warnings
4. Compile WsusManagementGui.ps1 to exe using PS2EXE
5. Run ExeValidation tests (now that exe exists)
6. Create distribution zip with Scripts/, Modules/, DomainController/

**Test configuration (`TestSetup.ps1`):**
- Skip service tests if W3SVC service doesn't exist: `SkipServiceTests = -not (Get-Service -Name 'W3SVC' -ErrorAction SilentlyContinue)`
- Skip FlaUI tests if test harness not available: `SkipFlaUITests = -not (Test-Path "C:\projects\FlaUI-TestHarness\FlaUITestHarness.psm1")`
- Skip interactive tests: `SkipInteractiveTests = $true` (always)

---

*Testing analysis: 2026-02-19*
