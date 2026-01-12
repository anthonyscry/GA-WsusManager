<#
.SYNOPSIS
    FlaUI UI Automation Tests Template for PS2EXE GUI Applications

.DESCRIPTION
    This is a template for creating UI automation tests for PowerShell GUI
    applications compiled with PS2EXE. Copy this file to your project's
    Tests folder and customize it for your specific application.

.NOTES
    Prerequisites:
    - FlaUI packages installed in C:\projects\FlaUI-TestHarness\packages
    - Pester module installed (Install-Module Pester -Force)
    - Application compiled to EXE using PS2EXE

.EXAMPLE
    # Run tests
    Invoke-Pester -Path ".\Tests\FlaUI.Tests.ps1" -Output Detailed
#>

#region Test Configuration

BeforeAll {
    # ===========================================================================
    # CONFIGURATION - Customize these for your application
    # ===========================================================================

    # Project name (replace with your app name)
    $script:AppName = "GA-WsusManager"  # <-- CHANGE THIS

    # Paths
    $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
    $script:ExePath = Join-Path $script:ProjectRoot "$script:AppName.exe"
    $script:ScreenshotPath = Join-Path $script:ProjectRoot "Tests\Screenshots"

    # Test harness path (shared across projects)
    $script:FlaUIHarnessPath = "C:\projects\FlaUI-TestHarness"

    # Import FlaUI Test Harness Module
    $modulePath = Join-Path $script:FlaUIHarnessPath "FlaUITestHarness.psm1"
    $script:FlaUIAvailable = Test-Path $modulePath
    if ($script:FlaUIAvailable) {
        Import-Module $modulePath -Force
    } else {
        Write-Warning "FlaUI Test Harness not found at: $modulePath - FlaUI tests will be skipped"
    }

    # Check if EXE exists
    $script:ExeAvailable = Test-Path $script:ExePath

    # Create screenshots directory
    if (-not (Test-Path $script:ScreenshotPath)) {
        New-Item -Path $script:ScreenshotPath -ItemType Directory -Force | Out-Null
    }

    # ===========================================================================
    # TEST TIMEOUTS AND SETTINGS
    # ===========================================================================
    $script:AppStartTimeout = 30      # Seconds to wait for app to start
    $script:ElementTimeout = 10       # Default element search timeout
    $script:ActionDelay = 500         # Milliseconds between actions
}

AfterAll {
    # Ensure application is closed after all tests
    Stop-GuiApplication -Force -ErrorAction SilentlyContinue
}

#endregion

#region Pre-Flight Checks

Describe "$script:AppName Pre-Flight Checks" -Skip:(-not $script:FlaUIAvailable) {
    Context 'Test Environment' {
        It 'FlaUI module is loaded' {
            if (-not $script:FlaUIAvailable) { Set-ItResult -Skipped -Because "FlaUI harness not installed" }
            Get-Module FlaUITestHarness | Should -Not -BeNullOrEmpty
        }

        It 'Application EXE exists' {
            Test-Path $script:ExePath | Should -BeTrue -Because "$script:ExePath should exist"
        }

        It 'Application is not already running' {
            if (-not $script:ExeAvailable) { Set-ItResult -Skipped -Because "EXE not found" }
            $running = Get-Process -Name $script:AppName -ErrorAction SilentlyContinue
            if ($running) {
                Write-Warning "Stopping existing instance of $script:AppName"
                $running | Stop-Process -Force
                Start-Sleep -Seconds 2
            }
            Get-Process -Name $script:AppName -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        }
    }
}

#endregion

#region Application Startup Tests

Describe "$script:AppName Startup Tests" -Skip:(-not ($script:FlaUIAvailable -and $script:ExeAvailable)) {
    BeforeAll {
        # Start the application
        $script:AppContext = Start-GuiApplication -Path $script:ExePath -Timeout $script:AppStartTimeout
    }

    AfterAll {
        # Capture final screenshot and close
        try {
            Save-UIScreenshot -Path (Join-Path $script:ScreenshotPath "Startup_Final.png")
        } catch { }
        Stop-GuiApplication -Force -ErrorAction SilentlyContinue
    }

    Context 'Application Launch' {
        It 'Application starts successfully' {
            $script:AppContext | Should -Not -BeNullOrEmpty
            $script:AppContext.ProcessId | Should -BeGreaterThan 0
        }

        It 'Main window appears' {
            $script:AppContext.MainWindow | Should -Not -BeNullOrEmpty
        }

        It 'Window title is correct' {
            # Customize this for your application
            $script:AppContext.MainWindow.Title | Should -Match $script:AppName
        }

        It 'Window is visible and not minimized' {
            $window = $script:AppContext.MainWindow
            $window.IsOffscreen | Should -BeFalse
        }
    }

    Context 'Initial UI State' {
        It 'Main content area is present' {
            # Customize: Add checks for your main UI elements
            # Example: Assert-UIElementExists -AutomationId "MainContent"
            $script:AppContext.MainWindow | Should -Not -BeNullOrEmpty
        }

        # Add more initial state checks specific to your application
        # Example:
        # It 'Navigation panel is visible' {
        #     Assert-UIElementExists -AutomationId "NavPanel"
        # }
        #
        # It 'Status bar shows Ready' {
        #     Assert-UIElementText -AutomationId "StatusLabel" -ExpectedText "Ready"
        # }
    }
}

#endregion

#region Navigation Tests (Template - Customize for your app)

