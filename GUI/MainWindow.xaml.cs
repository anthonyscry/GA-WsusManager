using System;
using System.Windows;
using WsusManager.ViewModels;

namespace WsusManager
{
    public partial class MainWindow : Window
    {
        public MainWindow()
        {
            InitializeComponent();

            // Set DataContext here (after App.OnStartup has run and App.ModulesPath is initialized)
            DataContext = new MainViewModel();

            Closed += OnClosed;
        }

        private void OnClosed(object? sender, EventArgs e)
        {
            if (DataContext is MainViewModel viewModel)
            {
                viewModel.Dispose();
            }
        }
    }
}
