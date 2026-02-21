using System.Windows;
using System.Windows.Input;

namespace WsusManager.App.Views;

/// <summary>
/// Dialog displaying GPO deployment instructions with copyable text.
/// Shown after GPO files are successfully copied to C:\WSUS\WSUS GPO\.
/// </summary>
public partial class GpoInstructionsDialog : Window
{
    private KeyEventHandler? _escHandler;

    public GpoInstructionsDialog(string instructionText)
    {
        InitializeComponent();
        TxtInstructions.Text = instructionText;

        // ESC key closes dialog (GUI-04)
        // Store handler reference for cleanup to prevent memory leak
        _escHandler = (s, e) =>
        {
            if (e.Key == Key.Escape)
                Close();
        };
        KeyDown += _escHandler;
        Closed += Dialog_Closed;
    }

    private void Dialog_Closed(object? sender, EventArgs e)
    {
        // Cleanup event handlers to prevent memory leaks
        if (_escHandler != null)
        {
            KeyDown -= _escHandler;
            _escHandler = null;
        }
        Closed -= Dialog_Closed;
    }

    private void CopyToClipboard_Click(object sender, RoutedEventArgs e)
    {
        Clipboard.SetText(TxtInstructions.Text);
    }

    private void Close_Click(object sender, RoutedEventArgs e)
    {
        Close();
    }
}
