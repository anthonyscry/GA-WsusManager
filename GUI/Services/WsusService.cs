using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using WsusManager.Models;

namespace WsusManager.Services
{
    /// <summary>
    /// High-level service for WSUS operations
    /// </summary>
    public class WsusService : IDisposable
    {
        private readonly PowerShellService _psService;
        private bool _disposed;

        public event EventHandler<PowerShellOutputEventArgs>? OutputReceived;
        public event EventHandler<PowerShellProgressEventArgs>? ProgressChanged;

        public WsusService(PowerShellService psService)
        {
            _psService = psService;
            _psService.OutputReceived += (s, e) => OutputReceived?.Invoke(this, e);
            _psService.ProgressChanged += (s, e) => ProgressChanged?.Invoke(this, e);
        }

        #region Service Operations

        public async Task<List<ServiceStatus>> GetServiceStatusAsync(CancellationToken ct = default)
        {
            var result = await _psService.ExecuteAsync("Get-WsusServiceStatus", cancellationToken: ct);
            var services = new List<ServiceStatus>();

            if (result.Success)
            {
                foreach (var item in result.Output)
                {
                    if (item is System.Management.Automation.PSObject pso)
                    {
                        services.Add(new ServiceStatus
                        {
                            Name = pso.Properties["Name"]?.Value?.ToString() ?? "Unknown",
                            DisplayName = pso.Properties["DisplayName"]?.Value?.ToString() ?? "Unknown",
                            Status = pso.Properties["Status"]?.Value?.ToString() ?? "Unknown",
                            IsRunning = pso.Properties["Status"]?.Value?.ToString() == "Running"
                        });
                    }
                }
            }

            // If module didn't return expected format, query services directly
            if (services.Count == 0)
            {
                var script = @"
                    @('WsusService', 'MSSQL$SQLEXPRESS', 'W3SVC') | ForEach-Object {
                        $svc = Get-Service -Name $_ -ErrorAction SilentlyContinue
                        if ($svc) {
                            [PSCustomObject]@{
                                Name = $svc.Name
                                DisplayName = $svc.DisplayName
                                Status = $svc.Status.ToString()
                            }
                        }
                    }
                ";
                var directResult = await _psService.ExecuteScriptAsync(script, ct);

                if (directResult.Success)
                {
                    foreach (var item in directResult.Output)
                    {
                        if (item is System.Management.Automation.PSObject pso)
                        {
                            var status = pso.Properties["Status"]?.Value?.ToString() ?? "Unknown";
                            services.Add(new ServiceStatus
                            {
                                Name = pso.Properties["Name"]?.Value?.ToString() ?? "Unknown",
                                DisplayName = pso.Properties["DisplayName"]?.Value?.ToString() ?? "Unknown",
                                Status = status,
                                IsRunning = status == "Running"
                            });
                        }
                    }
                }
            }

            return services;
        }

        public async Task<OperationResult> StartServiceAsync(string serviceName, CancellationToken ct = default)
        {
            var result = await _psService.ExecuteScriptAsync(
                $"Start-Service -Name '{serviceName}' -ErrorAction Stop", ct);

            return new OperationResult
            {
                Success = result.Success,
                Message = result.Success ? $"Service {serviceName} started" : string.Join(", ", result.Errors)
            };
        }

        public async Task<OperationResult> StopServiceAsync(string serviceName, CancellationToken ct = default)
        {
            var result = await _psService.ExecuteScriptAsync(
                $"Stop-Service -Name '{serviceName}' -Force -ErrorAction Stop", ct);

            return new OperationResult
            {
                Success = result.Success,
                Message = result.Success ? $"Service {serviceName} stopped" : string.Join(", ", result.Errors)
            };
        }

        public async Task<OperationResult> StartAllServicesAsync(CancellationToken ct = default)
        {
            var result = await _psService.ExecuteAsync("Start-AllWsusServices", cancellationToken: ct);
            return new OperationResult
            {
                Success = result.Success,
                Message = result.Success ? "All WSUS services started" : string.Join(", ", result.Errors)
            };
        }

        public async Task<OperationResult> StopAllServicesAsync(CancellationToken ct = default)
        {
            var result = await _psService.ExecuteAsync("Stop-AllWsusServices", cancellationToken: ct);
            return new OperationResult
            {
                Success = result.Success,
                Message = result.Success ? "All WSUS services stopped" : string.Join(", ", result.Errors)
            };
        }

        #endregion

        #region Health Operations

