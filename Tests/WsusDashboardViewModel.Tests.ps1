#Requires -Version 5.1
#Requires -Modules Pester

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\Modules\WsusTestHarness.psm1') -Force -DisableNameChecking -WarningAction SilentlyContinue
    $script:RepoRoot = Resolve-WsusTestRepoRoot -StartPath $PSScriptRoot
    Import-WsusTestModule -ModuleName 'WsusDashboardViewModel' -RepoRoot $script:RepoRoot
}

AfterAll {
    Remove-WsusTestModule -ModuleName 'WsusDashboardViewModel'
}

Describe 'WsusDashboardViewModel module' {
    It 'exports the dashboard view-model factory' {
        Get-Command New-WsusDashboardViewModel -Module WsusDashboardViewModel | Should -Not -BeNullOrEmpty
    }
}

Describe 'New-WsusDashboardViewModel' {
    It 'builds the not-installed cards without requiring dashboard data' {
        $vm = New-WsusDashboardViewModel -WsusInstalled:$false -ServerMode 'Offline'

        $vm.PSObject.TypeNames[0] | Should -Be 'Wsus.DashboardViewModel'
        $vm.ServerMode.Label | Should -Be 'Offline'
        $vm.ServerMode.Online | Should -BeFalse
        $vm.Cards.Services.Value | Should -Be 'Not Installed'
        $vm.Cards.Services.Status | Should -Be 'Fail'
        $vm.Cards.Database.Value | Should -Be 'N/A'
        $vm.Cards.Database.Status | Should -Be 'Skip'
        $vm.Cards.Task.Value | Should -Be 'N/A'
        $vm.Cards.Task.Status | Should -Be 'Skip'
    }

    It 'builds passing online cards for fully healthy dashboard data' {
        $data = [pscustomobject]@{
            Services = [pscustomobject]@{ Running = 3; Names = @('WsusService', 'W3SVC', 'BITS') }
            DatabaseSizeGB = 6.5
            DiskFreeGB = 50
            TaskStatus = 'Ready'
        }
        $health = [pscustomobject]@{ Score = 96; Grade = 'A' }

        $vm = New-WsusDashboardViewModel -WsusInstalled:$true -ServerMode 'Online' -DashboardData $data -Health $health -ContentPath 'D:\WSUS' -SqlInstance '.\SQLEXPRESS' -ExportRoot 'E:\Export' -LogPath 'D:\WSUS\Logs'

        $vm.ServerMode.Online | Should -BeTrue
        $vm.Cards.Services.Value | Should -Be 'All Running'
        $vm.Cards.Services.Sub | Should -Be 'WsusService, W3SVC, BITS'
        $vm.Cards.Services.Status | Should -Be 'Pass'
        $vm.Cards.Database.Value | Should -Be '6.5 / 10 GB'
        $vm.Cards.Database.Status | Should -Be 'Pass'
        $vm.Cards.Disk.Value | Should -Be '50 GB'
        $vm.Cards.Disk.Status | Should -Be 'Pass'
        $vm.Cards.Task.Status | Should -Be 'Pass'
        $vm.Health.Score | Should -Be 96
        $vm.Health.Available | Should -BeTrue
        $vm.Configuration.ContentPath | Should -Be 'D:\WSUS'
        $vm.Configuration.SqlInstance | Should -Be '.\SQLEXPRESS'
    }

    It 'marks partial service availability as a warning and stopped services as a failure' {
        $partialData = [pscustomobject]@{
            Services = [pscustomobject]@{ Running = 1; Names = @('BITS') }
            DatabaseSizeGB = 1
            DiskFreeGB = 100
            TaskStatus = 'Disabled'
        }
        $stoppedData = [pscustomobject]@{
            Services = [pscustomobject]@{ Running = 0; Names = @() }
            DatabaseSizeGB = 1
            DiskFreeGB = 100
            TaskStatus = 'Disabled'
        }

        $partial = New-WsusDashboardViewModel -WsusInstalled:$true -ServerMode 'Online' -DashboardData $partialData
        $stopped = New-WsusDashboardViewModel -WsusInstalled:$true -ServerMode 'Online' -DashboardData $stoppedData

        $partial.Cards.Services.Value | Should -Be '1/3'
        $partial.Cards.Services.Sub | Should -Be 'BITS'
        $partial.Cards.Services.Status | Should -Be 'Warn'
        $stopped.Cards.Services.Value | Should -Be '0/3'
        $stopped.Cards.Services.Sub | Should -Be 'Stopped'
        $stopped.Cards.Services.Status | Should -Be 'Fail'
    }

    It 'applies database size thresholds at healthy, warning, and critical boundaries' {
        $healthy = New-WsusDashboardViewModel -WsusInstalled:$true -ServerMode 'Online' -DashboardData ([pscustomobject]@{ Services = [pscustomobject]@{ Running = 3; Names = @() }; DatabaseSizeGB = 6.99; DiskFreeGB = 100; TaskStatus = 'Ready' })
        $warning = New-WsusDashboardViewModel -WsusInstalled:$true -ServerMode 'Online' -DashboardData ([pscustomobject]@{ Services = [pscustomobject]@{ Running = 3; Names = @() }; DatabaseSizeGB = 7; DiskFreeGB = 100; TaskStatus = 'Ready' })
        $critical = New-WsusDashboardViewModel -WsusInstalled:$true -ServerMode 'Online' -DashboardData ([pscustomobject]@{ Services = [pscustomobject]@{ Running = 3; Names = @() }; DatabaseSizeGB = 9; DiskFreeGB = 100; TaskStatus = 'Ready' })
        $offline = New-WsusDashboardViewModel -WsusInstalled:$true -ServerMode 'Online' -DashboardData ([pscustomobject]@{ Services = [pscustomobject]@{ Running = 3; Names = @() }; DatabaseSizeGB = -1; DiskFreeGB = 100; TaskStatus = 'Ready' })

        $healthy.Cards.Database.Sub | Should -Be 'Healthy'
        $healthy.Cards.Database.Status | Should -Be 'Pass'
        $warning.Cards.Database.Sub | Should -Be 'Warning'
        $warning.Cards.Database.Status | Should -Be 'Warn'
        $critical.Cards.Database.Sub | Should -Be 'Critical!'
        $critical.Cards.Database.Status | Should -Be 'Fail'
        $offline.Cards.Database.Value | Should -Be 'Offline'
        $offline.Cards.Database.Status | Should -Be 'Warn'
    }

    It 'applies disk free space thresholds at pass, warn, and fail boundaries' {
        $pass = New-WsusDashboardViewModel -WsusInstalled:$true -ServerMode 'Online' -DashboardData ([pscustomobject]@{ Services = [pscustomobject]@{ Running = 3; Names = @() }; DatabaseSizeGB = 1; DiskFreeGB = 50; TaskStatus = 'Ready' })
        $warn = New-WsusDashboardViewModel -WsusInstalled:$true -ServerMode 'Online' -DashboardData ([pscustomobject]@{ Services = [pscustomobject]@{ Running = 3; Names = @() }; DatabaseSizeGB = 1; DiskFreeGB = 10; TaskStatus = 'Ready' })
        $fail = New-WsusDashboardViewModel -WsusInstalled:$true -ServerMode 'Online' -DashboardData ([pscustomobject]@{ Services = [pscustomobject]@{ Running = 3; Names = @() }; DatabaseSizeGB = 1; DiskFreeGB = 9.99; TaskStatus = 'Ready' })

        $pass.Cards.Disk.Sub | Should -Be 'OK'
        $pass.Cards.Disk.Status | Should -Be 'Pass'
        $warn.Cards.Disk.Sub | Should -Be 'Low'
        $warn.Cards.Disk.Status | Should -Be 'Warn'
        $fail.Cards.Disk.Sub | Should -Be 'Critical!'
        $fail.Cards.Disk.Status | Should -Be 'Fail'
    }

    It 'labels manual server mode overrides and uses an unavailable health fallback' {
        $vm = New-WsusDashboardViewModel -WsusInstalled:$true -ServerMode 'Offline' -ServerModeOverridden:$true

        $vm.ServerMode.Label | Should -Be 'Offline (Manual)'
        $vm.ServerMode.Online | Should -BeFalse
        $vm.Health.Score | Should -Be -1
        $vm.Health.Grade | Should -Be 'Unknown'
        $vm.Health.Available | Should -BeFalse
    }
}
