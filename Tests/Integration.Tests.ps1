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
    $script:BuildScript = Join-Path $script:RepoRoot "build.ps1"
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
        It "WsusManagementGui.ps1 default sync products include .NET Framework and Visual Studio 2022, not Microsoft 365 Apps" {
            $content = Get-Content $script:GuiScript -Raw
            $content | Should -Match '\$script:DefaultSyncProducts\s*=\s*@\('
            $content | Should -Match '"\.NET Framework"'
            $content | Should -Match '"Visual Studio 2022"'
            $content | Should -Not -Match '\$script:DefaultSyncProducts\s*=\s*@\([^)]*"Microsoft 365 Apps"'
        }
        It "WsusManagementGui.ps1 resolves branding assets from Assets\\Branding and packaged roots" {
            $content = Get-Content $script:GuiScript -Raw
            $content | Should -Match 'function Resolve-WsusBrandingAssetPath'
            ([regex]::Matches($content, 'Assets\\Branding').Count) | Should -BeGreaterThan 1
            $content | Should -Match "Resolve-WsusBrandingAssetPath -FileName 'wsus-icon\.ico'"
        }

        It "build.ps1 sources icons from Assets\\Branding" {
            $content = Get-Content $script:BuildScript -Raw
            $content | Should -Match 'Assets\\Branding'
            $content | Should -Match 'wsus-icon\.ico'
            $content | Should -Match 'general_atomics_logo_small\.ico'
            $content | Should -Match 'general_atomics_logo_big\.ico'
        }

        It "Tray minimize keeps a taskbar recovery path" {
            $content = Get-Content $script:GuiScript -Raw
            $content | Should -Match 'function Restore-WsusMainWindowFromTray'
            $content | Should -Match 'function Set-WsusTrayIconVisible'
            $trayBlock = [regex]::Match($content, '(?s)# Intercept minimize.*?\$script:window\.Add_Closing').Value
            $trayBlock | Should -Not -Match '\.Hide\('
            $trayBlock | Should -Match 'ShowInTaskbar\s*=\s*\$true'
        }

        It "GUI help and about copy reflects current air-gap guidance and disk sizing" {
            $content = Get-Content $script:GuiScript -Raw
            $content | Should -Match '200 GB\+ disk space recommended'
            $content | Should -Match 'approved export folder'
            $content | Should -Match 'creates Member Servers, WSUS Server, and Workstations OUs if needed'
            $content | Should -Not -Match 'Online WSUS: Internet-connected'
            $content | Should -Not -Match '150 GB\+ disk space'
            $quickStartBlock = [regex]::Match($content, '(?s)QUICK START GUIDE.*?KEYBOARD SHORTCUTS').Value
            $quickStartBlock.IndexOf('AIR-GAPPED RESTORE') | Should -BeGreaterOrEqual 0
            $quickStartBlock.IndexOf('ONLINE SYNC') | Should -BeGreaterThan $quickStartBlock.IndexOf('AIR-GAPPED RESTORE')
            $content | Should -Match 'Use Robocopy if WsusContent still needs to be copied'
            $content | Should -Not -Match 'Robocopy/Import'
            $content | Should -Not -Match 'Robocopy Export'
            $content | Should -Not -Match 'Robocopy Import'
        }

        It "GUI popups use the readable themed dialog before native MessageBox fallback" {
            $content = Get-Content $script:GuiScript -Raw
            $content | Should -Match 'function Show-WsusCustomPopup'
            $popupFunction = [regex]::Match($content, '(?s)function Show-WsusPopup \{.*?\n\}').Value
            $popupFunction | Should -Match 'Show-WsusCustomPopup'
        }

        It "GUI removes Create GPO menu and places Fix SQL Login under diagnostics" {
            $content = Get-Content $script:GuiScript -Raw
            $content | Should -Not -Match 'x:Name="BtnCreateGpo"'
            $content | Should -Not -Match 'BtnCreateGpo\.Add_Click'
            $content | Should -Match 'Copy the whole DomainController folder'

            $diagnosticsBlock = [regex]::Match($content, '(?s)<Expander x:Name="DiagnosticsExpander".*?</Expander>').Value
            $diagnosticsBlock | Should -Match 'Header="DIAGNOSTICS"'
            $diagnosticsBlock | Should -Match 'IsExpanded="False"'
            $diagnosticsBlock | Should -Match 'x:Name="BtnFixSqlLogin"'
            $diagnosticsBlock | Should -Match 'x:Name="BtnDiagnostics"'
        }

        It "GUI groups maintenance and online operation buttons in the requested order" {
            $content = Get-Content $script:GuiScript -Raw
            $navBlock = [regex]::Match($content, '(?s)<ScrollViewer VerticalScrollBarVisibility="Auto".*?</ScrollViewer>').Value
            $navBlock | Should -Match 'Text="MAINTENANCE"'
            $navBlock | Should -Match 'x:Name="OnlineOperationsExpander"'
            $navBlock | Should -Match 'Header="ONLINE OPERATIONS"'
            $navBlock | Should -Match 'x:Name="DiagnosticsExpander"'
            $navBlock | Should -Match 'IsExpanded="False"'

            $restoreIndex = $navBlock.IndexOf('x:Name="BtnRestore"')
            $transferIndex = $navBlock.IndexOf('x:Name="BtnTransfer"')
            $cleanupIndex = $navBlock.IndexOf('x:Name="BtnCleanup"')
            $onlineHeaderIndex = $navBlock.IndexOf('Header="ONLINE OPERATIONS"')
            $maintenanceIndex = $navBlock.IndexOf('x:Name="BtnMaintenance"')
            $scheduleIndex = $navBlock.IndexOf('x:Name="BtnSchedule"')

            $restoreIndex | Should -BeGreaterOrEqual 0
            $transferIndex | Should -BeGreaterThan $restoreIndex
            $cleanupIndex | Should -BeGreaterThan $transferIndex
            $onlineHeaderIndex | Should -BeGreaterThan $cleanupIndex
            $maintenanceIndex | Should -BeGreaterThan $onlineHeaderIndex
            $scheduleIndex | Should -BeGreaterThan $maintenanceIndex
            $navButtonStyle = [regex]::Match($content, '(?s)<Style x:Key="NavBtn".*?</Style>').Value
            $navButtonStyle | Should -Match 'Property="FontWeight" Value="Normal"'
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
                @{ ModuleName = "WsusStartupProbe"; ModulesPath = $script:TestModulesPath }
                @{ ModuleName = "WsusOperationCompletion"; ModulesPath = $script:TestModulesPath }
                @{ ModuleName = "WsusGuiShell"; ModulesPath = $script:TestModulesPath }
                @{ ModuleName = "WsusHostEnvironment"; ModulesPath = $script:TestModulesPath }
                @{ ModuleName = "WsusProcessHost"; ModulesPath = $script:TestModulesPath }
                @{ ModuleName = "WsusOperationPlan"; ModulesPath = $script:TestModulesPath }
                @{ ModuleName = "WsusProvisioning"; ModulesPath = $script:TestModulesPath }
                @{ ModuleName = "WsusRepairPlan"; ModulesPath = $script:TestModulesPath }
                @{ ModuleName = "WsusRepairHarness"; ModulesPath = $script:TestModulesPath }
                @{ ModuleName = "WsusTestHarness"; ModulesPath = $script:TestModulesPath }
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
            Import-Module (Join-Path $script:ModulesPath 'WsusDatabase.psm1') -Force -DisableNameChecking -ErrorAction SilentlyContinue
            Import-Module (Join-Path $script:ModulesPath 'WsusUtilities.psm1') -Force -DisableNameChecking -ErrorAction SilentlyContinue
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
            $content = Get-Content (Join-Path $script:ModulesPath 'WsusUtilities.psm1') -Raw
            $content | Should -Match 'Clear-WsusSecretEnvironment'
        }

        It "GUI keeps stable baseline export root default" {
            $content = Get-Content $script:GuiScript -Raw
            $content | Should -Match '\$script:ExportRoot = "C:\\\"'
        }

        It "GUI transfer uses the selected destination root and appends the source folder" {
            $content = Get-Content $script:GuiScript -Raw
            $content | Should -Match '\$dst = Get-EscapedPath \(Join-Path \$opts\.DestinationPath \$srcFolderName\)'
            $content | Should -Match 'robocopy `"\$src`" `"\$dst`"'
            $transferBlock = [regex]::Match($content, '(?s)"transfer" \{.*?\n        \}').Value
            $transferBlock | Should -Not -Match '\$script:ForceEmbeddedMode\s*=\s*\$true'
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

    It "GUI script AppVersion matches the metadata version" {
        $guiContent = Get-Content $script:GuiScript -Raw
        $expected = (Get-Content (Join-Path $script:RepoRoot "metadata.json") -Raw | ConvertFrom-Json).version
        $guiContent | Should -Match "\`$script:AppVersion = `"$([regex]::Escape($expected))`""
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
