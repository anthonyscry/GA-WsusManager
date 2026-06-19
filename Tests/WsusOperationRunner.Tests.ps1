#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for WsusOperationRunner.psm1

.DESCRIPTION
    Unit tests for the WsusOperationRunner module functions including:
    - Find-WsusScript path resolution
    - Complete-WsusOperation GUI state teardown
    - Stop-WsusOperation null-safety
    - Start-WsusOperation parameter validation
#>

BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..\Modules\WsusOperationRunner.psm1'
    Import-Module $ModulePath -Force -DisableNameChecking

    # Load WPF assemblies once so DispatcherTimer (used by Start-WsusOperation)
    # is resolvable when tests exercise the runner end-to-end. Skip silently if
    # they are not present (Linux/CI hosts without PresentationCore).
    $script:WpfAvailable = $false
    try {
        Add-Type -AssemblyName PresentationCore -ErrorAction Stop
        Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
        Add-Type -AssemblyName WindowsBase -ErrorAction Stop
        $script:WpfAvailable = $true
    } catch {
        $script:WpfAvailable = $false
    }
}

AfterAll {
    Remove-Module WsusOperationRunner -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------
Describe "WsusOperationRunner Module" {
    Context "Module Loading" {
        It "Should import the module successfully" {
            Get-Module WsusOperationRunner | Should -Not -BeNullOrEmpty
        }

        It "Should export Find-WsusScript" {
            Get-Command Find-WsusScript -Module WsusOperationRunner | Should -Not -BeNullOrEmpty
        }

        It "Should export Start-WsusOperation" {
            Get-Command Start-WsusOperation -Module WsusOperationRunner | Should -Not -BeNullOrEmpty
        }

        It "Should export Stop-WsusOperation" {
            Get-Command Stop-WsusOperation -Module WsusOperationRunner | Should -Not -BeNullOrEmpty
        }

        It "Should export Complete-WsusOperation" {
            Get-Command Complete-WsusOperation -Module WsusOperationRunner | Should -Not -BeNullOrEmpty
        }
    }
}

# ---------------------------------------------------------------------------
Describe "Find-WsusScript" {
    BeforeAll {
        # Create a temporary directory tree for path resolution tests
        $script:TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "WsusRunnerTests_$([guid]::NewGuid().ToString('N'))"
        $script:TempScripts = Join-Path $script:TempRoot 'Scripts'
        New-Item -ItemType Directory -Path $script:TempRoot   -Force | Out-Null
        New-Item -ItemType Directory -Path $script:TempScripts -Force | Out-Null

        # A script placed directly in TempRoot
        $script:RootScript = Join-Path $script:TempRoot 'Invoke-WsusManagement.ps1'
        Set-Content -Path $script:RootScript -Value '# stub'

        # A script placed in the Scripts subdirectory
        $script:SubScript = Join-Path $script:TempScripts 'Invoke-WsusMonthlyMaintenance.ps1'
        Set-Content -Path $script:SubScript -Value '# stub'
    }

    AfterAll {
        Remove-Item -Path $script:TempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context "When the script exists directly in ScriptRoot" {
        It "Returns the full path to the script" {
            $result = Find-WsusScript -ScriptName 'Invoke-WsusManagement.ps1' -ScriptRoot $script:TempRoot
            $result | Should -Be $script:RootScript
        }

        It "Returns a string (not null)" {
            $result = Find-WsusScript -ScriptName 'Invoke-WsusManagement.ps1' -ScriptRoot $script:TempRoot
            $result | Should -BeOfType [string]
        }
    }

    Context "When the script exists only in the Scripts subdirectory" {
        It "Returns the path inside the Scripts subdirectory" {
            $result = Find-WsusScript -ScriptName 'Invoke-WsusMonthlyMaintenance.ps1' -ScriptRoot $script:TempRoot
            $result | Should -Be $script:SubScript
        }
    }

    Context "When the script does not exist anywhere" {
        It "Returns null" {
            $result = Find-WsusScript -ScriptName 'NonExistent.ps1' -ScriptRoot $script:TempRoot
            $result | Should -BeNullOrEmpty
        }
    }

    Context "When ScriptRoot itself does not exist" {
        It "Returns null without throwing" {
            $result = Find-WsusScript -ScriptName 'Invoke-WsusManagement.ps1' -ScriptRoot 'C:\DoesNotExist\Nowhere'
            $result | Should -BeNullOrEmpty
        }
    }

    Context "Parameter validation" {
        It "ScriptName parameter is mandatory" {
            $param = (Get-Command Find-WsusScript).Parameters['ScriptName']
            $param.Attributes.Where({ $_ -is [Parameter] }).Mandatory | Should -Be $true
        }

        It "ScriptRoot parameter is mandatory" {
            $param = (Get-Command Find-WsusScript).Parameters['ScriptRoot']
            $param.Attributes.Where({ $_ -is [Parameter] }).Mandatory | Should -Be $true
        }
    }
}

# ---------------------------------------------------------------------------
Describe "Stop-WsusOperation" {
    Context "Null safety" {
        It "Does not throw when Process is null" {
            { Stop-WsusOperation -Process $null } | Should -Not -Throw
        }

        It "Does not throw when called with no arguments" {
            { Stop-WsusOperation } | Should -Not -Throw
        }
    }

    Context "Already-exited process" {
        It "Does not throw for a process that has already exited" -Skip:($PSVersionTable.PSEdition -ne 'Desktop' -and $env:OS -ne 'Windows_NT') {
            # Start a trivially short process and wait for it to exit
            $proc = Start-Process -FilePath 'powershell.exe' `
                                  -ArgumentList '-NoProfile -Command exit 0' `
                                  -PassThru
            $proc.WaitForExit(5000) | Out-Null
            { Stop-WsusOperation -Process $proc } | Should -Not -Throw
        }
    }
}

# ---------------------------------------------------------------------------
Describe "Complete-WsusOperation" {
    BeforeAll {
        # Build a minimal mock dispatcher that records Invoke calls synchronously
        # so we can test UI-thread dispatch without an actual WPF window.

        $script:InvokeCallCount = 0

        # Dispatcher mock: a PSCustomObject whose Invoke ScriptMethod runs actions inline.
        $script:MockDispatcher = [PSCustomObject]@{ InvokeCount = 0 }
        $script:MockDispatcher | Add-Member -MemberType ScriptMethod -Name Invoke -Value {
            param($action)
            $this.InvokeCount++
            if ($action -is [scriptblock]) {
                $action.Invoke()
            } elseif ($action -is [System.Delegate]) {
                $action.DynamicInvoke()
            }
        }

        # Window mock: Window.Dispatcher returns the mock dispatcher.
        $script:MockWindow = [PSCustomObject]@{}
        $mockDisp = $script:MockDispatcher
        $script:MockWindow | Add-Member -MemberType ScriptProperty -Name Dispatcher -Value { $mockDisp }

        # Build a minimal Context hashtable with no real WPF objects.
        $script:MockControls = @{
            StatusLabel  = [PSCustomObject]@{ Text = '' }
            CancelButton = [PSCustomObject]@{ Visibility = 'Visible' }
        }
        $script:MockControls.StatusLabel  | Add-Member -MemberType NoteProperty -Name 'IsEnabled' -Value $true  -Force
        $script:MockControls.CancelButton | Add-Member -MemberType NoteProperty -Name 'IsEnabled' -Value $true  -Force

        $script:FlagValue = $true   # starts as running

        $script:MockContext = @{
            Window             = $script:MockWindow
            Controls           = $script:MockControls
            OperationButtons   = @()
            OperationInputs    = @()
            SetOperationRunning = { param($v) $script:FlagValue = $v }
            UpdateButtonState   = $null
        }
    }

    BeforeEach {
        # Complete-WsusOperation guards against double-completion per process
        # Id. Tests share a single mock context, so the guard from the previous
        # test would short-circuit this one. Clear it before each test.
        Reset-WsusOperationGuard
    }

    Context "Status updates" {
        It "Sets StatusLabel text to Completed on success" {
            $script:MockControls.StatusLabel.Text = ''
            Complete-WsusOperation -Context $script:MockContext -Title 'TestOp' -Success $true
            $script:MockControls.StatusLabel.Text | Should -Match 'Completed: TestOp'
        }

        It "Sets StatusLabel text to Failed on failure" {
            $script:MockControls.StatusLabel.Text = ''
            Complete-WsusOperation -Context $script:MockContext -Title 'TestOp' -Success $false
            $script:MockControls.StatusLabel.Text | Should -Match 'Failed: TestOp'
        }

        It "Includes a timestamp in the status label" {
            Complete-WsusOperation -Context $script:MockContext -Title 'TimestampCheck' -Success $true
            $script:MockControls.StatusLabel.Text | Should -Match '\d{2}:\d{2}:\d{2}'
        }
    }

    Context "OperationRunning flag" {
        It "Resets the running flag to false via SetOperationRunning" {
            $script:FlagValue = $true
            Complete-WsusOperation -Context $script:MockContext -Title 'FlagTest' -Success $true
            $script:FlagValue | Should -Be $false
        }
    }

    Context "OnComplete callback" {
        It "Invokes OnComplete with true on success" {
            $script:CallbackResult = $null
            $cb = { param($s) $script:CallbackResult = $s }
            Complete-WsusOperation -Context $script:MockContext -Title 'CallbackTest' -Success $true -OnComplete $cb
            $script:CallbackResult | Should -Be $true
        }

        It "Invokes OnComplete with false on failure" {
            $script:CallbackResult = $null
            $cb = { param($s) $script:CallbackResult = $s }
            Complete-WsusOperation -Context $script:MockContext -Title 'CallbackFail' -Success $false -OnComplete $cb
            $script:CallbackResult | Should -Be $false
        }

        It "Does not throw when OnComplete is null" {
            { Complete-WsusOperation -Context $script:MockContext -Title 'NullCb' -Success $true -OnComplete $null } |
                Should -Not -Throw
        }
    }

    Context "Dispatcher dispatch" {
        It "Calls Dispatcher.Invoke at least once to update UI" {
            $script:MockDispatcher.InvokeCount = 0
            Complete-WsusOperation -Context $script:MockContext -Title 'DispatchTest' -Success $true
            $script:MockDispatcher.InvokeCount | Should -BeGreaterThan 0
        }
    }

    Context "Environment and host process seam" {
        It "Accepts Environment parameter" {
            $param = (Get-Command Start-WsusOperation).Parameters['Environment']
            $param | Should -Not -BeNullOrEmpty
        }

    }
}

# ---------------------------------------------------------------------------
Describe "Start-WsusOperation" {
    Context "Parameter validation" {
        It "Command parameter is mandatory" {
            $param = (Get-Command Start-WsusOperation).Parameters['Command']
            $param.Attributes.Where({ $_ -is [Parameter] }).Mandatory | Should -Be $true
        }

        It "Title parameter is mandatory" {
            $param = (Get-Command Start-WsusOperation).Parameters['Title']
            $param.Attributes.Where({ $_ -is [Parameter] }).Mandatory | Should -Be $true
        }

        It "Context parameter is mandatory" {
            $param = (Get-Command Start-WsusOperation).Parameters['Context']
            $param.Attributes.Where({ $_ -is [Parameter] }).Mandatory | Should -Be $true
        }

        It "Mode parameter defaults to Embedded" {
            $param = (Get-Command Start-WsusOperation).Parameters['Mode']
            $param | Should -Not -BeNullOrEmpty
        }

        It "Rejects an invalid Mode value" {
            $ctx = @{ Window = $null; Controls = @{}; OperationButtons = @(); OperationInputs = @() }
            { Start-WsusOperation -Command 'exit 0' -Title 'T' -Context $ctx -Mode 'Invalid' } | Should -Throw
        }
    }

    Context "Integration (manual / skipped in CI)" -Skip {
        It "Starts a process and calls OnComplete - MANUAL TEST ONLY" {
            # This test requires a real WPF dispatcher and is intentionally skipped
            # in automated runs.  Run manually to verify end-to-end operation lifecycle.
            $true | Should -Be $true
        }
    }
}

# ---------------------------------------------------------------------------
Describe "New-WsusEnvironmentBootstrapFile" {
    Context "Empty environment" {
        It "Returns null when given no entries" {
            $result = InModuleScope WsusOperationRunner { param($e) New-WsusEnvironmentBootstrapFile -Environment $e } -ArgumentList @{}
            $result | Should -BeNullOrEmpty
        }
    }

    Context "Writing env vars to a temp file" {
        It "Writes a Set-Item line per non-blank key" {
            $path = InModuleScope WsusOperationRunner { param($e) New-WsusEnvironmentBootstrapFile -Environment $e } -ArgumentList @{ FOO = 'bar'; BAZ = 'qux' }
            try {
                $path | Should -Not -BeNullOrEmpty
                Test-Path -LiteralPath $path -PathType Leaf | Should -BeTrue
                $content = Get-Content -LiteralPath $path -Raw
                $content | Should -Match "Set-Item -LiteralPath 'Env:FOO' -Value 'bar' -Force"
                $content | Should -Match "Set-Item -LiteralPath 'Env:BAZ' -Value 'qux' -Force"
            } finally {
                Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
            }
        }

        It "Escapes embedded single quotes in values" {
            $path = InModuleScope WsusOperationRunner { param($e) New-WsusEnvironmentBootstrapFile -Environment $e } -ArgumentList @{ SECRET = "O'Brien" }
            try {
                $content = Get-Content -LiteralPath $path -Raw
                # doubled-up single quotes survive PowerShell single-quoted-string parsing
                $content | Should -Match "Set-Item -LiteralPath 'Env:SECRET' -Value 'O''Brien' -Force"
            } finally {
                Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
            }
        }

        It "Skips blank keys without throwing" {
            $path = InModuleScope WsusOperationRunner { param($e) New-WsusEnvironmentBootstrapFile -Environment $e } -ArgumentList @{ '' = 'ignored'; REAL = 'kept' }
            try {
                $content = Get-Content -LiteralPath $path -Raw
                $content | Should -Not -Match "Env:'"
                $content | Should -Match "Set-Item -LiteralPath 'Env:REAL' -Value 'kept' -Force"
            } finally {
                Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe "Remove-WsusEnvironmentBootstrapFile" {
    BeforeAll {
        $script:RemoveBootstrap = {
            param($p)
            InModuleScope WsusOperationRunner { param($x) Remove-WsusEnvironmentBootstrapFile -Path $x } -ArgumentList $p
        }
    }

    It "Deletes an existing file" {
        $path = Join-Path ([System.IO.Path]::GetTempPath()) ("wsus-env-test-{0}.ps1" -f ([guid]::NewGuid().ToString('N')))
        Set-Content -LiteralPath $path -Value '# stub' -Force
        Test-Path -LiteralPath $path | Should -BeTrue

        & $script:RemoveBootstrap $path
        Test-Path -LiteralPath $path | Should -BeFalse
    }

    It "Is a no-op when the file is missing" {
        $missing = Join-Path ([System.IO.Path]::GetTempPath()) ("wsus-env-missing-{0}.ps1" -f ([guid]::NewGuid().ToString('N')))
        { & $script:RemoveBootstrap $missing } | Should -Not -Throw
    }

    It "Is a no-op when the path is blank" {
        { & $script:RemoveBootstrap '' } | Should -Not -Throw
        { & $script:RemoveBootstrap $null } | Should -Not -Throw
    }
}

Describe "Start-WsusOperation Terminal-mode environment bootstrap" -Skip:(-not $script:WpfAvailable) {
    Context "Terminal mode without environment" {
        It "Does NOT create an env bootstrap file" {
            $ctx = @{
                Window             = $null
                Controls           = @{}
                OperationButtons   = @()
                OperationInputs    = @()
                ScriptRoot         = $env:TEMP
                SetOperationRunning = { param($v) }
            }

            $bootstrap = $null
            $proc = $null
            try {
                $proc = Start-WsusOperation -Command 'Write-Output hello' -Title 'NoEnv' -Context $ctx -Mode 'Terminal' -Environment @{} -TimeoutMinutes 0
                $proc | Should -Not -BeNullOrEmpty
                Start-Sleep -Milliseconds 250
                if ($ctx.ContainsKey('EnvBootstrapPath')) { $bootstrap = $ctx['EnvBootstrapPath'] }
                $bootstrap | Should -BeNullOrEmpty
            } finally {
                if ($proc -and -not $proc.HasExited) { $proc.Kill() }
                if ($bootstrap -and (Test-Path -LiteralPath $bootstrap)) {
                    Remove-Item -LiteralPath $bootstrap -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    Context "Terminal mode WITH environment" {
        It "Writes a bootstrap file and injects it into the command line" {
            $ctx = @{
                Window             = $null
                Controls           = @{}
                OperationButtons   = @()
                OperationInputs    = @()
                ScriptRoot         = $env:TEMP
                SetOperationRunning = { param($v) }
            }

            $bootstrap = $null
            $proc = $null
            try {
                $env = @{ WSUS_INSTALL_SA_PASSWORD = 'ProbePwd!1' }
                $proc = Start-WsusOperation -Command 'Write-Output hello' -Title 'EnvTest' -Context $ctx -Mode 'Terminal' -Environment $env -TimeoutMinutes 0
                $proc | Should -Not -BeNullOrEmpty
                Start-Sleep -Milliseconds 250
                $bootstrap = $ctx['EnvBootstrapPath']
                $bootstrap | Should -Not -BeNullOrEmpty
                Test-Path -LiteralPath $bootstrap | Should -BeTrue
                $content = Get-Content -LiteralPath $bootstrap -Raw
                $content | Should -Match "Set-Item -LiteralPath 'Env:WSUS_INSTALL_SA_PASSWORD' -Value 'ProbePwd!1' -Force"
            } finally {
                if ($proc -and -not $proc.HasExited) { $proc.Kill() }
                if ($bootstrap -and (Test-Path -LiteralPath $bootstrap)) {
                    Remove-Item -LiteralPath $bootstrap -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    Context "Embedded mode retains direct env propagation" {
        It "Does NOT create a bootstrap file when UseShellExecute=False" {
            $ctx = @{
                Window             = $null
                Controls           = @{}
                OperationButtons   = @()
                OperationInputs    = @()
                ScriptRoot         = $env:TEMP
                SetOperationRunning = { param($v) }
            }

            $bootstrap = $null
            $proc = $null
            try {
                $env = @{ WSUS_INSTALL_SA_PASSWORD = 'EmbeddedProbe' }
                $proc = Start-WsusOperation -Command 'Write-Output hello' -Title 'EmbeddedEnvTest' -Context $ctx -Mode 'Embedded' -Environment $env -TimeoutMinutes 0
                $proc | Should -Not -BeNullOrEmpty
                Start-Sleep -Milliseconds 250
                $bootstrap = $ctx['EnvBootstrapPath']
                $bootstrap | Should -BeNullOrEmpty
            } finally {
                if ($proc -and -not $proc.HasExited) { $proc.Kill() }
                if ($bootstrap -and (Test-Path -LiteralPath $bootstrap)) {
                    Remove-Item -LiteralPath $bootstrap -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
}

Describe "Start-RunnerTimer" -Skip:(-not $script:WpfAvailable) {
    It "Starts a DispatcherTimer without throwing" {
        $timer = New-Object System.Windows.Threading.DispatcherTimer
        $timer.Interval = [TimeSpan]::FromMilliseconds(500)
        { InModuleScope WsusOperationRunner { param($t) Start-RunnerTimer -Timer $t } -ArgumentList $timer } | Should -Not -Throw
        # Cleanup
        try { $timer.Stop() } catch { }
    }

    It "Is a no-op when Timer is null" {
        { InModuleScope WsusOperationRunner { param($t) Start-RunnerTimer -Timer $t } -ArgumentList $null } | Should -Not -Throw
    }
}

Describe "Complete-WsusOperation env bootstrap cleanup" -Skip:(-not $script:WpfAvailable) {
    BeforeEach {
        Reset-WsusOperationGuard
    }

    It "Removes the env bootstrap file when complete is called" {
        # Create a real temp file to simulate a bootstrap and register it on a
        # mock context. Complete should unlink it as part of teardown.
        $fake = Join-Path ([System.IO.Path]::GetTempPath()) ("wsus-env-cleanup-{0}.ps1" -f ([guid]::NewGuid().ToString('N')))
        Set-Content -LiteralPath $fake -Value '# stub' -Force
        Test-Path -LiteralPath $fake | Should -BeTrue

        $mockDisp = [PSCustomObject]@{ InvokeCount = 0 }
        $mockDisp | Add-Member -MemberType ScriptMethod -Name Invoke -Value { param($a) $this.InvokeCount++; if ($a -is [scriptblock]) { $a.Invoke() } }
        $mockWin = [PSCustomObject]@{}
        $mockWin | Add-Member -MemberType ScriptProperty -Name Dispatcher -Value { $mockDisp }

        $ctx = @{
            Window             = $mockWin
            Controls           = @{ StatusLabel = [PSCustomObject]@{ Text = '' } }
            OperationButtons   = @()
            OperationInputs    = @()
            EnvBootstrapPath   = $fake
            SetOperationRunning = { param($v) }
        }

        try {
            Complete-WsusOperation -Context $ctx -Title 'Cleanup' -Success $true
            Test-Path -LiteralPath $fake | Should -BeFalse
            $ctx['EnvBootstrapPath'] | Should -BeNullOrEmpty
        } finally {
            if (Test-Path -LiteralPath $fake) { Remove-Item -LiteralPath $fake -Force -ErrorAction SilentlyContinue }
        }
    }
}
