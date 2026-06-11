#Requires -Modules Pester
<#
.SYNOPSIS
    Integration tests for WSUS Manager

.DESCRIPTION
    Tests to verify:
    - GUI script can be parsed without syntax errors
    - All modules load correctly
    - Module dependencies are satisfied
    - Key functions are available after module import
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:ModulesPath = Join-Path $script:RepoRoot "Modules"
    $script:ScriptsPath = Join-Path $script:RepoRoot "Scripts"
    $script:GuiScript = Join-Path $script:ScriptsPath "WsusManagementGui.ps1"
}

Describe "Script Syntax Validation" {
    Context "GUI Script" {
        It "WsusManagementGui.ps1 exists" {
            Test-Path $script:GuiScript | Should -BeTrue
        }

        It "WsusManagementGui.ps1 has no syntax errors" {
            $errors = $null
            $null = [System.Management.Automation.PSParser]::Tokenize(
                (Get-Content $script:GuiScript -Raw),
                [ref]$errors
            )
            $errors.Count | Should -Be 0
        }

        It "WsusManagementGui.ps1 sets AppVersion" {
            $content = Get-Content $script:GuiScript -Raw
            $content | Should -Match '\$script:AppVersion\s*=\s*'
        }
    }

    Context "CLI Scripts" {
        It "Invoke-WsusManagement.ps1 has no syntax errors" {
            $script = Join-Path $script:ScriptsPath "Invoke-WsusManagement.ps1"
            $errors = $null
            $null = [System.Management.Automation.PSParser]::Tokenize(
                (Get-Content $script -Raw),
                [ref]$errors
            )
            $errors.Count | Should -Be 0
        }

        It "Invoke-WsusMonthlyMaintenance.ps1 has no syntax errors" {
            $script = Join-Path $script:ScriptsPath "Invoke-WsusMonthlyMaintenance.ps1"
            $errors = $null
            $null = [System.Management.Automation.PSParser]::Tokenize(
                (Get-Content $script -Raw),
                [ref]$errors
            )
            $errors.Count | Should -Be 0
        }

        It "Install-WsusWithSqlExpress.ps1 has no syntax errors" {
            $script = Join-Path $script:ScriptsPath "Install-WsusWithSqlExpress.ps1"
            $errors = $null
            $null = [System.Management.Automation.PSParser]::Tokenize(
                (Get-Content $script -Raw),
                [ref]$errors
            )
            $errors.Count | Should -Be 0
        }
    }
}

