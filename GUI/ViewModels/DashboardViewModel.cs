using System;
using System.Collections.ObjectModel;
using System.Threading.Tasks;
using System.Windows.Input;
using System.Windows.Threading;
using WsusManager.Helpers;
using WsusManager.Models;
using WsusManager.Services;

namespace WsusManager.ViewModels
{
    public class DashboardViewModel : ViewModelBase
    {
        private readonly WsusService _wsusService;
        private readonly DispatcherTimer _refreshTimer;

        private bool _isLoading;
        private string _lastUpdated = string.Empty;
        private DatabaseStats _databaseStats = new();
        private DiskSpaceInfo _diskSpace = new();
        private bool _autoRefreshEnabled = true;

        public DashboardViewModel(WsusService wsusService)
        {
            _wsusService = wsusService;

            Services = new ObservableCollection<ServiceStatus>();
            RecentOperations = new ObservableCollection<OperationLogEntry>();

            // Commands
            RefreshCommand = new AsyncRelayCommand(RefreshAsync);
            StartAllServicesCommand = new AsyncRelayCommand(StartAllServicesAsync);
            StopAllServicesCommand = new AsyncRelayCommand(StopAllServicesAsync);
            ToggleAutoRefreshCommand = new RelayCommand(ToggleAutoRefresh);

            // Setup auto-refresh timer (every 30 seconds)
            _refreshTimer = new DispatcherTimer
            {
                Interval = TimeSpan.FromSeconds(30)
            };
            _refreshTimer.Tick += async (s, e) => await RefreshAsync();

            // Initial load
            _ = RefreshAsync();
        }

        #region Properties

        public ObservableCollection<ServiceStatus> Services { get; }
        public ObservableCollection<OperationLogEntry> RecentOperations { get; }

        public bool IsLoading
        {
            get => _isLoading;
            set => SetProperty(ref _isLoading, value);
        }

        public string LastUpdated
        {
            get => _lastUpdated;
            set => SetProperty(ref _lastUpdated, value);
        }

        public DatabaseStats DatabaseStats
        {
            get => _databaseStats;
            set => SetProperty(ref _databaseStats, value);
        }

        public DiskSpaceInfo DiskSpace
        {
            get => _diskSpace;
            set => SetProperty(ref _diskSpace, value);
        }

        public bool AutoRefreshEnabled
        {
            get => _autoRefreshEnabled;
            set
            {
                if (SetProperty(ref _autoRefreshEnabled, value))
                {
                    if (value)
                        _refreshTimer.Start();
                    else
                        _refreshTimer.Stop();
                }
            }
        }

        // Service status summary
        public bool AllServicesRunning => Services.Count > 0 &&
            System.Linq.Enumerable.All(Services, s => s.IsRunning);

        public bool SomeServicesStopped => Services.Count > 0 &&
            System.Linq.Enumerable.Any(Services, s => !s.IsRunning);

        public int RunningServicesCount =>
            System.Linq.Enumerable.Count(Services, s => s.IsRunning);

        public int TotalServicesCount => Services.Count;

        #endregion

        #region Commands

        public ICommand RefreshCommand { get; }
        public ICommand StartAllServicesCommand { get; }
        public ICommand StopAllServicesCommand { get; }
        public ICommand ToggleAutoRefreshCommand { get; }

        #endregion

        #region Methods

        public async Task RefreshAsync()
        {
            IsLoading = true;

            try
            {
                // Refresh services
                var services = await _wsusService.GetServiceStatusAsync();
                Services.Clear();
                foreach (var service in services)
                {
                    Services.Add(service);
                }

                // Refresh database stats
                DatabaseStats = await _wsusService.GetDatabaseStatsAsync();

                // Refresh disk space
                DiskSpace = await _wsusService.GetDiskSpaceAsync("C:\\WSUS");

                LastUpdated = DateTime.Now.ToString("HH:mm:ss");

                // Notify property changes for computed properties
                OnPropertyChanged(nameof(AllServicesRunning));
                OnPropertyChanged(nameof(SomeServicesStopped));
                OnPropertyChanged(nameof(RunningServicesCount));
                OnPropertyChanged(nameof(TotalServicesCount));
            }
            catch (Exception ex)
            {
                AddOperationLog("Refresh failed", ex.Message, false);
            }
            finally
            {
                IsLoading = false;
            }
        }

        private async Task StartAllServicesAsync()
        {
            IsLoading = true;
            try
            {
                var result = await _wsusService.StartAllServicesAsync();
                AddOperationLog("Start All Services", result.Message, result.Success);
                await RefreshAsync();
            }
            finally
            {
                IsLoading = false;
            }
        }

        private async Task StopAllServicesAsync()
        {
            IsLoading = true;
            try
            {
                var result = await _wsusService.StopAllServicesAsync();
                AddOperationLog("Stop All Services", result.Message, result.Success);
                await RefreshAsync();
            }
            finally
            {
                IsLoading = false;
            }
        }

        private void ToggleAutoRefresh()
        {
            AutoRefreshEnabled = !AutoRefreshEnabled;
        }

        private void AddOperationLog(string operation, string message, bool success)
        {
            RecentOperations.Insert(0, new OperationLogEntry
            {
                Timestamp = DateTime.Now,
                Operation = operation,
                Message = message,
                Success = success
            });

            // Keep only last 10 entries
            while (RecentOperations.Count > 10)
            {
                RecentOperations.RemoveAt(RecentOperations.Count - 1);
            }
        }

        #endregion
    }

    public class OperationLogEntry
    {
        public DateTime Timestamp { get; set; }
        public string Operation { get; set; } = string.Empty;
        public string Message { get; set; } = string.Empty;
        public bool Success { get; set; }

        public string TimestampDisplay => Timestamp.ToString("HH:mm:ss");
    }
}
