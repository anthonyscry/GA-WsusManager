using System;
using System.Windows.Input;
using WsusManager.Helpers;
using WsusManager.Services;

namespace WsusManager.ViewModels
{
    public class MainViewModel : ViewModelBase, IDisposable
    {
        private readonly PowerShellService _psService;
        private readonly WsusService _wsusService;

        private ViewModelBase? _currentViewModel;
        private int _selectedTabIndex;
        private string _statusMessage = "Ready";
        private bool _isOperationRunning;

        public MainViewModel()
        {
            // Initialize services
            _psService = new PowerShellService(App.ModulesPath);
            _wsusService = new WsusService(_psService);

            // Subscribe to output events
            _wsusService.OutputReceived += OnOutputReceived;
            _wsusService.ProgressChanged += OnProgressChanged;

            // Initialize ViewModels
            DashboardViewModel = new DashboardViewModel(_wsusService);
            DatabaseViewModel = new DatabaseViewModel(_wsusService);
            ServicesViewModel = new ServicesViewModel(_wsusService);
            HealthViewModel = new HealthViewModel(_wsusService);
            MaintenanceViewModel = new MaintenanceViewModel(_wsusService);
            MediaTransferViewModel = new MediaTransferViewModel(_wsusService);
            SettingsViewModel = new SettingsViewModel(_wsusService);

            // Set initial view
            CurrentViewModel = DashboardViewModel;

            // Initialize commands
            NavigateCommand = new RelayCommand<string>(Navigate);
            RefreshCommand = new AsyncRelayCommand(RefreshCurrentView);
        }

        #region Properties

        public DashboardViewModel DashboardViewModel { get; }
        public DatabaseViewModel DatabaseViewModel { get; }
        public ServicesViewModel ServicesViewModel { get; }
        public HealthViewModel HealthViewModel { get; }
        public MaintenanceViewModel MaintenanceViewModel { get; }
        public MediaTransferViewModel MediaTransferViewModel { get; }
        public SettingsViewModel SettingsViewModel { get; }

        public ViewModelBase? CurrentViewModel
        {
            get => _currentViewModel;
            set => SetProperty(ref _currentViewModel, value);
        }

        public int SelectedTabIndex
        {
            get => _selectedTabIndex;
            set
            {
                if (SetProperty(ref _selectedTabIndex, value))
                {
                    UpdateCurrentViewModelFromTab();
                }
            }
        }

        public string StatusMessage
        {
            get => _statusMessage;
            set => SetProperty(ref _statusMessage, value);
        }

        public bool IsOperationRunning
        {
            get => _isOperationRunning;
            set => SetProperty(ref _isOperationRunning, value);
        }

        #endregion

        #region Commands

        public ICommand NavigateCommand { get; }
        public ICommand RefreshCommand { get; }

        #endregion

        #region Methods

        private void Navigate(string? viewName)
        {
            CurrentViewModel = viewName switch
            {
                "Dashboard" => DashboardViewModel,
                "Database" => DatabaseViewModel,
                "Services" => ServicesViewModel,
                "Health" => HealthViewModel,
                "Maintenance" => MaintenanceViewModel,
                "MediaTransfer" => MediaTransferViewModel,
                "Settings" => SettingsViewModel,
                _ => DashboardViewModel
            };
        }

        private void UpdateCurrentViewModelFromTab()
        {
            CurrentViewModel = SelectedTabIndex switch
            {
                0 => DashboardViewModel,
                1 => DatabaseViewModel,
                2 => ServicesViewModel,
                3 => HealthViewModel,
                4 => MaintenanceViewModel,
                5 => MediaTransferViewModel,
                6 => SettingsViewModel,
                _ => DashboardViewModel
            };
        }

        private async System.Threading.Tasks.Task RefreshCurrentView()
        {
            if (CurrentViewModel is DashboardViewModel dashboard)
            {
                await dashboard.RefreshAsync();
            }
            else if (CurrentViewModel is ServicesViewModel services)
            {
                await services.RefreshServicesAsync();
            }
            else if (CurrentViewModel is DatabaseViewModel database)
            {
                await database.RefreshStatsAsync();
            }
        }

        private void OnOutputReceived(object? sender, PowerShellOutputEventArgs e)
        {
            StatusMessage = e.Message;
        }

        private void OnProgressChanged(object? sender, PowerShellProgressEventArgs e)
        {
            StatusMessage = $"{e.Activity}: {e.Status} ({e.PercentComplete}%)";
        }

        public void Dispose()
        {
            _wsusService.Dispose();
            _psService.Dispose();
        }

        #endregion
    }
}
