using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Threading;
using System.Threading.Tasks;

namespace WsusManager.Services
{
    /// <summary>
    /// Service for executing PowerShell commands and interacting with WSUS modules
    /// </summary>
    public class PowerShellService : IDisposable
    {
        private readonly string _modulesPath;
        private RunspacePool? _runspacePool;
        private bool _disposed;

        public event EventHandler<PowerShellOutputEventArgs>? OutputReceived;
        public event EventHandler<PowerShellProgressEventArgs>? ProgressChanged;

        public PowerShellService(string modulesPath)
        {
            _modulesPath = modulesPath;
            InitializeRunspacePool();
        }

        private void InitializeRunspacePool()
        {
            var iss = InitialSessionState.CreateDefault();

            // Import WSUS modules
            var moduleFiles = new[]
            {
                "WsusUtilities.psm1",
                "WsusDatabase.psm1",
                "WsusServices.psm1",
                "WsusHealth.psm1",
                "WsusExport.psm1",
                "WsusFirewall.psm1",
                "WsusPermissions.psm1",
                "WsusScheduledTask.psm1",
                "WsusConfig.psm1"
            };

            foreach (var module in moduleFiles)
            {
                var modulePath = Path.Combine(_modulesPath, module);
                if (File.Exists(modulePath))
                {
                    iss.ImportPSModule(new[] { modulePath });
                }
            }

            _runspacePool = RunspaceFactory.CreateRunspacePool(iss);
            _runspacePool.SetMinRunspaces(1);
            _runspacePool.SetMaxRunspaces(5);
            _runspacePool.Open();
        }

        /// <summary>
        /// Executes a PowerShell command asynchronously
        /// </summary>
        public async Task<PowerShellResult> ExecuteAsync(
            string command,
            Dictionary<string, object>? parameters = null,
            CancellationToken cancellationToken = default)
        {
            return await Task.Run(() => Execute(command, parameters, cancellationToken), cancellationToken);
        }

        /// <summary>
        /// Executes a PowerShell command
        /// </summary>
        public PowerShellResult Execute(
            string command,
            Dictionary<string, object>? parameters = null,
            CancellationToken cancellationToken = default)
        {
            if (_runspacePool == null)
                throw new InvalidOperationException("Runspace pool not initialized");

            using var ps = PowerShell.Create();
            ps.RunspacePool = _runspacePool;

            ps.AddCommand(command);

            if (parameters != null)
            {
                foreach (var param in parameters)
                {
                    ps.AddParameter(param.Key, param.Value);
                }
            }

            // Set up output streams
            var output = new List<object>();
            var errors = new List<string>();
            var warnings = new List<string>();
            var verbose = new List<string>();

            ps.Streams.Error.DataAdded += (s, e) =>
            {
                var error = ps.Streams.Error[e.Index];
                errors.Add(error.ToString());
                OnOutputReceived(error.ToString(), OutputType.Error);
            };

            ps.Streams.Warning.DataAdded += (s, e) =>
            {
                var warning = ps.Streams.Warning[e.Index];
                warnings.Add(warning.Message);
                OnOutputReceived(warning.Message, OutputType.Warning);
            };

            ps.Streams.Verbose.DataAdded += (s, e) =>
            {
                var verboseMsg = ps.Streams.Verbose[e.Index];
                verbose.Add(verboseMsg.Message);
                OnOutputReceived(verboseMsg.Message, OutputType.Verbose);
            };

            ps.Streams.Information.DataAdded += (s, e) =>
            {
                var info = ps.Streams.Information[e.Index];
                var message = info.MessageData?.ToString() ?? string.Empty;
                OnOutputReceived(message, OutputType.Information);
            };

            ps.Streams.Progress.DataAdded += (s, e) =>
            {
                var progress = ps.Streams.Progress[e.Index];
                OnProgressChanged(progress.Activity, progress.StatusDescription, progress.PercentComplete);
            };

            try
            {
                var results = ps.Invoke();

                foreach (var result in results)
                {
                    if (result?.BaseObject != null)
                    {
                        output.Add(result.BaseObject);
                        OnOutputReceived(result.ToString() ?? string.Empty, OutputType.Output);
                    }
                }

                return new PowerShellResult
                {
                    Success = !ps.HadErrors,
                    Output = output,
                    Errors = errors,
                    Warnings = warnings,
                    Verbose = verbose
                };
            }
            catch (Exception ex)
            {
                return new PowerShellResult
                {
                    Success = false,
                    Errors = new List<string> { ex.Message },
                    Output = new List<object>(),
                    Warnings = warnings,
                    Verbose = verbose
                };
            }
        }

