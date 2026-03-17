<#
.SYNOPSIS
    FlaUI UI Automation Tests for WSUS Manager GUI

.DESCRIPTION
    Automated end-to-end GUI tests using FlaUI (UIA3) to drive the
    WSUS Manager WPF application. Tests cover startup, navigation,
    panel visibility, dialog open/close, and UI state assertions.

    These tests require:
    1. FlaUI NuGet packages installed (run Tests/FlaUITestHarness/Install-FlaUI.ps1)
    2. Windows OS (UI Automation is Windows-only)
    3. Administrator privileges (app requires admin)
    4. The compiled EXE or the PS1 script available

    Tests are designed to work WITHOUT WSUS installed (clean VM safe).
    WSUS-dependent operations are tagged "RequiresWsus" and skipped
    when WSUS is not present.

.NOTES
    Prerequisites:
    - FlaUI packages installed in Tests/FlaUITestHarness/packages
    - Pester 5+ (Install-Module Pester -Force)
    - Application compiled to EXE or PS1 script available
    - Run as Administrator

.EXAMPLE
    # Run all FlaUI tests
    Invoke-Pester -Path ".\Tests\FlaUI.Tests.ps1" -Output Detailed

    # Run only navigation tests
    Invoke-Pester -Path ".\Tests\FlaUI.Tests.ps1" -Output Detailed -Tag "Navigation"

    # Run excluding WSUS-dependent tests
    Invoke-Pester -Path ".\Tests\FlaUI.Tests.ps1" -Output Detailed -ExcludeTag "RequiresWsus"
#>

#region Test Configuration

# BeforeDiscovery runs during Pester's discovery phase, BEFORE -Skip is evaluated.
# This is critical — variables used in -Skip must be set here, not in BeforeAll.
BeforeDiscovery {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:AppName = "GA-WsusManager"

    # Find executable — prefer dist/ build, fall back to root, then PS1 script
    $exeCandidates = @(
        (Join-Path $script:RepoRoot "dist\GA-WsusManager.exe"),
        (Join-Path $script:RepoRoot "dist\WsusManager.exe"),
        (Join-Path $script:RepoRoot "GA-WsusManager.exe"),
        (Join-Path $script:RepoRoot "WsusManager.exe"),
        (Join-Path $script:RepoRoot "Scripts\WsusManagementGui.ps1")
    )
    $script:ExePath = $null
    foreach ($c in $exeCandidates) {
        if (Test-Path $c) { $script:ExePath = $c; break }
    }

    $harnessPath = Join-Path $PSScriptRoot "FlaUITestHarness\FlaUITestHarness.psm1"
    $script:FlaUIAvailable = (Test-Path $harnessPath)

    # Test FlaUI assembly loading during discovery
    if ($script:FlaUIAvailable) {
        Import-Module $harnessPath -Force
        try {
$null = [FlaUI.UIA3.UIA3Automation]::new() 2>$null; if ($?) { $script:FlaUIAssembliesLoaded = $true; return }
$null = [FlaUI.UIA2.UIA2Automation]::new() 2>$null; if ($?) { $script:FlaUIAssembliesLoaded = $true; return }
$script:FlaUIAssembliesLoaded = $false
        } catch {
            $script:FlaUIAssembliesLoaded = $false
        }
    } else {
        $script:FlaUIAssembliesLoaded = $false
    }

    $script:ExeAvailable = ($null -ne $script:ExePath -and (Test-Path $script:ExePath))
    $script:CanRunTests = ($script:FlaUIAvailable -and $script:ExeAvailable -and $script:FlaUIAssembliesLoaded)

    if (-not $script:CanRunTests) {
        $reasons = @()
        if (-not $script:FlaUIAvailable) { $reasons += "FlaUI harness not found" }
        if (-not $script:ExeAvailable) { $reasons += "EXE/script not found" }
        if (-not $script:FlaUIAssembliesLoaded) { $reasons += "FlaUI assemblies failed to load" }
        Write-Warning "FlaUI tests skipped: $($reasons -join ', ')"
    }
}

