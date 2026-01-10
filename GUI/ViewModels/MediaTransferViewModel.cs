using System;
using System.Collections.ObjectModel;
using System.Threading.Tasks;
using System.Windows.Input;
using WsusManager.Helpers;
using WsusManager.Models;
using WsusManager.Services;

namespace WsusManager.ViewModels
{
    public class MediaTransferViewModel : ViewModelBase
    {
        private readonly WsusService _wsusService;

        private bool _isLoading;
        private string _statusMessage = string.Empty;
        private int _operationProgress;
        private string _currentOperation = string.Empty;

        // Import settings
        private string _importSourcePath = string.Empty;
        private string _importDestinationPath = "C:\\WSUS";

        // Export settings
        private string _exportSourcePath = "C:\\WSUS";
        private string _exportDestinationPath = string.Empty;
        private int _exportDaysOld;
        private ExportMode _selectedExportMode = ExportMode.Full;

        // Archive browser
        private string _archivePath = "\\\\lab-hyperv\\d\\WSUS-Exports";
        private ArchiveYear? _selectedYear;
        private ArchiveMonth? _selectedMonth;
        private ArchiveBackup? _selectedBackup;

        public MediaTransferViewModel(WsusService wsusService)
        {
            _wsusService = wsusService;

            OutputLog = new ObservableCollection<string>();
            ArchiveYears = new ObservableCollection<ArchiveYear>();
            ExportModes = new ObservableCollection<ExportMode>
            {
                ExportMode.Full,
                ExportMode.Differential,
                ExportMode.NewOnly
            };

            // Subscribe to events
            _wsusService.OutputReceived += OnOutputReceived;
            _wsusService.ProgressChanged += OnProgressChanged;

            // Commands
            BrowseImportSourceCommand = new RelayCommand(BrowseImportSource);
            BrowseExportDestinationCommand = new RelayCommand(BrowseExportDestination);
            RefreshArchiveCommand = new AsyncRelayCommand(RefreshArchiveAsync);
            ImportCommand = new AsyncRelayCommand(ImportFromMediaAsync, () => !IsLoading && !string.IsNullOrEmpty(ImportSourcePath));
            ImportFromArchiveCommand = new AsyncRelayCommand(ImportFromArchiveAsync, () => !IsLoading && SelectedBackup != null);
            ExportCommand = new AsyncRelayCommand(ExportToMediaAsync, () => !IsLoading && !string.IsNullOrEmpty(ExportDestinationPath));
            ClearLogCommand = new RelayCommand(() => OutputLog.Clear());
        }

        #region Enums

        public enum ExportMode
        {
            Full,
            Differential,
            NewOnly
        }

        #endregion

        #region Properties

        public ObservableCollection<string> OutputLog { get; }
        public ObservableCollection<ArchiveYear> ArchiveYears { get; }
        public ObservableCollection<ExportMode> ExportModes { get; }

