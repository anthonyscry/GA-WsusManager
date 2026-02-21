namespace WsusManager.Core.Models;

/// <summary>
/// Options for the WSUS + SQL Server Express installation wizard.
/// All fields are collected via the GUI dialog before installation begins.
/// </summary>
public record InstallOptions
{
    /// <summary>
    /// Path to the directory containing SQL Express and optional SSMS installers.
    /// Default: C:\WSUS\SQLDB.
    /// </summary>
    public string InstallerPath { get; init; } = @"C:\WSUS\SQLDB";

    /// <summary>
    /// SQL Server SA account username.
    /// Default: sa.
    /// </summary>
    public string SaUsername { get; init; } = "sa";

    /// <summary>
    /// SQL Server SA account password.
    /// Must be at least 15 characters with at least 1 digit and 1 special character.
    /// </summary>
    public string SaPassword { get; init; } = string.Empty;

    /// <summary>
    /// Whether to also install SQL Server Management Studio (if SSMS-Setup-ENU.exe is present).
    /// </summary>
    public bool InstallSsms { get; init; }
}