Describe "Module Loading" {
    Context "All modules load without errors" {
        BeforeDiscovery {
            # Must set path in BeforeDiscovery for -ForEach tests to use
            $script:TestModulesPath = Join-Path (Split-Path -Parent $PSScriptRoot) "Modules"
            $script:ModuleList = @(
                @{ ModuleName = "WsusUtilities"; ModulesPath = $script:TestModulesPath }
                @{ ModuleName = "WsusServices"; ModulesPath = $script:TestModulesPath }
                @{ ModuleName = "WsusFirewall"; ModulesPath = $script:TestModulesPath }
                @{ ModuleName = "WsusPermissions"; ModulesPath = $script:TestModulesPath }
                @{ ModuleName = "WsusDatabase"; ModulesPath = $script:TestModulesPath }
                @{ ModuleName = "WsusHealth"; ModulesPath = $script:TestModulesPath }
                @{ ModuleName = "WsusConfig"; ModulesPath = $script:TestModulesPath }
                @{ ModuleName = "WsusExport"; ModulesPath = $script:TestModulesPath }
                @{ ModuleName = "WsusScheduledTask"; ModulesPath = $script:TestModulesPath }
                @{ ModuleName = "WsusAutoDetection"; ModulesPath = $script:TestModulesPath }
                @{ ModuleName = "WsusDiagnosticResult"; ModulesPath = $script:TestModulesPath }
                @{ ModuleName = "WsusGuiShell"; ModulesPath = $script:TestModulesPath }
                @{ ModuleName = "WsusHostEnvironment"; ModulesPath = $script:TestModulesPath }
                @{ ModuleName = "WsusProcessHost"; ModulesPath = $script:TestModulesPath }
                @{ ModuleName = "WsusOperationPlan"; ModulesPath = $script:TestModulesPath }
                @{ ModuleName = "WsusProvisioning"; ModulesPath = $script:TestModulesPath }
                @{ ModuleName = "WsusRepairPlan"; ModulesPath = $script:TestModulesPath }
                @{ ModuleName = "WsusRepairHarness"; ModulesPath = $script:TestModulesPath }
                @{ ModuleName = "WsusTestHarness"; ModulesPath = $script:TestModulesPath }
                @{ ModuleName = "AsyncHelpers"; ModulesPath = $script:TestModulesPath }
            )
        }

        It "<ModuleName>.psm1 loads without errors" -ForEach $script:ModuleList {
            $modulePath = Join-Path $ModulesPath "$ModuleName.psm1"
            { Import-Module $modulePath -Force -DisableNameChecking -ErrorAction Stop } | Should -Not -Throw
        }
    }

    Context "Key functions are exported" {
        BeforeAll {
            # Load all modules
            Get-ChildItem -Path $script:ModulesPath -Filter "*.psm1" | ForEach-Object {
                Import-Module $_.FullName -Force -DisableNameChecking -ErrorAction SilentlyContinue
            }
        }

        It "Write-Log function is available" {
            Get-Command -Name Write-Log -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "Test-AdminPrivileges function is available" {
            Get-Command -Name Test-AdminPrivileges -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "Invoke-WsusSqlcmd function is available" {
            Get-Command -Name Invoke-WsusSqlcmd -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "Get-WsusDatabaseSize function is available" {
            Get-Command -Name Get-WsusDatabaseSize -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "Test-WsusHealth function is available" {
            Get-Command -Name Test-WsusHealth -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "Export-WsusContent function is available" {
            Get-Command -Name Export-WsusContent -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "Security Validation" {
    Context "Password handling uses environment variables" {
        It "Install operation uses WSUS_INSTALL_SA_PASSWORD env var" {
            $content = Get-Content (Join-Path $script:ModulesPath 'WsusOperationPlan.psm1') -Raw
            $content | Should -Match 'WSUS_INSTALL_SA_PASSWORD'
        }

        It "Schedule task uses WSUS_TASK_PASSWORD env var" {
            $content = Get-Content (Join-Path $script:ModulesPath 'WsusOperationPlan.psm1') -Raw
            $content | Should -Match 'WSUS_TASK_PASSWORD'
        }

        It "Environment variables are cleaned up after use" {
            $content = Get-Content (Join-Path $script:ModulesPath 'WsusGuiShell.psm1') -Raw
            $content | Should -Match 'Clear-WsusSecretEnvironment'
        }

        It "GUI uses runtime-config DefaultExportPath" {
            $content = Get-Content $script:GuiScript -Raw
            $content | Should -Match '\$script:ExportRoot = \$script:RuntimeConfig\.DefaultExportPath'
        }

        It "GUI transfer import uses selected destination root directly" {
            $content = Get-Content $script:GuiScript -Raw
            $content | Should -Match 'New-WsusTransferOperationPlan -SourcePath \$opts\.SourcePath -DestinationPath \$opts\.DestinationPath'
        }
    }

    Context "Path validation functions exist" {
        BeforeAll {
            Import-Module (Join-Path $script:ModulesPath "WsusUtilities.psm1") -Force -DisableNameChecking -ErrorAction SilentlyContinue
        }

        It "Test-WsusPath function is available" {
            Get-Command -Name Test-WsusPath -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "Version Consistency" {
    BeforeAll {
        # Import the module so we can call Get-WsusAppVersion.
        $wsusConfigPath = Join-Path $script:RepoRoot "Modules\WsusConfig.psm1"
        if (Test-Path $wsusConfigPath) {
            Import-Module $wsusConfigPath -Force -DisableNameChecking
        }
    }

    It "WsusConfig module exposes Get-WsusAppVersion" {
        Get-Command Get-WsusAppVersion -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It "Get-WsusAppVersion returns the metadata.json version" {
        $expected = (Get-Content (Join-Path $script:RepoRoot "metadata.json") -Raw | ConvertFrom-Json).version
        Get-WsusAppVersion | Should -Be $expected
    }

    It "GUI script delegates AppVersion to Get-WsusAppVersion (not hardcoded)" {
        $guiContent = Get-Content $script:GuiScript -Raw
        $guiContent | Should -Match 'Get-WsusAppVersion'
    }

    It "build.ps1 reads version from metadata.json" {
        $buildContent = Get-Content (Join-Path $script:RepoRoot "build.ps1") -Raw
        $buildContent | Should -Match 'metadata\.json'
    }

    It "metadata.json has a valid semver-style version" {
        $meta = Get-Content (Join-Path $script:RepoRoot "metadata.json") -Raw | ConvertFrom-Json
        $meta.version | Should -Match '^\d+\.\d+\.\d+'
    }
}
