using WsusManager.Core.Models;

namespace WsusManager.Core.Services.Interfaces;

/// <summary>
/// Runs wsusutil.exe reset to re-verify WSUS content files against the database.
/// Used after air-gap database import to fix "content is still downloading" status.
/// No timeout is applied — wsusutil reset can take 10+ minutes on large content stores.
/// </summary>
public interface IContentResetService
{
    /// <summary>
    /// Runs wsusutil.exe reset. Output is streamed to the progress reporter.
    /// Returns failure if wsusutil.exe is not found or the process exits with non-zero code.
    /// </summary>
    Task<OperationResult> ResetContentAsync(IProgress<string>? progress = null, CancellationToken ct = default);
}
