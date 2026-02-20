namespace WsusManager.Core.Models;

/// <summary>
/// Result of an external process execution.
/// </summary>
public record ProcessResult(int ExitCode, IReadOnlyList<string> OutputLines)
{
    /// <summary>True if the process exited with code 0.</summary>
    public bool Success => ExitCode == 0;

    /// <summary>All output as a single string.</summary>
    public string Output => string.Join(Environment.NewLine, OutputLines);
}
