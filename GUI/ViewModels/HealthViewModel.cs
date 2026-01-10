using System;
using System.Collections.ObjectModel;
using System.Threading.Tasks;
using System.Windows.Input;
using WsusManager.Helpers;
using WsusManager.Models;
using WsusManager.Services;

namespace WsusManager.ViewModels
{
    public class HealthViewModel : ViewModelBase
    {
        private readonly WsusService _wsusService;

        private bool _isLoading;
        private bool _isRepairing;
        private string _statusMessage = string.Empty;
        private string _overallStatus = "Unknown";
        private DateTime? _lastCheckTime;

        public HealthViewModel(WsusService wsusService)
        {
            _wsusService = wsusService;

            HealthChecks = new ObservableCollection<HealthCheck>();
            RepairLog = new ObservableCollection<string>();

            // Commands
            RunHealthCheckCommand = new AsyncRelayCommand(RunHealthCheckAsync, () => !IsLoading);
            RunRepairCommand = new AsyncRelayCommand(RunRepairAsync, () => !IsLoading && !IsRepairing);
            ClearLogCommand = new RelayCommand(() => RepairLog.Clear());
        }

        #region Properties

        public ObservableCollection<HealthCheck> HealthChecks { get; }
        public ObservableCollection<string> RepairLog { get; }

        public bool IsLoading
        {
            get => _isLoading;
            set
            {
                if (SetProperty(ref _isLoading, value))
                {
                    ((AsyncRelayCommand)RunHealthCheckCommand).RaiseCanExecuteChanged();
                    ((AsyncRelayCommand)RunRepairCommand).RaiseCanExecuteChanged();
                }
            }
        }

        public bool IsRepairing
        {
            get => _isRepairing;
            set
            {
                if (SetProperty(ref _isRepairing, value))
                {
                    ((AsyncRelayCommand)RunRepairCommand).RaiseCanExecuteChanged();
                }
            }
        }

        public string StatusMessage
        {
            get => _statusMessage;
            set => SetProperty(ref _statusMessage, value);
        }

        public string OverallStatus
        {
            get => _overallStatus;
            set => SetProperty(ref _overallStatus, value);
        }

        public DateTime? LastCheckTime
        {
            get => _lastCheckTime;
            set => SetProperty(ref _lastCheckTime, value);
        }

        public string LastCheckDisplay => LastCheckTime?.ToString("yyyy-MM-dd HH:mm:ss") ?? "Never";

        public int PassedCount => System.Linq.Enumerable.Count(HealthChecks, c => c.IsSuccess);
        public int WarningCount => System.Linq.Enumerable.Count(HealthChecks, c => c.IsWarning);
        public int FailedCount => System.Linq.Enumerable.Count(HealthChecks, c => c.IsError);

        #endregion

        #region Commands

        public ICommand RunHealthCheckCommand { get; }
        public ICommand RunRepairCommand { get; }
        public ICommand ClearLogCommand { get; }

        #endregion

        #region Methods

        private async Task RunHealthCheckAsync()
        {
            IsLoading = true;
            StatusMessage = "Running health check...";
            HealthChecks.Clear();

            try
            {
                var result = await _wsusService.RunHealthCheckAsync();

                foreach (var check in result.Checks)
                {
                    HealthChecks.Add(check);
                }

                LastCheckTime = DateTime.Now;

                // Determine overall status
                if (FailedCount > 0)
                {
                    OverallStatus = "Failed";
                    StatusMessage = $"Health check completed with {FailedCount} failure(s)";
                }
                else if (WarningCount > 0)
                {
                    OverallStatus = "Warning";
                    StatusMessage = $"Health check completed with {WarningCount} warning(s)";
                }
                else
                {
                    OverallStatus = "Healthy";
                    StatusMessage = "All health checks passed";
                }

                // Update computed properties
                OnPropertyChanged(nameof(LastCheckDisplay));
                OnPropertyChanged(nameof(PassedCount));
                OnPropertyChanged(nameof(WarningCount));
                OnPropertyChanged(nameof(FailedCount));
            }
            catch (Exception ex)
            {
                OverallStatus = "Error";
                StatusMessage = $"Health check error: {ex.Message}";
                AddRepairLog($"Error running health check: {ex.Message}");
            }
            finally
            {
                IsLoading = false;
            }
        }

        private async Task RunRepairAsync()
        {
            IsRepairing = true;
            StatusMessage = "Running automatic repair...";
            AddRepairLog("Starting automatic repair...");

            try
            {
                var result = await _wsusService.RepairHealthAsync();

                if (result.Success)
                {
                    AddRepairLog("Repair completed successfully");
                    StatusMessage = "Repair completed - running health check...";

                    // Run health check after repair
                    await RunHealthCheckAsync();
                }
                else
                {
                    AddRepairLog($"Repair failed: {result.Message}");
                    StatusMessage = $"Repair failed: {result.Message}";
                }

                foreach (var detail in result.Details)
                {
                    AddRepairLog(detail.ToString() ?? string.Empty);
                }
            }
            catch (Exception ex)
            {
                StatusMessage = $"Repair error: {ex.Message}";
                AddRepairLog($"Repair error: {ex.Message}");
            }
            finally
            {
                IsRepairing = false;
            }
        }

        private void AddRepairLog(string message)
        {
            if (string.IsNullOrEmpty(message)) return;

            var timestamp = DateTime.Now.ToString("HH:mm:ss");
            RepairLog.Insert(0, $"[{timestamp}] {message}");

            // Keep log manageable
            while (RepairLog.Count > 100)
            {
                RepairLog.RemoveAt(RepairLog.Count - 1);
            }
        }

        #endregion
    }
}
