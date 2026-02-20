using WsusManager.Core.Models;

namespace WsusManager.Core.Services.Interfaces;

/// <summary>
/// Service for copying GPO deployment files from the application's DomainController/ directory
/// to C:\WSUS\WSUS GPO\ and returning step-by-step instructions for the DC admin.
/// </summary>
public interface IGpoDeploymentService
{
    /// <summary>
    /// Copies GPO files to the destination directory and returns instruction text on success.
    /// </summary>
    Task<OperationResult<string>> DeployGpoFilesAsync(IProgress<string>? progress = null, CancellationToken ct = default);
}