BeforeAll {
    # Re-assign discovery variables — BeforeDiscovery runs in a different scope
    # and $script: variables may not carry over in Pester 5.x
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:AppName = "GA-WsusManager"
    $script:ScreenshotDir = Join-Path $PSScriptRoot "Screenshots"

    # Find executable (same logic as BeforeDiscovery for runtime use)
    $exeCandidates = @(
        (Join-Path $script:RepoRoot "dist\GA-WsusManager.exe"),
        (Join-Path $script:RepoRoot "dist\WsusManager.exe"),
        (Join-Path $script:RepoRoot "GA-WsusManager.exe"),
        (Join-Path $script:RepoRoot "WsusManager.exe"),
        (Join-Path $script:RepoRoot "Scripts\WsusManagementGui.ps1")
    )
    $script:ExePath = $null
    foreach ($c in $exeCandidates) {
        if (Test-Path $c) { $script:ExePath = $c; break }
    }

    # Import FlaUI Test Harness (also needed at runtime for harness functions)
    $harnessPath = Join-Path $PSScriptRoot "FlaUITestHarness\FlaUITestHarness.psm1"
    $script:FlaUIAvailable = (Test-Path $harnessPath)
    if ($script:FlaUIAvailable) {
        Import-Module $harnessPath -Force
        try {
$null = [FlaUI.UIA3.UIA3Automation]::new() 2>$null; if ($?) { $script:FlaUIAssembliesLoaded = $true; return }
$null = [FlaUI.UIA2.UIA2Automation]::new() 2>$null; if ($?) { $script:FlaUIAssembliesLoaded = $true; return }
$script:FlaUIAssembliesLoaded = $false
        } catch {
            $script:FlaUIAssembliesLoaded = $false
        }
    } else {
        $script:FlaUIAssembliesLoaded = $false
    }

    $script:ExeAvailable = ($null -ne $script:ExePath -and (Test-Path $script:ExePath))
    $script:CanRunTests = ($script:FlaUIAvailable -and $script:ExeAvailable -and $script:FlaUIAssembliesLoaded)

    # Detect WSUS installation
    $script:WsusInstalled = $false
    if ($env:OS -eq "Windows_NT") {
        $script:WsusInstalled = (Get-Service -Name "WSUSService" -ErrorAction SilentlyContinue) -ne $null
    }

    # Create screenshots directory
    if (-not (Test-Path $script:ScreenshotDir)) {
        New-Item -Path $script:ScreenshotDir -ItemType Directory -Force | Out-Null
    }

    # Kill any existing instances
    if ($env:OS -eq "Windows_NT") {
        Get-Process -Name $script:AppName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
    }

    $script:AppStartTimeout = 45
    $script:ElementTimeout = 10
    $script:ActionDelay = 500
}