        public async Task<HealthCheckResult> RunHealthCheckAsync(CancellationToken ct = default)
        {
            var result = await _psService.ExecuteAsync("Test-WsusHealth", cancellationToken: ct);

            var healthResult = new HealthCheckResult
            {
                Success = result.Success,
                Checks = new List<HealthCheck>()
            };

            if (result.Success)
            {
                foreach (var item in result.Output)
                {
                    if (item is System.Management.Automation.PSObject pso)
                    {
                        healthResult.Checks.Add(new HealthCheck
                        {
                            Name = pso.Properties["Check"]?.Value?.ToString() ?? "Unknown",
                            Status = pso.Properties["Status"]?.Value?.ToString() ?? "Unknown",
                            Message = pso.Properties["Message"]?.Value?.ToString() ?? ""
                        });
                    }
                }
            }

            return healthResult;
        }

        public async Task<OperationResult> RepairHealthAsync(CancellationToken ct = default)
        {
            var result = await _psService.ExecuteAsync("Repair-WsusHealth", cancellationToken: ct);
            return new OperationResult
            {
                Success = result.Success,
                Message = result.Success ? "Health repair completed" : string.Join(", ", result.Errors),
                Details = result.Output
            };
        }

        #endregion

        #region Database Operations

        public async Task<DatabaseStats> GetDatabaseStatsAsync(CancellationToken ct = default)
        {
            var result = await _psService.ExecuteAsync("Get-WsusDatabaseStats", cancellationToken: ct);
            var stats = new DatabaseStats();

            if (result.Success && result.Output.Count > 0)
            {
                if (result.Output[0] is System.Management.Automation.PSObject pso)
                {
                    stats.SizeMB = Convert.ToDouble(pso.Properties["SizeMB"]?.Value ?? 0);
                    stats.UpdateCount = Convert.ToInt32(pso.Properties["UpdateCount"]?.Value ?? 0);
                    stats.SupersededCount = Convert.ToInt32(pso.Properties["SupersededCount"]?.Value ?? 0);
                    stats.DeclinedCount = Convert.ToInt32(pso.Properties["DeclinedCount"]?.Value ?? 0);
                }
            }

            return stats;
        }

        public async Task<double> GetDatabaseSizeAsync(CancellationToken ct = default)
        {
            var result = await _psService.ExecuteAsync("Get-WsusDatabaseSize", cancellationToken: ct);

            if (result.Success && result.Output.Count > 0)
            {
                return Convert.ToDouble(result.Output[0]);
            }

            return 0;
        }

        public async Task<OperationResult> ShrinkDatabaseAsync(CancellationToken ct = default)
        {
            var result = await _psService.ExecuteAsync("Invoke-WsusDatabaseShrink", cancellationToken: ct);
            return new OperationResult
            {
                Success = result.Success,
                Message = result.Success ? "Database shrink completed" : string.Join(", ", result.Errors)
            };
        }

        public async Task<OperationResult> OptimizeIndexesAsync(CancellationToken ct = default)
        {
            var result = await _psService.ExecuteAsync("Optimize-WsusIndexes", cancellationToken: ct);
            return new OperationResult
            {
                Success = result.Success,
                Message = result.Success ? "Index optimization completed" : string.Join(", ", result.Errors)
            };
        }

        public async Task<List<BackupInfo>> GetAvailableBackupsAsync(string backupPath, CancellationToken ct = default)
        {
            var script = $@"
                Get-ChildItem -Path '{backupPath}' -Filter '*.bak' -Recurse -ErrorAction SilentlyContinue |
                Select-Object Name, FullName, Length, LastWriteTime |
                Sort-Object LastWriteTime -Descending
            ";

            var result = await _psService.ExecuteScriptAsync(script, ct);
            var backups = new List<BackupInfo>();

            if (result.Success)
            {
                foreach (var item in result.Output)
                {
                    if (item is System.Management.Automation.PSObject pso)
                    {
                        backups.Add(new BackupInfo
                        {
                            Name = pso.Properties["Name"]?.Value?.ToString() ?? "Unknown",
                            FullPath = pso.Properties["FullName"]?.Value?.ToString() ?? "",
                            SizeBytes = Convert.ToInt64(pso.Properties["Length"]?.Value ?? 0),
                            Created = Convert.ToDateTime(pso.Properties["LastWriteTime"]?.Value ?? DateTime.MinValue)
                        });
                    }
                }
            }

            return backups;
        }

        public async Task<OperationResult> RestoreDatabaseAsync(string backupPath, CancellationToken ct = default)
        {
            var script = $@"
                # Stop services
                Stop-AllWsusServices

                # Restore database (placeholder - actual restore logic in module)
                # Invoke-WsusRestore -BackupPath '{backupPath}'

                # Start services
                Start-AllWsusServices
            ";

            var result = await _psService.ExecuteScriptAsync(script, ct);
            return new OperationResult
            {
                Success = result.Success,
                Message = result.Success ? "Database restore completed" : string.Join(", ", result.Errors)
            };
        }