        public bool IsLoading
        {
            get => _isLoading;
            set
            {
                if (SetProperty(ref _isLoading, value))
                {
                    ((AsyncRelayCommand)ImportCommand).RaiseCanExecuteChanged();
                    ((AsyncRelayCommand)ImportFromArchiveCommand).RaiseCanExecuteChanged();
                    ((AsyncRelayCommand)ExportCommand).RaiseCanExecuteChanged();
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

        // Import Properties
        public string ImportSourcePath
        {
            get => _importSourcePath;
            set
            {
                if (SetProperty(ref _importSourcePath, value))
                {
                    ((AsyncRelayCommand)ImportCommand).RaiseCanExecuteChanged();
                }
            }
        }

        public string ImportDestinationPath
        {
            get => _importDestinationPath;
            set => SetProperty(ref _importDestinationPath, value);
        }

        // Export Properties
        public string ExportSourcePath
        {
            get => _exportSourcePath;
            set => SetProperty(ref _exportSourcePath, value);
        }

        public string ExportDestinationPath
        {
            get => _exportDestinationPath;
            set
            {
                if (SetProperty(ref _exportDestinationPath, value))
                {
                    ((AsyncRelayCommand)ExportCommand).RaiseCanExecuteChanged();
                }
            }
        }

        public int ExportDaysOld
        {
            get => _exportDaysOld;
            set => SetProperty(ref _exportDaysOld, value);
        }

        public ExportMode SelectedExportMode
        {
            get => _selectedExportMode;
            set => SetProperty(ref _selectedExportMode, value);
        }

        // Archive Browser Properties
        public string ArchivePath
        {
            get => _archivePath;
            set
            {
                if (SetProperty(ref _archivePath, value))
                {
                    _ = RefreshArchiveAsync();
                }
            }
        }

        public ArchiveYear? SelectedYear
        {
            get => _selectedYear;
            set
            {
                if (SetProperty(ref _selectedYear, value))
                {
                    SelectedMonth = null;
                    OnPropertyChanged(nameof(AvailableMonths));
                }
            }
        }

        public ArchiveMonth? SelectedMonth
        {
            get => _selectedMonth;
            set
            {
                if (SetProperty(ref _selectedMonth, value))
                {
                    SelectedBackup = null;
                    OnPropertyChanged(nameof(AvailableBackups));
                }
            }
        }

        public ArchiveBackup? SelectedBackup
        {
            get => _selectedBackup;
            set
            {
                if (SetProperty(ref _selectedBackup, value))
                {
                    ((AsyncRelayCommand)ImportFromArchiveCommand).RaiseCanExecuteChanged();
                }
            }
        }

        public ObservableCollection<ArchiveMonth>? AvailableMonths =>
            SelectedYear != null ? new ObservableCollection<ArchiveMonth>(SelectedYear.Months) : null;

        public ObservableCollection<ArchiveBackup>? AvailableBackups =>
            SelectedMonth != null ? new ObservableCollection<ArchiveBackup>(SelectedMonth.Backups) : null;

        #endregion

        #region Commands

        public ICommand BrowseImportSourceCommand { get; }
        public ICommand BrowseExportDestinationCommand { get; }
        public ICommand RefreshArchiveCommand { get; }
        public ICommand ImportCommand { get; }
        public ICommand ImportFromArchiveCommand { get; }
        public ICommand ExportCommand { get; }
        public ICommand ClearLogCommand { get; }

        #endregion

        #region Methods

        private void BrowseImportSource()
        {
            // In a real implementation, this would open a folder browser dialog
            AddLog("Browse import source - use folder browser");
        }

        private void BrowseExportDestination()
        {
            // In a real implementation, this would open a folder browser dialog
            AddLog("Browse export destination - use folder browser");
        }

        private async Task RefreshArchiveAsync()
        {
            IsLoading = true;
            StatusMessage = "Loading archive structure...";

            try
            {
                var years = await _wsusService.GetArchiveStructureAsync(ArchivePath);
                ArchiveYears.Clear();
                foreach (var year in years)
                {
                    ArchiveYears.Add(year);
                }
                StatusMessage = $"Found {ArchiveYears.Count} year(s) in archive";
            }
            catch (Exception ex)
            {
                StatusMessage = $"Error loading archive: {ex.Message}";
                AddLog($"Error loading archive: {ex.Message}");
            }
            finally
            {
                IsLoading = false;
            }
        }

        private async Task ImportFromMediaAsync()
        {
            if (string.IsNullOrEmpty(ImportSourcePath)) return;

            IsLoading = true;
            OperationProgress = 0;
            CurrentOperation = "Importing from external media...";
            AddLog($"Starting import from: {ImportSourcePath}");
            AddLog($"Destination: {ImportDestinationPath}");

            try
            {
                var result = await _wsusService.ImportFromMediaAsync(ImportSourcePath, ImportDestinationPath);

                if (result.Success)
                {
                    OperationProgress = 100;
                    CurrentOperation = "Import completed";
                    StatusMessage = "Import completed successfully";
                    AddLog("Import completed successfully");
                }
                else
                {
                    CurrentOperation = "Import failed";
                    StatusMessage = $"Import failed: {result.Message}";
                    AddLog($"Import failed: {result.Message}");
                }
            }
            catch (Exception ex)
            {
                StatusMessage = $"Import error: {ex.Message}";
                CurrentOperation = "Error";
                AddLog($"Import error: {ex.Message}");
            }
            finally
            {
                IsLoading = false;
            }
        }

        private async Task ImportFromArchiveAsync()
        {
            if (SelectedBackup == null) return;

            ImportSourcePath = SelectedBackup.Path;
            await ImportFromMediaAsync();
        }

        private async Task ExportToMediaAsync()
        {
            if (string.IsNullOrEmpty(ExportDestinationPath)) return;

            IsLoading = true;
            OperationProgress = 0;
            CurrentOperation = "Exporting to external media...";
            AddLog($"Starting export from: {ExportSourcePath}");
            AddLog($"Destination: {ExportDestinationPath}");
            AddLog($"Mode: {SelectedExportMode}");

            if (ExportDaysOld > 0)
            {
                AddLog($"Only files older than {ExportDaysOld} days");
            }

            try
            {
                var daysParam = SelectedExportMode == ExportMode.Differential ? ExportDaysOld : 0;
                var result = await _wsusService.ExportToMediaAsync(ExportSourcePath, ExportDestinationPath, daysParam);

                if (result.Success)
                {
                    OperationProgress = 100;
                    CurrentOperation = "Export completed";
                    StatusMessage = "Export completed successfully";
                    AddLog("Export completed successfully");
                }
                else
                {
                    CurrentOperation = "Export failed";
                    StatusMessage = $"Export failed: {result.Message}";
                    AddLog($"Export failed: {result.Message}");
                }
            }
            catch (Exception ex)
            {
                StatusMessage = $"Export error: {ex.Message}";
                CurrentOperation = "Error";
                AddLog($"Export error: {ex.Message}");
            }
            finally
            {
                IsLoading = false;
            }
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
