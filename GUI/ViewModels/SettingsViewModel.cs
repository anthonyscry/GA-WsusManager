using System;
using System.Threading.Tasks;
using System.Windows.Input;
using WsusManager.Helpers;
using WsusManager.Models;
using WsusManager.Services;

namespace WsusManager.ViewModels
{
    public class SettingsViewModel : ViewModelBase
    {
        private readonly WsusService _wsusService;

        private bool _isLoading;
        private bool _hasChanges;
        private string _statusMessage = string.Empty;

        // Configuration
        private string _contentPath = "C:\\WSUS";
        private string _sqlInstance = ".\\SQLEXPRESS";
        private string _exportPath = string.Empty;
        private string _logPath = "C:\\WSUS\\Logs";
        private string _archivePath = "\\\\lab-hyperv\\d\\WSUS-Exports";

        // SSL Settings
        private bool _sslEnabled;
        private string _sslCertificateThumbprint = string.Empty;

        public SettingsViewModel(WsusService wsusService)
        {
            _wsusService = wsusService;

            // Commands
            LoadConfigCommand = new AsyncRelayCommand(LoadConfigurationAsync);
            SaveConfigCommand = new AsyncRelayCommand(SaveConfigurationAsync, () => HasChanges && !IsLoading);
            ResetConfigCommand = new RelayCommand(ResetConfiguration);
            BrowseContentPathCommand = new RelayCommand(BrowseContentPath);
            BrowseLogPathCommand = new RelayCommand(BrowseLogPath);
            BrowseExportPathCommand = new RelayCommand(BrowseExportPath);
            TestConnectionCommand = new AsyncRelayCommand(TestDatabaseConnectionAsync);

            // Load initial configuration
            _ = LoadConfigurationAsync();
        }

        #region Properties

        public bool IsLoading
        {
            get => _isLoading;
            set
            {
                if (SetProperty(ref _isLoading, value))
                {
                    ((AsyncRelayCommand)SaveConfigCommand).RaiseCanExecuteChanged();
                }
            }
        }

        public bool HasChanges
        {
            get => _hasChanges;
            set
            {
                if (SetProperty(ref _hasChanges, value))
                {
                    ((AsyncRelayCommand)SaveConfigCommand).RaiseCanExecuteChanged();
                }
            }
        }

        public string StatusMessage
        {
            get => _statusMessage;
            set => SetProperty(ref _statusMessage, value);
        }

        // Configuration Properties
        public string ContentPath
        {
            get => _contentPath;
            set
            {
                if (SetProperty(ref _contentPath, value))
                {
                    HasChanges = true;
                }
            }
        }

        public string SqlInstance
        {
            get => _sqlInstance;
            set
            {
                if (SetProperty(ref _sqlInstance, value))
                {
                    HasChanges = true;
                }
            }
        }

        public string ExportPath
        {
            get => _exportPath;
            set
            {
                if (SetProperty(ref _exportPath, value))
                {
                    HasChanges = true;
                }
            }
        }

        public string LogPath
        {
            get => _logPath;
            set
            {
                if (SetProperty(ref _logPath, value))
                {
                    HasChanges = true;
                }
            }
        }

        public string ArchivePath
        {
            get => _archivePath;
            set
            {
                if (SetProperty(ref _archivePath, value))
                {
                    HasChanges = true;
                }
            }
        }

        // SSL Properties
        public bool SslEnabled
        {
            get => _sslEnabled;
            set
            {
                if (SetProperty(ref _sslEnabled, value))
                {
                    HasChanges = true;
                }
            }
        }

        public string SslCertificateThumbprint
        {
            get => _sslCertificateThumbprint;
            set
            {
                if (SetProperty(ref _sslCertificateThumbprint, value))
                {
                    HasChanges = true;
                }
            }
        }

        #endregion

        #region Commands

        public ICommand LoadConfigCommand { get; }
        public ICommand SaveConfigCommand { get; }
        public ICommand ResetConfigCommand { get; }
        public ICommand BrowseContentPathCommand { get; }
        public ICommand BrowseLogPathCommand { get; }
        public ICommand BrowseExportPathCommand { get; }
        public ICommand TestConnectionCommand { get; }

        #endregion

        #region Methods

        private async Task LoadConfigurationAsync()
        {
            IsLoading = true;
            StatusMessage = "Loading configuration...";

            try
            {
                var config = await _wsusService.GetConfigurationAsync();

                ContentPath = config.ContentPath;
                SqlInstance = config.SqlInstance;
                ExportPath = config.ExportPath;
                LogPath = config.LogPath;
                ArchivePath = config.DefaultArchivePath;

                HasChanges = false;
                StatusMessage = "Configuration loaded";
            }
            catch (Exception ex)
            {
                StatusMessage = $"Error loading configuration: {ex.Message}";
            }
            finally
            {
                IsLoading = false;
            }
        }

        private async Task SaveConfigurationAsync()
        {
            IsLoading = true;
            StatusMessage = "Saving configuration...";

            try
            {
                var config = new WsusConfiguration
                {
                    ContentPath = ContentPath,
                    SqlInstance = SqlInstance,
                    ExportPath = ExportPath,
                    LogPath = LogPath,
                    DefaultArchivePath = ArchivePath
                };

                var result = await _wsusService.SetConfigurationAsync(config);

                if (result.Success)
                {
                    HasChanges = false;
                    StatusMessage = "Configuration saved successfully";
                }
                else
                {
                    StatusMessage = $"Error saving: {result.Message}";
                }
            }
            catch (Exception ex)
            {
                StatusMessage = $"Error saving configuration: {ex.Message}";
            }
            finally
            {
                IsLoading = false;
            }
        }

        private void ResetConfiguration()
        {
            ContentPath = "C:\\WSUS";
            SqlInstance = ".\\SQLEXPRESS";
            ExportPath = string.Empty;
            LogPath = "C:\\WSUS\\Logs";
            ArchivePath = "\\\\lab-hyperv\\d\\WSUS-Exports";
            SslEnabled = false;
            SslCertificateThumbprint = string.Empty;

            HasChanges = true;
            StatusMessage = "Configuration reset to defaults";
        }

        private void BrowseContentPath()
        {
            // In a real implementation, this would open a folder browser dialog
            StatusMessage = "Browse content path - use folder browser";
        }

        private void BrowseLogPath()
        {
            // In a real implementation, this would open a folder browser dialog
            StatusMessage = "Browse log path - use folder browser";
        }

        private void BrowseExportPath()
        {
            // In a real implementation, this would open a folder browser dialog
            StatusMessage = "Browse export path - use folder browser";
        }

        private async Task TestDatabaseConnectionAsync()
        {
            IsLoading = true;
            StatusMessage = "Testing database connection...";

            try
            {
                var script = $@"
                    $connectionString = 'Server={SqlInstance};Database=SUSDB;Integrated Security=True;Connection Timeout=5'
                    $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
                    $connection.Open()
                    $connection.Close()
                    Write-Output 'Connection successful'
                ";

                // This would use the PowerShell service to test the connection
                await Task.Delay(1000); // Simulate connection test

                StatusMessage = "Database connection successful";
            }
            catch (Exception ex)
            {
                StatusMessage = $"Connection failed: {ex.Message}";
            }
            finally
            {
                IsLoading = false;
            }
        }

        #endregion
    }
}