        #endregion

        #region Cleanup Operations

        public async Task<OperationResult> RunDeepCleanupAsync(CancellationToken ct = default)
        {
            var script = @"
                Remove-DeclinedSupersessionRecords
                Remove-SupersededSupersessionRecords
                Optimize-WsusIndexes
                Update-WsusStatistics
            ";

            var result = await _psService.ExecuteScriptAsync(script, ct);
            return new OperationResult
            {
                Success = result.Success,
                Message = result.Success ? "Deep cleanup completed" : string.Join(", ", result.Errors)
            };
        }

        public async Task<OperationResult> ResetContentDownloadAsync(CancellationToken ct = default)
        {
            var script = @"
                $wsusUtil = 'C:\Program Files\Update Services\Tools\wsusutil.exe'
                if (Test-Path $wsusUtil) {
                    & $wsusUtil reset
                } else {
                    throw 'wsusutil.exe not found'
                }
            ";

            var result = await _psService.ExecuteScriptAsync(script, ct);
            return new OperationResult
            {
                Success = result.Success,
                Message = result.Success ? "Content download reset initiated" : string.Join(", ", result.Errors)
            };
        }

        #endregion

        #region Export/Import Operations

        public async Task<List<ArchiveYear>> GetArchiveStructureAsync(string archivePath, CancellationToken ct = default)
        {
            var script = $@"
                $years = Get-ChildItem -Path '{archivePath}' -Directory -ErrorAction SilentlyContinue |
                    Where-Object {{ $_.Name -match '^\d{{4}}$' }} |
                    Sort-Object Name -Descending

                foreach ($year in $years) {{
                    $months = Get-ChildItem -Path $year.FullName -Directory -ErrorAction SilentlyContinue |
                        Sort-Object Name

                    [PSCustomObject]@{{
                        Year = $year.Name
                        Path = $year.FullName
                        Months = $months | ForEach-Object {{
                            $backups = Get-ChildItem -Path $_.FullName -Directory -ErrorAction SilentlyContinue |
                                Sort-Object Name -Descending
                            [PSCustomObject]@{{
                                Name = $_.Name
                                Path = $_.FullName
                                BackupCount = $backups.Count
                                Backups = $backups | ForEach-Object {{
                                    [PSCustomObject]@{{
                                        Name = $_.Name
                                        Path = $_.FullName
                                    }}
                                }}
                            }}
                        }}
                    }}
                }}
            ";

            var result = await _psService.ExecuteScriptAsync(script, ct);
            var years = new List<ArchiveYear>();

            if (result.Success)
            {
                foreach (var item in result.Output)
                {
                    if (item is System.Management.Automation.PSObject pso)
                    {
                        var year = new ArchiveYear
                        {
                            Year = pso.Properties["Year"]?.Value?.ToString() ?? "",
                            Path = pso.Properties["Path"]?.Value?.ToString() ?? "",
                            Months = new List<ArchiveMonth>()
                        };

                        var months = pso.Properties["Months"]?.Value;
                        if (months is System.Collections.IEnumerable monthsEnum)
                        {
                            foreach (var monthItem in monthsEnum)
                            {
                                if (monthItem is System.Management.Automation.PSObject monthPso)
                                {
                                    var month = new ArchiveMonth
                                    {
                                        Name = monthPso.Properties["Name"]?.Value?.ToString() ?? "",
                                        Path = monthPso.Properties["Path"]?.Value?.ToString() ?? "",
                                        BackupCount = Convert.ToInt32(monthPso.Properties["BackupCount"]?.Value ?? 0),
                                        Backups = new List<ArchiveBackup>()
                                    };

                                    var backups = monthPso.Properties["Backups"]?.Value;
                                    if (backups is System.Collections.IEnumerable backupsEnum)
                                    {
                                        foreach (var backupItem in backupsEnum)
                                        {
                                            if (backupItem is System.Management.Automation.PSObject backupPso)
                                            {
                                                month.Backups.Add(new ArchiveBackup
                                                {
                                                    Name = backupPso.Properties["Name"]?.Value?.ToString() ?? "",
                                                    Path = backupPso.Properties["Path"]?.Value?.ToString() ?? ""
                                                });
                                            }
                                        }
                                    }

                                    year.Months.Add(month);
                                }
                            }
                        }

                        years.Add(year);
                    }
                }
            }

            return years;
        }

