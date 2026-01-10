using System;
using System.Collections.ObjectModel;
using System.Threading.Tasks;
using System.Windows.Input;
using WsusManager.Helpers;
using WsusManager.Models;
using WsusManager.Services;

namespace WsusManager.ViewModels
{
    public class DatabaseViewModel : ViewModelBase
    {
        private readonly WsusService _wsusService;

        private bool _isLoading;
        private string _statusMessage = string.Empty;
        private DatabaseStats _stats = new();
        private BackupInfo? _selectedBackup;
        private string _backupPath = "C:\\WSUS\\Backups";
        private bool _isRestoring;
        private int _operationProgress;
        private string _operationStatus = string.Empty;

        public DatabaseViewModel(WsusService wsusService)
        {
            _wsusService = wsusService;

            Backups = new ObservableCollection<BackupInfo>();
            OutputLog = new ObservableCollection<string>();

            // Subscribe to output events
            _wsusService.OutputReceived += OnOutputReceived;
            _wsusService.ProgressChanged += OnProgressChanged;

            // Commands
            RefreshCommand = new AsyncRelayCommand(RefreshStatsAsync);
            RefreshBackupsCommand = new AsyncRelayCommand(RefreshBackupsAsync);
            RestoreCommand = new AsyncRelayCommand(RestoreSelectedBackupAsync, () => SelectedBackup != null && !IsRestoring);
            ShrinkCommand = new AsyncRelayCommand(ShrinkDatabaseAsync, () => !IsLoading);
            OptimizeCommand = new AsyncRelayCommand(OptimizeIndexesAsync, () => !IsLoading);
            BrowseBackupPathCommand = new RelayCommand(BrowseBackupPath);
            ClearLogCommand = new RelayCommand(() => OutputLog.Clear());

            // Initial load
            _ = RefreshStatsAsync();
        }

        #region Properties

        public ObservableCollection<BackupInfo> Backups { get; }
        public ObservableCollection<string> OutputLog { get; }

        public bool IsLoading
        {
            get => _isLoading;
            set => SetProperty(ref _isLoading, value);
        }

        public string StatusMessage
        {
            get => _statusMessage;
            set => SetProperty(ref _statusMessage, value);
        }

        public DatabaseStats Stats
        {
            get => _stats;
            set => SetProperty(ref _stats, value);
        }

        public BackupInfo? SelectedBackup
        {
            get => _selectedBackup;
            set
            {
                if (SetProperty(ref _selectedBackup, value))
                {
                    ((AsyncRelayCommand)RestoreCommand).RaiseCanExecuteChanged();
                }
            }
        }

        public string BackupPath
        {
            get => _backupPath;
            set
            {
                if (SetProperty(ref _backupPath, value))
                {
                    _ = RefreshBackupsAsync();
                }
            }
        }

        public bool IsRestoring
        {
            get => _isRestoring;
            set
            {
                if (SetProperty(ref _isRestoring, value))
                {
                    ((AsyncRelayCommand)RestoreCommand).RaiseCanExecuteChanged();
                }
            }
        }

        public int OperationProgress
        {
            get => _operationProgress;
            set => SetProperty(ref _operationProgress, value);
        }

        public string OperationStatus
        {
            get => _operationStatus;
            set => SetProperty(ref _operationStatus, value);
        }

        #endregion

        #region Commands

        public ICommand RefreshCommand { get; }
        public ICommand RefreshBackupsCommand { get; }
        public ICommand RestoreCommand { get; }
        public ICommand ShrinkCommand { get; }
        public ICommand OptimizeCommand { get; }
        public ICommand BrowseBackupPathCommand { get; }
        public ICommand ClearLogCommand { get; }

        #endregion

        #region Methods

        public async Task RefreshStatsAsync()
        {
            IsLoading = true;
            StatusMessage = "Loading database statistics...";

            try
            {
                Stats = await _wsusService.GetDatabaseStatsAsync();
                StatusMessage = $"Database size: {Stats.SizeDisplay}";
            }
            catch (Exception ex)
            {
                StatusMessage = $"Error: {ex.Message}";
                AddLog($"Error loading stats: {ex.Message}");
            }
            finally
            {
                IsLoading = false;
            }
        }