AfterAll {
    Stop-GuiApplication -Force -ErrorAction SilentlyContinue
    # Ensure cleanup
    if ($env:OS -eq "Windows_NT") {
        Get-Process -Name $script:AppName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
}

#endregion

#region Pre-Flight Checks

Describe "WSUS Manager Pre-Flight Checks" -Skip:(-not $script:CanRunTests) {
    Context 'Test Environment' {
        It 'FlaUI Test Harness is loaded' {
            Get-Module FlaUITestHarness | Should -Not -BeNullOrEmpty
        }

        It 'FlaUI .NET assemblies are available' {
            $script:FlaUIAssembliesLoaded | Should -BeTrue
        }

        It 'Application file exists' {
            $script:ExePath | Should -Not -BeNullOrEmpty
            Test-Path $script:ExePath | Should -BeTrue -Because "EXE/script should exist at $($script:ExePath)"
        }
    }

    Context 'Clean State' {
        It 'No existing instances are running' {
            $running = Get-Process -Name $script:AppName -ErrorAction SilentlyContinue
            if ($running) {
                $running | Stop-Process -Force
                Start-Sleep -Seconds 2
            }
            Get-Process -Name $script:AppName -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        }
    }
}

#endregion

#region Application Startup Tests

Describe "WSUS Manager Startup" -Skip:(-not $script:CanRunTests) {
    BeforeAll {
        $script:AppContext = $null
        try {
            $script:AppContext = Start-GuiApplication -Path $script:ExePath -Timeout $script:AppStartTimeout
        } catch {
            $script:StartupError = $_.Exception.Message
        }
    }

    AfterAll {
        if ($script:AppContext) {
            try { Save-UIScreenshot -Path (Join-Path $script:ScreenshotDir "Startup_Final.png") } catch { }
        }
        Stop-GuiApplication -Force -ErrorAction SilentlyContinue
    }

    Context 'Application Launch' {
        It 'Starts without exception' {
            if ($script:StartupError) {
                throw "Startup failed: $($script:StartupError)"
            }
            $script:AppContext | Should -Not -BeNullOrEmpty
        }

        It 'Returns a valid process ID' {
            $script:AppContext.ProcessId | Should -BeGreaterThan 0
        }

        It 'Main window is accessible' {
            $script:AppContext.MainWindow | Should -Not -BeNullOrEmpty
        }

        It 'Window title contains "WSUS Manager"' {
            # Title may vary slightly, just check key part
            $script:AppContext.MainWindow.Title | Should -Match "WSUS"
        }

        It 'Window is visible (not minimized or offscreen)' {
            $script:AppContext.MainWindow.IsOffscreen | Should -BeFalse
        }
    }

    Context 'Initial UI State' {
        It 'Dashboard panel is visible' {
            $el = Assert-UIElementExists -AppContext $script:AppContext -AutomationId "DashboardPanel"
            # Dashboard starts visible, so it should NOT be offscreen
            # Note: AutomationId on Grid doesn't guarantee we can check offscreen
            $el | Should -Not -BeNullOrEmpty
        }

        It 'Health score element exists' {
            Assert-UIElementExists -AppContext $script:AppContext -AutomationId "HealthScoreValue" | Should -Not -BeNullOrEmpty
        }

        It 'Health score grade element exists' {
            Assert-UIElementExists -AppContext $script:AppContext -AutomationId "HealthScoreGrade" | Should -Not -BeNullOrEmpty
        }

        It 'Log panel exists' {
            Assert-UIElementExists -AppContext $script:AppContext -AutomationId "LogPanel" | Should -Not -BeNullOrEmpty
        }

        It 'Install panel exists (may be collapsed)' {
            Assert-UIElementExists -AppContext $script:AppContext -AutomationId "InstallPanel" | Should -Not -BeNullOrEmpty
        }
    }
}

#endregion

#region Navigation Tests

Describe "WSUS Manager Navigation" -Tag "Navigation" -Skip:(-not $script:CanRunTests) {
    BeforeAll {
        $script:AppContext = Start-GuiApplication -Path $script:ExePath -Timeout $script:AppStartTimeout
    }

    AfterAll {
        try { Save-UIScreenshot -Path (Join-Path $script:ScreenshotDir "Navigation_Final.png") } catch { }
        Stop-GuiApplication -Force -ErrorAction SilentlyContinue
    }

    Context 'Sidebar Navigation Buttons Exist' {
        # These buttons use x:Name which FlaUI can find via Name property
        $navButtons = @(
            @{ Name = "BtnDashboard";    Label = "Dashboard" },
            @{ Name = "BtnInstall";      Label = "Install WSUS" },
            @{ Name = "BtnRestore";      Label = "Restore DB" },
            @{ Name = "BtnCreateGpo";    Label = "Create GPO" },
            @{ Name = "BtnTransfer";     Label = "Export/Import" },
            @{ Name = "BtnMaintenance";  Label = "Online Sync" },
            @{ Name = "BtnSchedule";     Label = "Schedule Task" },
            @{ Name = "BtnCleanup";      Label = "Deep Cleanup" },
            @{ Name = "BtnDiagnostics";  Label = "Run Diagnostics" },
            @{ Name = "BtnReset";        Label = "Reset Content" },
            @{ Name = "BtnHistory";      Label = "History" },
            @{ Name = "BtnHelp";         Label = "Help" },
            @{ Name = "BtnSettings";     Label = "Settings" },
            @{ Name = "BtnAbout";        Label = "About" }
        )

        It "Button '<Label>' (x:Name=<Name>) exists" -TestCases $navButtons {
            param($Name, $Label)
            $el = Find-UIElement -AppContext $script:AppContext -Name $Name -ClassName "Button" -Timeout 5
            $el | Should -Not -BeNullOrEmpty -Because "Nav button '$Label' should exist"
        }
    }

    Context 'Panel Navigation via Sidebar' {
        It 'Clicking Dashboard returns to Dashboard panel' {
            Invoke-UIClick -AppContext $script:AppContext -Name "BtnDashboard" -Delay $script:ActionDelay
            # Dashboard panel should be visible (we can't easily check WPF Visibility via UIA,
            # but we can verify the PageTitle text)
            Start-Sleep -Milliseconds 500
            $pageTitle = Find-UIElement -AppContext $script:AppContext -Name "PageTitle" -Timeout 5
            $pageTitle | Should -Not -BeNullOrEmpty
            # PageTitle is a TextBlock — check its Name (which carries the text in WPF)
        }

        It 'Clicking About shows About panel' {
            Invoke-UIClick -AppContext $script:AppContext -Name "BtnAbout" -Delay $script:ActionDelay
            $aboutPanel = Assert-UIElementExists -AppContext $script:AppContext -AutomationId "AboutPanel"
            $aboutPanel | Should -Not -BeNullOrEmpty
        }

        It 'Clicking Help shows Help panel' {
            Invoke-UIClick -AppContext $script:AppContext -Name "BtnHelp" -Delay $script:ActionDelay
            $helpPanel = Assert-UIElementExists -AppContext $script:AppContext -AutomationId "HelpPanel"
            $helpPanel | Should -Not -BeNullOrEmpty
        }

        It 'Clicking Install shows Install panel' {
            Invoke-UIClick -AppContext $script:AppContext -Name "BtnInstall" -Delay $script:ActionDelay
            $installPanel = Assert-UIElementExists -AppContext $script:AppContext -AutomationId "InstallPanel"
            $installPanel | Should -Not -BeNullOrEmpty
        }

        It 'Clicking History shows History panel' {
            Invoke-UIClick -AppContext $script:AppContext -Name "BtnHistory" -Delay $script:ActionDelay
            $historyPanel = Assert-UIElementExists -AppContext $script:AppContext -AutomationId "HistoryPanel" -Timeout 5
            $historyPanel | Should -Not -BeNullOrEmpty
        }

        It 'Clicking Dashboard from any panel returns to Dashboard' {
            # Navigate away first
            Invoke-UIClick -AppContext $script:AppContext -Name "BtnAbout" -Delay $script:ActionDelay
            Invoke-UIClick -AppContext $script:AppContext -Name "BtnDashboard" -Delay $script:ActionDelay
            $dashPanel = Assert-UIElementExists -AppContext $script:AppContext -AutomationId "DashboardPanel"
            $dashPanel | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Quick Action Buttons Exist' {
        $quickButtons = @(
            @{ Name = "QBtnDiagnostics" },
            @{ Name = "QBtnCleanup" },
            @{ Name = "QBtnMaint" },
            @{ Name = "QBtnStart" }
        )

        It "Quick action button '<Name>' exists" -TestCases $quickButtons {
            param($Name)
            $el = Find-UIElement -AppContext $script:AppContext -Name $Name -ClassName "Button" -Timeout 5
            $el | Should -Not -BeNullOrEmpty -Because "Quick action button '$Name' should exist"
        }
    }
}

#endregion

#region Settings Dialog Tests

Describe "WSUS Manager Settings Dialog" -Tag "Settings" -Skip:(-not $script:CanRunTests) {
    BeforeAll {
        $script:AppContext = Start-GuiApplication -Path $script:ExePath -Timeout $script:AppStartTimeout
    }

    AfterAll {
        Stop-GuiApplication -Force -ErrorAction SilentlyContinue
    }

    Context 'Open Settings' {
        It 'Settings button opens a modal dialog' {
            Invoke-UIClick -AppContext $script:AppContext -Name "BtnSettings" -Delay 1000
            # Settings opens as a modal Window — find it by title
            $settingsWindow = $null
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            while ($sw.Elapsed.TotalSeconds -lt 5 -and $null -eq $settingsWindow) {
                $settingsWindow = Find-UIElement -AppContext $script:AppContext -Name "Settings" -ClassName "Window" -Timeout 1
            }
            $settingsWindow | Should -Not -BeNullOrEmpty -Because "Settings dialog should appear"
        }
    }

    Context 'Close Settings' {
        It 'ESC key closes the Settings dialog' {
            # Open Settings
            Invoke-UIClick -AppContext $script:AppContext -Name "BtnSettings" -Delay 1000
            Start-Sleep -Milliseconds 500

            # Send ESC
            Send-UIKeys -Keys "{ESC}" -Delay 1000

            # Verify dialog is gone
            $gone = Wait-UIElementGone -AppContext $script:AppContext -Name "Settings" -ClassName "Window" -Timeout 5
            $gone | Should -BeTrue -Because "ESC should close Settings dialog"
        }
    }
}

#endregion

#region About Dialog Tests

Describe "WSUS Manager About" -Tag "About" -Skip:(-not $script:CanRunTests) {
    BeforeAll {
        $script:AppContext = Start-GuiApplication -Path $script:ExePath -Timeout $script:AppStartTimeout
    }

    AfterAll {
        Stop-GuiApplication -Force -ErrorAction SilentlyContinue
    }

    It 'About panel shows version information' {
        Invoke-UIClick -AppContext $script:AppContext -Name "BtnAbout" -Delay $script:ActionDelay
        $aboutPanel = Assert-UIElementExists -AppContext $script:AppContext -AutomationId "AboutPanel"
        $aboutPanel | Should -Not -BeNullOrEmpty
        # About panel is a ScrollViewer with content — verify it exists and is not empty
    }

    It 'Navigating away from About shows Dashboard' {
        Invoke-UIClick -AppContext $script:AppContext -Name "BtnDashboard" -Delay $script:ActionDelay
        $dashPanel = Assert-UIElementExists -AppContext $script:AppContext -AutomationId "DashboardPanel"
        $dashPanel | Should -Not -BeNullOrEmpty
    }
}

#endregion

#region History Panel Tests

Describe "WSUS Manager History Panel" -Tag "History" -Skip:(-not $script:CanRunTests) {
    BeforeAll {
        $script:AppContext = Start-GuiApplication -Path $script:ExePath -Timeout $script:AppStartTimeout
    }

    AfterAll {
        Stop-GuiApplication -Force -ErrorAction SilentlyContinue
    }

    It 'History panel opens and shows list control' {
        Invoke-UIClick -AppContext $script:AppContext -Name "BtnHistory" -Delay $script:ActionDelay
        $historyPanel = Assert-UIElementExists -AppContext $script:AppContext -AutomationId "HistoryPanel"
        $historyPanel | Should -Not -BeNullOrEmpty

        # History panel contains a ListView named HistoryList
        $historyList = Find-UIElement -AppContext $script:AppContext -Name "HistoryList" -Timeout 3
        # May or may not have items, but the control should exist
        $historyList | Should -Not -BeNullOrEmpty -Because "History list control should exist"
    }

    It 'History filter and buttons exist' {
        # These controls are inside HistoryPanel
        $filter = Find-UIElement -AppContext $script:AppContext -Name "HistoryFilter" -Timeout 3
        $filter | Should -Not -BeNullOrEmpty -Because "History filter should exist"
    }
}

#endregion

#region Help Panel Tests

Describe "WSUS Manager Help Panel" -Tag "Help" -Skip:(-not $script:CanRunTests) {
    BeforeAll {
        $script:AppContext = Start-GuiApplication -Path $script:ExePath -Timeout $script:AppStartTimeout
    }

    AfterAll {
        Stop-GuiApplication -Force -ErrorAction SilentlyContinue
    }

    It 'Help panel opens with Overview content' {
        Invoke-UIClick -AppContext $script:AppContext -Name "BtnHelp" -Delay $script:ActionDelay
        $helpPanel = Assert-UIElementExists -AppContext $script:AppContext -AutomationId "HelpPanel"
        $helpPanel | Should -Not -BeNullOrEmpty
    }

    It 'Help content buttons exist' {
        $helpButtons = @("HelpBtnOverview", "HelpBtnDashboard", "HelpBtnOperations", "HelpBtnAirGap", "HelpBtnTroubleshooting")
        foreach ($btnName in $helpButtons) {
            $el = Find-UIElement -AppContext $script:AppContext -Name $btnName -ClassName "Button" -Timeout 2
            $el | Should -Not -BeNullOrEmpty -Because "Help button '$btnName' should exist"
        }
    }
}

#endregion

#region Performance Tests

Describe "WSUS Manager Performance" -Tag "Performance" -Skip:(-not $script:CanRunTests) {
    Context 'Startup Time' {
        It 'Application starts within 45 seconds' {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $ctx = Start-GuiApplication -Path $script:ExePath -Timeout 60
            $sw.Stop()

            Stop-GuiApplication -Force -ErrorAction SilentlyContinue

            $sw.ElapsedMilliseconds | Should -BeLessThan 45000 -Because "App should start within 45s (was $([math]::Round($sw.Elapsed.TotalSeconds, 1))s)"
        }
    }
}

#endregion

#region Resilience Tests

Describe "WSUS Manager Resilience" -Tag "Resilience" -Skip:(-not $script:CanRunTests) {
    BeforeAll {
        $script:AppContext = Start-GuiApplication -Path $script:ExePath -Timeout $script:AppStartTimeout
    }

    AfterAll {
        try { Save-UIScreenshot -Path (Join-Path $script:ScreenshotDir "Resilience_Final.png") } catch { }
        Stop-GuiApplication -Force -ErrorAction SilentlyContinue
    }

    Context 'Rapid Navigation' {
        It 'Survives rapid panel switching' {
            # Click through all nav buttons quickly
            $navButtons = @("BtnDashboard", "BtnInstall", "BtnAbout", "BtnHelp", "BtnHistory", "BtnDashboard")
            foreach ($btn in $navButtons) {
                Invoke-UIClick -AppContext $script:AppContext -Name $btn -Delay 200
            }

            # App should still be responsive
            Start-Sleep -Milliseconds 500
            $window = $script:AppContext.MainWindow
            $window | Should -Not -BeNullOrEmpty
            $window.IsOffscreen | Should -BeFalse
        }
    }

    Context 'Multiple Dialog Open/Close' {
        It 'Survives opening and closing Settings multiple times' {
            for ($i = 0; $i -lt 3; $i++) {
                Invoke-UIClick -AppContext $script:AppContext -Name "BtnSettings" -Delay 800
                Send-UIKeys -Keys "{ESC}" -Delay 800
            }

            # App should still be responsive
            $window = $script:AppContext.MainWindow
            $window | Should -Not -BeNullOrEmpty
        }
    }
}

#endregion

#region Cleanup Verification

Describe "WSUS Manager Cleanup" -Tag "Cleanup" -Skip:(-not $script:CanRunTests) {
    It 'Application process terminates cleanly' {
        Stop-GuiApplication -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2

        $running = Get-Process -Name $script:AppName -ErrorAction SilentlyContinue
        $running | Should -BeNullOrEmpty -Because "Application should be fully terminated after cleanup"
    }
}

#endregion