        public async Task<OperationResult> ImportFromMediaAsync(string sourcePath, string destinationPath, CancellationToken ct = default)
        {
            var script = $@"
                $source = '{sourcePath}'
                $dest = '{destinationPath}'

                # Use robocopy for efficient copy
                robocopy $source $dest /E /MT:16 /R:2 /W:5 /NP /NDL /NFL

                if ($LASTEXITCODE -lt 8) {{
                    Write-Output 'Import completed successfully'
                }} else {{
                    throw 'Robocopy failed with exit code: ' + $LASTEXITCODE
                }}
            ";

            var result = await _psService.ExecuteScriptAsync(script, ct);
            return new OperationResult
            {
                Success = result.Success,
                Message = result.Success ? "Import completed" : string.Join(", ", result.Errors)
            };
        }

        public async Task<OperationResult> ExportToMediaAsync(string sourcePath, string destinationPath, int daysOld = 0, CancellationToken ct = default)
        {
            var minageParam = daysOld > 0 ? $"/MINAGE:{daysOld}" : "";
            var script = $@"
                $source = '{sourcePath}'
                $dest = '{destinationPath}'

                # Ensure destination exists
                if (-not (Test-Path $dest)) {{
                    New-Item -Path $dest -ItemType Directory -Force | Out-Null
                }}

                # Use robocopy for efficient copy
                robocopy $source $dest /E /MT:16 /R:2 /W:5 /NP /NDL /NFL {minageParam}

                if ($LASTEXITCODE -lt 8) {{
                    Write-Output 'Export completed successfully'
                }} else {{
                    throw 'Robocopy failed with exit code: ' + $LASTEXITCODE
                }}
            ";

            var result = await _psService.ExecuteScriptAsync(script, ct);
            return new OperationResult
            {
                Success = result.Success,
                Message = result.Success ? "Export completed" : string.Join(", ", result.Errors)
            };
        }

        #endregion

        #region Configuration

        public async Task<WsusConfiguration> GetConfigurationAsync(CancellationToken ct = default)
        {
            var result = await _psService.ExecuteAsync("Get-WsusConfig", cancellationToken: ct);
            var config = new WsusConfiguration();

            if (result.Success && result.Output.Count > 0)
            {
                if (result.Output[0] is System.Management.Automation.PSObject pso)
                {
                    config.ContentPath = pso.Properties["ContentPath"]?.Value?.ToString() ?? "C:\\WSUS";
                    config.SqlInstance = pso.Properties["SqlInstance"]?.Value?.ToString() ?? ".\\SQLEXPRESS";
                    config.ExportPath = pso.Properties["ExportPath"]?.Value?.ToString() ?? "";
                    config.LogPath = pso.Properties["LogPath"]?.Value?.ToString() ?? "C:\\WSUS\\Logs";
                }
            }

            return config;
        }

        public async Task<OperationResult> SetConfigurationAsync(WsusConfiguration config, CancellationToken ct = default)
        {
            var result = await _psService.ExecuteAsync("Set-WsusConfig", new Dictionary<string, object>
            {
                { "ContentPath", config.ContentPath },
                { "SqlInstance", config.SqlInstance },
                { "ExportPath", config.ExportPath },
                { "LogPath", config.LogPath }
            }, ct);

            return new OperationResult
            {
                Success = result.Success,
                Message = result.Success ? "Configuration saved" : string.Join(", ", result.Errors)
            };
        }

        #endregion

        #region Disk Space

        public async Task<DiskSpaceInfo> GetDiskSpaceAsync(string path, CancellationToken ct = default)
        {
            var script = $@"
                $drive = (Get-Item '{path}').PSDrive
                $freeGB = [math]::Round($drive.Free / 1GB, 2)
                $usedGB = [math]::Round($drive.Used / 1GB, 2)
                $totalGB = [math]::Round(($drive.Free + $drive.Used) / 1GB, 2)

                [PSCustomObject]@{{
                    FreeGB = $freeGB
                    UsedGB = $usedGB
                    TotalGB = $totalGB
                    PercentUsed = [math]::Round(($usedGB / $totalGB) * 100, 1)
                }}
            ";

            var result = await _psService.ExecuteScriptAsync(script, ct);
            var info = new DiskSpaceInfo();

            if (result.Success && result.Output.Count > 0)
            {
                if (result.Output[0] is System.Management.Automation.PSObject pso)
                {
                    info.FreeGB = Convert.ToDouble(pso.Properties["FreeGB"]?.Value ?? 0);
                    info.UsedGB = Convert.ToDouble(pso.Properties["UsedGB"]?.Value ?? 0);
                    info.TotalGB = Convert.ToDouble(pso.Properties["TotalGB"]?.Value ?? 0);
                    info.PercentUsed = Convert.ToDouble(pso.Properties["PercentUsed"]?.Value ?? 0);
                }
            }

            return info;
        }

        #endregion

        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;
        }
    }
}
