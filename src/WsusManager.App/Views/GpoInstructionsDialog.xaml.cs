using System.Windows;
using System.Windows.Input;

namespace WsusManager.App.Views;

/// <summary>
/// Dialog displaying GPO deployment instructions with copyable text.
/// Shown after GPO files are successfully copied to C:\WSUS\WSUS GPO\.
/// </summary>
public partial class GpoInstructionsDialog : Window
{
    public GpoInstructionsDialog(string instructionText)
    {
        InitializeComponent();
        TxtInstructions.Text = instructionText;

        // ESC key closes dialog (GUI-04)
        KeyDown += (s, e) =>
        {
            if (e.Key == Key.Escape)
                Close();
        };
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
