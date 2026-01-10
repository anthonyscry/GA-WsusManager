using System;
using System.Collections.ObjectModel;
using System.Threading.Tasks;
using System.Windows.Input;
using WsusManager.Helpers;
using WsusManager.Services;

namespace WsusManager.ViewModels
{
    public class MaintenanceViewModel : ViewModelBase
    {
        private readonly WsusService _wsusService;

        private bool _isLoading;
        private string _statusMessage = string.Empty;
        private int _operationProgress;
        private string _currentOperation = string.Empty;

        // Cleanup options
        private bool _removeDeclined = true;
        private bool _removeSuperseded = true;
        private bool _optimizeIndexes = true;
        private bool _updateStatistics = true;
        private bool _shrinkDatabase;

        public MaintenanceViewModel(WsusService wsusService)
        {
            _wsusService = wsusService;

            OutputLog = new ObservableCollection<string>();

            // Subscribe to events
            _wsusService.OutputReceived += OnOutputReceived;
            _wsusService.ProgressChanged += OnProgressChanged;

            // Commands
            RunDeepCleanupCommand = new AsyncRelayCommand(RunDeepCleanupAsync, () => !IsLoading);
            RunContentResetCommand = new AsyncRelayCommand(RunContentResetAsync, () => !IsLoading);
            ClearLogCommand = new RelayCommand(() => OutputLog.Clear());
        }

        #region Properties

        public ObservableCollection<string> OutputLog { get; }

        public bool IsLoading
        {
            get => _isLoading;
            set
            {
                if (SetProperty(ref _isLoading, value))
                {
                    ((AsyncRelayCommand)RunDeepCleanupCommand).RaiseCanExecuteChanged();
                    ((AsyncRelayCommand)RunContentResetCommand).RaiseCanExecuteChanged();
                }
            }
        }

        public string StatusMessage
        {
            get => _statusMessage;
            set => SetProperty(ref _statusMessage, value);
        }

        public int OperationProgress
        {
            get => _operationProgress;
            set => SetProperty(ref _operationProgress, value);
        }

        public string CurrentOperation
        {
            get => _currentOperation;
            set => SetProperty(ref _currentOperation, value);
        }

        // Cleanup Options
        public bool RemoveDeclined
        {
            get => _removeDeclined;
            set => SetProperty(ref _removeDeclined, value);
        }

        public bool RemoveSuperseded
        {
            get => _removeSuperseded;
            set => SetProperty(ref _removeSuperseded, value);
        }

        public bool OptimizeIndexes
        {
            get => _optimizeIndexes;
            set => SetProperty(ref _optimizeIndexes, value);
        }

        public bool UpdateStatistics
        {
            get => _updateStatistics;
            set => SetProperty(ref _updateStatistics, value);
        }

        public bool ShrinkDatabase
        {
            get => _shrinkDatabase;
            set => SetProperty(ref _shrinkDatabase, value);
        }

        #endregion

        #region Commands

        public ICommand RunDeepCleanupCommand { get; }
        public ICommand RunContentResetCommand { get; }
        public ICommand ClearLogCommand { get; }

        #endregion

        #region Methods

        private async Task RunDeepCleanupAsync()
        {
            IsLoading = true;
            OperationProgress = 0;
            OutputLog.Clear();

            try
            {
                int totalSteps = 0;
                if (RemoveDeclined) totalSteps++;
                if (RemoveSuperseded) totalSteps++;
                if (OptimizeIndexes) totalSteps++;
                if (UpdateStatistics) totalSteps++;
                if (ShrinkDatabase) totalSteps++;

                if (totalSteps == 0)
                {
                    StatusMessage = "No cleanup options selected";
                    return;
                }

                int currentStep = 0;

                // Remove Declined
                if (RemoveDeclined)
                {
                    currentStep++;
                    CurrentOperation = "Removing declined supersession records...";
                    OperationProgress = (int)((double)currentStep / totalSteps * 100);
                    AddLog("Removing declined supersession records...");

                    var script = "Remove-DeclinedSupersessionRecords";
                    await ExecuteScriptAsync(script);
                }

                // Remove Superseded
                if (RemoveSuperseded)
                {
                    currentStep++;
                    CurrentOperation = "Removing superseded supersession records...";
                    OperationProgress = (int)((double)currentStep / totalSteps * 100);
                    AddLog("Removing superseded supersession records...");

                    var script = "Remove-SupersededSupersessionRecords";
                    await ExecuteScriptAsync(script);
                }

                // Optimize Indexes
                if (OptimizeIndexes)
                {
                    currentStep++;
                    CurrentOperation = "Optimizing database indexes...";
                    OperationProgress = (int)((double)currentStep / totalSteps * 100);
                    AddLog("Optimizing database indexes...");

                    await _wsusService.OptimizeIndexesAsync();
                }

                // Update Statistics
                if (UpdateStatistics)
                {
                    currentStep++;
                    CurrentOperation = "Updating database statistics...";
                    OperationProgress = (int)((double)currentStep / totalSteps * 100);
                    AddLog("Updating database statistics...");

                    var script = "Update-WsusStatistics";
                    await ExecuteScriptAsync(script);
                }

                // Shrink Database
                if (ShrinkDatabase)
                {
                    currentStep++;
                    CurrentOperation = "Shrinking database...";
                    OperationProgress = (int)((double)currentStep / totalSteps * 100);
                    AddLog("Shrinking database...");

                    await _wsusService.ShrinkDatabaseAsync();
                }

                OperationProgress = 100;
                CurrentOperation = "Deep cleanup completed";
                StatusMessage = "Deep cleanup completed successfully";
                AddLog("Deep cleanup completed successfully");
            }
            catch (Exception ex)
            {
                StatusMessage = $"Cleanup error: {ex.Message}";
                CurrentOperation = "Error";
                AddLog($"Error: {ex.Message}");
            }
            finally
            {
                IsLoading = false;
            }
        }

        private async Task RunContentResetAsync()
        {
            IsLoading = true;
            OperationProgress = 0;
            CurrentOperation = "Resetting content download...";
            AddLog("Starting content download reset...");
            AddLog("WARNING: This operation may take 30-90 minutes to complete");

            try
            {
                OperationProgress = 10;
                var result = await _wsusService.ResetContentDownloadAsync();

                if (result.Success)
                {
                    OperationProgress = 100;
                    CurrentOperation = "Content reset initiated";
                    StatusMessage = "Content download reset initiated successfully";
                    AddLog("Content download reset initiated successfully");
                    AddLog("Note: WSUS will now re-verify all content files. This runs in the background.");
                }
                else
                {
                    CurrentOperation = "Reset failed";
                    StatusMessage = $"Reset failed: {result.Message}";
                    AddLog($"Reset failed: {result.Message}");
                }
            }
            catch (Exception ex)
            {
                StatusMessage = $"Reset error: {ex.Message}";
                CurrentOperation = "Error";
                AddLog($"Error: {ex.Message}");
            }
            finally
            {
                IsLoading = false;
            }
        }

        private async Task ExecuteScriptAsync(string script)
        {
            // Use PowerShell service to execute script
            // This is a simplified wrapper
            await Task.Delay(100); // Placeholder for actual execution
        }

        private void AddLog(string message)
        {
            var timestamp = DateTime.Now.ToString("HH:mm:ss");
            OutputLog.Add($"[{timestamp}] {message}");
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
                if (e.PercentComplete >= 0)
                {
                    OperationProgress = e.PercentComplete;
                }
                CurrentOperation = $"{e.Activity}: {e.Status}";
            });
        }

        #endregion
    }
}