        private async Task RefreshBackupsAsync()
        {
            IsLoading = true;

            try
            {
                var backups = await _wsusService.GetAvailableBackupsAsync(BackupPath);
                Backups.Clear();
                foreach (var backup in backups)
                {
                    Backups.Add(backup);
                }
                StatusMessage = $"Found {Backups.Count} backup(s)";
            }
            catch (Exception ex)
            {
                StatusMessage = $"Error loading backups: {ex.Message}";
            }
            finally
            {
                IsLoading = false;
            }
        }

        private async Task RestoreSelectedBackupAsync()
        {
            if (SelectedBackup == null) return;

            IsRestoring = true;
            OperationProgress = 0;
            OperationStatus = "Starting restore...";
            AddLog($"Starting restore from: {SelectedBackup.FullPath}");

            try
            {
                var result = await _wsusService.RestoreDatabaseAsync(SelectedBackup.FullPath);

                if (result.Success)
                {
                    OperationStatus = "Restore completed successfully";
                    StatusMessage = "Database restored successfully";
                    AddLog("Restore completed successfully");
                }
                else
                {
                    OperationStatus = $"Restore failed: {result.Message}";
                    StatusMessage = $"Restore failed: {result.Message}";
                    AddLog($"Restore failed: {result.Message}");
                }

                OperationProgress = 100;
            }
            catch (Exception ex)
            {
                OperationStatus = $"Error: {ex.Message}";
                StatusMessage = $"Restore error: {ex.Message}";
                AddLog($"Restore error: {ex.Message}");
            }
            finally
            {
                IsRestoring = false;
                await RefreshStatsAsync();
            }
        }

        private async Task ShrinkDatabaseAsync()
        {
            IsLoading = true;
            StatusMessage = "Shrinking database...";
            AddLog("Starting database shrink operation...");

            try
            {
                var result = await _wsusService.ShrinkDatabaseAsync();
                StatusMessage = result.Message;
                AddLog(result.Message);
                await RefreshStatsAsync();
            }
            catch (Exception ex)
            {
                StatusMessage = $"Shrink error: {ex.Message}";
                AddLog($"Shrink error: {ex.Message}");
            }
            finally
            {
                IsLoading = false;
            }
        }

        private async Task OptimizeIndexesAsync()
        {
            IsLoading = true;
            StatusMessage = "Optimizing indexes...";
            AddLog("Starting index optimization...");

            try
            {
                var result = await _wsusService.OptimizeIndexesAsync();
                StatusMessage = result.Message;
                AddLog(result.Message);
            }
            catch (Exception ex)
            {
                StatusMessage = $"Optimization error: {ex.Message}";
                AddLog($"Optimization error: {ex.Message}");
            }
            finally
            {
                IsLoading = false;
            }
        }

        private void BrowseBackupPath()
        {
            // In a real implementation, this would open a folder browser dialog
            // For now, we just notify that this functionality is available
            AddLog("Browse backup path - use folder browser");
        }

        private void AddLog(string message)
        {
            var timestamp = DateTime.Now.ToString("HH:mm:ss");
            OutputLog.Insert(0, $"[{timestamp}] {message}");

            // Keep log manageable
            while (OutputLog.Count > 100)
            {
                OutputLog.RemoveAt(OutputLog.Count - 1);
            }
        }

        private void OnOutputReceived(object? sender, PowerShellOutputEventArgs e)
        {
            System.Windows.Application.Current?.Dispatcher.Invoke(() =>
            {
                AddLog(e.Message);
            });
        }

        private void OnProgressChanged(object? sender, PowerShellProgressEventArgs e)
        {
            System.Windows.Application.Current?.Dispatcher.Invoke(() =>
            {
                OperationProgress = e.PercentComplete;
                OperationStatus = $"{e.Activity}: {e.Status}";
            });
        }

        #endregion
    }
}