Describe "$script:AppName Navigation Tests" -Tag "Navigation" -Skip:(-not ($script:FlaUIAvailable -and $script:ExeAvailable)) {
    BeforeAll {
        $script:AppContext = Start-GuiApplication -Path $script:ExePath -Timeout $script:AppStartTimeout
    }

    AfterAll {
        Stop-GuiApplication -Force -ErrorAction SilentlyContinue
    }

    # Customize these tests based on your application's navigation structure
    # Example for a multi-page WPF app:

    Context 'Page Navigation' {
        # It 'Can navigate to Settings page' {
        #     Invoke-UIClick -AutomationId "btnSettings"
        #     Start-Sleep -Milliseconds $script:ActionDelay
        #     Assert-UIElementExists -AutomationId "SettingsPage"
        # }

        # It 'Can navigate back to Home page' {
        #     Invoke-UIClick -AutomationId "btnHome"
        #     Start-Sleep -Milliseconds $script:ActionDelay
        #     Assert-UIElementExists -AutomationId "HomePage"
        # }

        It 'Placeholder - Add your navigation tests' {
            # Remove this and add your actual navigation tests
            $true | Should -BeTrue
        }
    }
}

#endregion

#region Core Functionality Tests (Template - Customize for your app)

Describe "$script:AppName Core Functionality" -Tag "Functional" -Skip:(-not ($script:FlaUIAvailable -and $script:ExeAvailable)) {
    BeforeAll {
        $script:AppContext = Start-GuiApplication -Path $script:ExePath -Timeout $script:AppStartTimeout
    }

    AfterAll {
        try {
            Save-UIScreenshot -Path (Join-Path $script:ScreenshotPath "Functional_Final.png")
        } catch { }
        Stop-GuiApplication -Force -ErrorAction SilentlyContinue
    }

    # Add tests for your application's core functionality
    # Examples:

    Context 'Form Input Handling' {
        # It 'Can enter text in input field' {
        #     Set-UIText -AutomationId "txtInput" -Text "Test Value" -Clear
        #     $text = Get-UIText -AutomationId "txtInput"
        #     $text | Should -Be "Test Value"
        # }

        # It 'Submit button becomes enabled with valid input' {
        #     Set-UIText -AutomationId "txtRequired" -Text "Valid Data" -Clear
        #     Assert-UIElementEnabled -AutomationId "btnSubmit"
        # }

        It 'Placeholder - Add your input tests' {
            $true | Should -BeTrue
        }
    }

    Context 'Button Actions' {
        # It 'Clicking action button triggers expected behavior' {
        #     Invoke-UIClick -AutomationId "btnAction"
        #     Start-Sleep -Seconds 1
        #     Assert-UIElementText -AutomationId "lblResult" -ExpectedText "Action Complete"
        # }

        It 'Placeholder - Add your button action tests' {
            $true | Should -BeTrue
        }
    }

    Context 'Data Display' {
        # It 'Data grid displays results' {
        #     # Trigger data load
        #     Invoke-UIClick -AutomationId "btnLoadData"
        #     Start-Sleep -Seconds 2
        #
        #     $rows = Get-WPFDataGridRows -AutomationId "dgResults"
        #     $rows.Count | Should -BeGreaterThan 0
        # }

        It 'Placeholder - Add your data display tests' {
            $true | Should -BeTrue
        }
    }
}

#endregion

#region Error Handling Tests

Describe "$script:AppName Error Handling" -Tag "ErrorHandling" -Skip:(-not ($script:FlaUIAvailable -and $script:ExeAvailable)) {
    BeforeAll {
        $script:AppContext = Start-GuiApplication -Path $script:ExePath -Timeout $script:AppStartTimeout
    }

    AfterAll {
        Stop-GuiApplication -Force -ErrorAction SilentlyContinue
    }

    Context 'Invalid Input Handling' {
        # It 'Shows error for invalid input' {
        #     Set-UIText -AutomationId "txtInput" -Text "INVALID" -Clear
        #     Invoke-UIClick -AutomationId "btnSubmit"
        #     Start-Sleep -Milliseconds 500
        #     Assert-UIElementExists -AutomationId "ErrorMessage"
        # }

        It 'Placeholder - Add your error handling tests' {
            $true | Should -BeTrue
        }
    }

    Context 'Application Resilience' {
        It 'Application remains responsive after test interactions' {
            # Verify the app is still responsive
            $window = (Get-GuiApplication).MainWindow
            $window | Should -Not -BeNullOrEmpty
            $window.IsOffscreen | Should -BeFalse
        }
    }
}

#endregion

#region Performance Tests

Describe "$script:AppName Performance" -Tag "Performance" -Skip:(-not ($script:FlaUIAvailable -and $script:ExeAvailable)) {
    Context 'Startup Performance' {
        It 'Application starts within acceptable time' {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            $context = Start-GuiApplication -Path $script:ExePath -Timeout 60
            $stopwatch.Stop()

            Stop-GuiApplication -Force

            # Adjust threshold based on your requirements
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 30000 -Because "App should start within 30 seconds"
        }
    }

    # Add more performance tests as needed
    # Context 'Operation Performance' {
    #     It 'Data load completes within acceptable time' {
    #         # Measure specific operations
    #     }
    # }
}

#endregion

#region Cleanup

Describe "$script:AppName Cleanup Verification" -Tag "Cleanup" -Skip:(-not ($script:FlaUIAvailable -and $script:ExeAvailable)) {
    It 'Application process is terminated' {
        Stop-GuiApplication -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1

        $running = Get-Process -Name $script:AppName -ErrorAction SilentlyContinue
        $running | Should -BeNullOrEmpty -Because "Application should be fully terminated"
    }
}

#endregion

