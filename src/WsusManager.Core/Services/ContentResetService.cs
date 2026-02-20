using WsusManager.Core.Infrastructure;
using WsusManager.Core.Logging;
using WsusManager.Core.Models;
using WsusManager.Core.Services.Interfaces;

namespace WsusManager.Core.Services;

/// <summary>
/// Runs wsusutil.exe reset via IProcessRunner to re-verify content files.
/// The wsusutil executable is located at C:\Program Files\Update Services\Tools\wsusutil.exe.
/// Output is streamed to the progress reporter. No timeout is applied.
/// </summary>
public class ContentResetService : IContentResetService
{
    private readonly IProcessRunner _processRunner;
    private readonly ILogService _logService;

    /// <summary>Standard wsusutil.exe installation path.</summary>
    public static readonly string WsusUtilPath =
        @"C:\Program Files\Update Services\Tools\wsusutil.exe";

    public ContentResetService(IProcessRunner processRunner, ILogService logService)
    {
        _processRunner = processRunner;
        _logService = logService;
    }

    /// <inheritdoc/>
    public async Task<OperationResult> ResetContentAsync(
        IProgress<string>? progress = null,
        CancellationToken ct = default)
    {
        try
        {
            _logService.Info("Starting content reset via wsusutil.exe reset");

            // Validate wsusutil.exe exists before attempting to run it
            if (!File.Exists(WsusUtilPath))
            {
                var msg = $"wsusutil.exe not found at: {WsusUtilPath}. " +
                          "WSUS may not be installed on this server.";
                _logService.Warning(msg);
                progress?.Report($"[FAIL] {msg}");
                return OperationResult.Fail(msg);
            }

            progress?.Report("Starting wsusutil reset — this may take 10+ minutes on large content stores...");
            progress?.Report($"Executable: {WsusUtilPath}");

            var result = await _processRunner.RunAsync(
                WsusUtilPath,
                "reset",
                progress,
                ct);

            if (result.Success)
            {
                _logService.Info("wsusutil reset completed successfully (exit code 0)");
                return OperationResult.Ok("Content reset completed successfully.");
            }
            else
            {
                var msg = $"wsusutil reset failed with exit code {result.ExitCode}.";
                _logService.Warning(msg);
                return OperationResult.Fail(msg);
            }
        }
        catch (OperationCanceledException)
        {
            _logService.Info("Content reset cancelled by user");
            throw;
        }
        catch (Exception ex)
        {
            _logService.Error(ex, "Content reset failed with unexpected error");
            return OperationResult.Fail($"Content reset failed: {ex.Message}", ex);
        }
    }
}
