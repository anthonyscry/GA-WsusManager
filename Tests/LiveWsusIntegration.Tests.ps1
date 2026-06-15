#Requires -Modules Pester
<#
.SYNOPSIS
    Live WSUS integration tests for lab or production-like validation.
.DESCRIPTION
    Opt-in tests for a real WSUS host. Set WSUS_LIVE_INTEGRATION=1.
    Optional variables: WSUS_LIVE_SERVER, WSUS_LIVE_USERNAME, WSUS_LIVE_PASSWORD,
    WSUS_LIVE_SQL_INSTANCE, WSUS_LIVE_CONTENT_PATH.
#>

BeforeDiscovery {
    $script:LiveDiscoveryEnabled = ($env:WSUS_LIVE_INTEGRATION -eq '1')
    $script:LiveSqlDiscoveryEnabled = ($env:WSUS_LIVE_INTEGRATION -eq '1' -and -not [string]::IsNullOrWhiteSpace($env:WSUS_LIVE_SQL_INSTANCE))
}

BeforeAll {
    $script:LiveEnabled = ($env:WSUS_LIVE_INTEGRATION -eq '1')
    $script:TargetServer = if ($env:WSUS_LIVE_SERVER) { $env:WSUS_LIVE_SERVER } else { 'MS02' }
    $script:SqlInstance = $env:WSUS_LIVE_SQL_INSTANCE
    $script:ContentPath = if ($env:WSUS_LIVE_CONTENT_PATH) { $env:WSUS_LIVE_CONTENT_PATH } else { 'C:\WSUS' }
    $script:Credential = $null

    if ($env:WSUS_LIVE_USERNAME -and $env:WSUS_LIVE_PASSWORD) {
        $networkCredential = [System.Net.NetworkCredential]::new($env:WSUS_LIVE_USERNAME, $env:WSUS_LIVE_PASSWORD)
        $script:Credential = [pscredential]::new($env:WSUS_LIVE_USERNAME, $networkCredential.SecurePassword)
    }

    function Invoke-LiveWsusCommand {
        param([Parameter(Mandatory)][scriptblock]$ScriptBlock)

        $params = @{ ComputerName = $script:TargetServer; ScriptBlock = $ScriptBlock }
        if ($script:Credential) { $params.Credential = $script:Credential }
        Invoke-Command @params
    }
}

Describe 'Live WSUS integration checks' -Tag 'Integration', 'LiveWSUS' {
    It 'finds the required WSUS Windows services on the target host' -Skip:(-not $script:LiveDiscoveryEnabled) {
        $services = Invoke-LiveWsusCommand -ScriptBlock {
            Get-Service -Name 'WSUSService', 'W3SVC', 'bits' -ErrorAction SilentlyContinue |
                Select-Object Name, @{ Name = 'Status'; Expression = { $_.Status.ToString() } }, StartType
        }

        ($services | Where-Object Name -eq 'WSUSService').Status | Should -Be 'Running'
        ($services | Where-Object Name -eq 'W3SVC').Status | Should -Be 'Running'
        ($services | Where-Object Name -eq 'bits') | Should -Not -BeNullOrEmpty
    }

    It 'can query SUSDB size through the configured SQL instance' -Skip:(-not $script:LiveSqlDiscoveryEnabled) {
        $size = Invoke-LiveWsusCommand -ScriptBlock {
            $query = "SELECT CAST(SUM(size)*8.0/1024/1024 AS DECIMAL(10,2)) AS SizeGB FROM sys.master_files WHERE database_id=DB_ID('SUSDB')"
            if (Get-Command Invoke-Sqlcmd -ErrorAction SilentlyContinue) {
                return (Invoke-Sqlcmd -ServerInstance $using:SqlInstance -Database master -Query $query -QueryTimeout 30 -ErrorAction Stop).SizeGB
            }
            if (Get-Command sqlcmd.exe -ErrorAction SilentlyContinue) {
                $raw = & sqlcmd.exe -S $using:SqlInstance -d master -Q $query -h -1 -W
                return ($raw | Where-Object { $_ -match '^\s*\d+(\.\d+)?\s*$' } | Select-Object -First 1).Trim()
            }
            throw 'Neither Invoke-Sqlcmd nor sqlcmd.exe is available on the live WSUS host.'
        }

        [double]$size | Should -BeGreaterOrEqual 0
    }

    It 'has either SQL or WID database service installed' -Skip:(-not $script:LiveDiscoveryEnabled) {
        $databaseServices = Invoke-LiveWsusCommand -ScriptBlock {
            Get-Service -Name 'MSSQL$SQLEXPRESS', 'MSSQLSERVER', 'MSSQL$MICROSOFT##WID', 'WIDWriter' -ErrorAction SilentlyContinue |
                Select-Object Name, @{ Name = 'Status'; Expression = { $_.Status.ToString() } }
        }

        @($databaseServices).Count | Should -BeGreaterThan 0
    }

    It 'keeps WSUS firewall rules discoverable' -Skip:(-not $script:LiveDiscoveryEnabled) {
        $rules = Invoke-LiveWsusCommand -ScriptBlock {
            Get-NetFirewallRule -DisplayName '*WSUS*' -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty DisplayName
        }

        @($rules).Count | Should -BeGreaterThan 0
    }

    It 'grants read access on the WSUS content root to expected service principals' -Skip:(-not $script:LiveDiscoveryEnabled) {
        $acl = Invoke-LiveWsusCommand -ScriptBlock {
            if (-not (Test-Path $using:ContentPath)) {
                throw "Content path not found: $using:ContentPath"
            }
            (Get-Acl -Path $using:ContentPath).Access | Select-Object IdentityReference, FileSystemRights
        }

        @($acl.IdentityReference.Value) | Should -Contain 'NT AUTHORITY\NETWORK SERVICE'
    }
}
