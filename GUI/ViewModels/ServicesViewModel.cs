using System;
using System.Collections.ObjectModel;
using System.Threading.Tasks;
using System.Windows.Input;
using WsusManager.Helpers;
using WsusManager.Models;
using WsusManager.Services;

namespace WsusManager.ViewModels
{
    public class ServicesViewModel : ViewModelBase
    {
        private readonly WsusService _wsusService;

        private bool _isLoading;
        private ServiceStatus? _selectedService;
        private string _statusMessage = string.Empty;

        public ServicesViewModel(WsusService wsusService)
        {
            _wsusService = wsusService;

            Services = new ObservableCollection<ServiceStatus>();

            // Commands
            RefreshCommand = new AsyncRelayCommand(RefreshServicesAsync);
            StartServiceCommand = new AsyncRelayCommand(StartSelectedServiceAsync, () => SelectedService != null && !SelectedService.IsRunning);
            StopServiceCommand = new AsyncRelayCommand(StopSelectedServiceAsync, () => SelectedService != null && SelectedService.IsRunning);
            RestartServiceCommand = new AsyncRelayCommand(RestartSelectedServiceAsync, () => SelectedService != null);
            StartAllCommand = new AsyncRelayCommand(StartAllServicesAsync);
            StopAllCommand = new AsyncRelayCommand(StopAllServicesAsync);

            // Initial load
            _ = RefreshServicesAsync();
        }

        #region Properties

        public ObservableCollection<ServiceStatus> Services { get; }

        public bool IsLoading
        {
            get => _isLoading;
            set => SetProperty(ref _isLoading, value);
        }

        public ServiceStatus? SelectedService
        {
            get => _selectedService;
            set
            {
                if (SetProperty(ref _selectedService, value))
                {
                    ((AsyncRelayCommand)StartServiceCommand).RaiseCanExecuteChanged();
                    ((AsyncRelayCommand)StopServiceCommand).RaiseCanExecuteChanged();
                    ((AsyncRelayCommand)RestartServiceCommand).RaiseCanExecuteChanged();
                }
            }
        }

        public string StatusMessage
        {
            get => _statusMessage;
            set => SetProperty(ref _statusMessage, value);
        }

        #endregion

        #region Commands

        public ICommand RefreshCommand { get; }
        public ICommand StartServiceCommand { get; }
        public ICommand StopServiceCommand { get; }
        public ICommand RestartServiceCommand { get; }
        public ICommand StartAllCommand { get; }
        public ICommand StopAllCommand { get; }

        #endregion

        #region Methods

        public async Task RefreshServicesAsync()
        {
            IsLoading = true;
            StatusMessage = "Refreshing services...";

            try
            {
                var services = await _wsusService.GetServiceStatusAsync();
                Services.Clear();
                foreach (var service in services)
                {
                    Services.Add(service);
                }
                StatusMessage = $"Found {Services.Count} services";
            }
            catch (Exception ex)
            {
                StatusMessage = $"Error: {ex.Message}";
            }
            finally
            {
                IsLoading = false;
            }
        }

        private async Task StartSelectedServiceAsync()
        {
            if (SelectedService == null) return;

            IsLoading = true;
            StatusMessage = $"Starting {SelectedService.DisplayName}...";

            try
            {
                var result = await _wsusService.StartServiceAsync(SelectedService.Name);
                StatusMessage = result.Message;
                await RefreshServicesAsync();
            }
            catch (Exception ex)
            {
                StatusMessage = $"Error: {ex.Message}";
            }
            finally
            {
                IsLoading = false;
            }
        }

        private async Task StopSelectedServiceAsync()
        {
            if (SelectedService == null) return;

            IsLoading = true;
            StatusMessage = $"Stopping {SelectedService.DisplayName}...";

            try
            {
                var result = await _wsusService.StopServiceAsync(SelectedService.Name);
                StatusMessage = result.Message;
                await RefreshServicesAsync();
            }
            catch (Exception ex)
            {
                StatusMessage = $"Error: {ex.Message}";
            }
            finally
            {
                IsLoading = false;
            }
        }

        private async Task RestartSelectedServiceAsync()
        {
            if (SelectedService == null) return;

            IsLoading = true;
            StatusMessage = $"Restarting {SelectedService.DisplayName}...";

            try
            {
                await _wsusService.StopServiceAsync(SelectedService.Name);
                await _wsusService.StartServiceAsync(SelectedService.Name);
                StatusMessage = $"{SelectedService.DisplayName} restarted successfully";
                await RefreshServicesAsync();
            }
            catch (Exception ex)
            {
                StatusMessage = $"Error: {ex.Message}";
            }
            finally
            {
                IsLoading = false;
            }
        }

        private async Task StartAllServicesAsync()
        {
            IsLoading = true;
            StatusMessage = "Starting all WSUS services...";

            try
            {
                var result = await _wsusService.StartAllServicesAsync();
                StatusMessage = result.Message;
                await RefreshServicesAsync();
            }
            catch (Exception ex)
            {
                StatusMessage = $"Error: {ex.Message}";
            }
            finally
            {
                IsLoading = false;
            }
        }

        private async Task StopAllServicesAsync()
        {
            IsLoading = true;
            StatusMessage = "Stopping all WSUS services...";

            try
            {
                var result = await _wsusService.StopAllServicesAsync();
                StatusMessage = result.Message;
                await RefreshServicesAsync();
            }
            catch (Exception ex)
            {
                StatusMessage = $"Error: {ex.Message}";
            }
            finally
            {
                IsLoading = false;
            }
        }

        #endregion
    }
}