        /// <summary>
        /// Executes a PowerShell script block asynchronously
        /// </summary>
        public async Task<PowerShellResult> ExecuteScriptAsync(
            string script,
            CancellationToken cancellationToken = default)
        {
            return await Task.Run(() => ExecuteScript(script, cancellationToken), cancellationToken);
        }

        /// <summary>
        /// Executes a PowerShell script block
        /// </summary>
        public PowerShellResult ExecuteScript(string script, CancellationToken cancellationToken = default)
        {
            if (_runspacePool == null)
                throw new InvalidOperationException("Runspace pool not initialized");

            using var ps = PowerShell.Create();
            ps.RunspacePool = _runspacePool;

            ps.AddScript(script);

            var output = new List<object>();
            var errors = new List<string>();
            var warnings = new List<string>();
            var verbose = new List<string>();

            ps.Streams.Error.DataAdded += (s, e) =>
            {
                var error = ps.Streams.Error[e.Index];
                errors.Add(error.ToString());
                OnOutputReceived(error.ToString(), OutputType.Error);
            };

            ps.Streams.Warning.DataAdded += (s, e) =>
            {
                var warning = ps.Streams.Warning[e.Index];
                warnings.Add(warning.Message);
                OnOutputReceived(warning.Message, OutputType.Warning);
            };

            ps.Streams.Verbose.DataAdded += (s, e) =>
            {
                var verboseMsg = ps.Streams.Verbose[e.Index];
                verbose.Add(verboseMsg.Message);
                OnOutputReceived(verboseMsg.Message, OutputType.Verbose);
            };

            ps.Streams.Information.DataAdded += (s, e) =>
            {
                var info = ps.Streams.Information[e.Index];
                var message = info.MessageData?.ToString() ?? string.Empty;
                OnOutputReceived(message, OutputType.Information);
            };

            try
            {
                var results = ps.Invoke();

                foreach (var result in results)
                {
                    if (result?.BaseObject != null)
                    {
                        output.Add(result.BaseObject);
                        OnOutputReceived(result.ToString() ?? string.Empty, OutputType.Output);
                    }
                }

                return new PowerShellResult
                {
                    Success = !ps.HadErrors,
                    Output = output,
                    Errors = errors,
                    Warnings = warnings,
                    Verbose = verbose
                };
            }
            catch (Exception ex)
            {
                return new PowerShellResult
                {
                    Success = false,
                    Errors = new List<string> { ex.Message },
                    Output = new List<object>(),
                    Warnings = warnings,
                    Verbose = verbose
                };
            }
        }

        /// <summary>
        /// Tests if the WSUS modules are available
        /// </summary>
        public async Task<bool> TestModulesAvailableAsync()
        {
            var result = await ExecuteAsync("Get-Command", new Dictionary<string, object>
            {
                { "Name", "Test-WsusHealth" },
                { "ErrorAction", "SilentlyContinue" }
            });

            return result.Success && result.Output.Count > 0;
        }

        protected virtual void OnOutputReceived(string message, OutputType type)
        {
            OutputReceived?.Invoke(this, new PowerShellOutputEventArgs(message, type));
        }

        protected virtual void OnProgressChanged(string activity, string status, int percentComplete)
        {
            ProgressChanged?.Invoke(this, new PowerShellProgressEventArgs(activity, status, percentComplete));
        }

        public void Dispose()
        {
            if (_disposed) return;

            _runspacePool?.Close();
            _runspacePool?.Dispose();
            _disposed = true;
        }
    }

    public class PowerShellResult
    {
        public bool Success { get; set; }
        public List<object> Output { get; set; } = new();
        public List<string> Errors { get; set; } = new();
        public List<string> Warnings { get; set; } = new();
        public List<string> Verbose { get; set; } = new();

        public T? GetFirstOutput<T>() where T : class
        {
            return Output.Count > 0 ? Output[0] as T : null;
        }
    }

    public enum OutputType
    {
        Output,
        Error,
        Warning,
        Verbose,
        Information
    }

    public class PowerShellOutputEventArgs : EventArgs
    {
        public string Message { get; }
        public OutputType Type { get; }

        public PowerShellOutputEventArgs(string message, OutputType type)
        {
            Message = message;
            Type = type;
        }
    }

    public class PowerShellProgressEventArgs : EventArgs
    {
        public string Activity { get; }
        public string Status { get; }
        public int PercentComplete { get; }

        public PowerShellProgressEventArgs(string activity, string status, int percentComplete)
        {
            Activity = activity;
            Status = status;
            PercentComplete = percentComplete;
        }
    }
}
