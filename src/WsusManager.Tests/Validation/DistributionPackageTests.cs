namespace WsusManager.Tests.Validation;

/// <summary>
/// Validates the C# distribution package contents.
/// Tests skip if the distribution directory is not found.
/// Set WSUS_DIST_PATH environment variable to the dist directory,
/// or tests will search common output locations.
/// </summary>
public class DistributionPackageTests
{
    private const string ExeName = "WsusManager.exe";

    /// <summary>
    /// Finds the distribution directory. Checks WSUS_DIST_PATH env var first.
    /// </summary>
    private static string? FindDistDirectory()
    {
        var envPath = Environment.GetEnvironmentVariable("WSUS_DIST_PATH");
        if (!string.IsNullOrEmpty(envPath) && Directory.Exists(envPath))
            return envPath;

        var testDir = AppContext.BaseDirectory;

        var searchPaths = new[]
        {
            Path.Combine(testDir, "..", "..", "..", "..", "..", "dist-csharp"),
            Path.Combine(testDir, "..", "..", "..", "..", "..", "publish"),
        };

        foreach (var path in searchPaths)
        {
            var fullPath = Path.GetFullPath(path);
            if (Directory.Exists(fullPath) && File.Exists(Path.Combine(fullPath, ExeName)))
                return fullPath;
        }

        return null;
    }

    [Fact]
    public void Package_ContainsExe()
    {
        var distDir = FindDistDirectory();
        if (distDir is null) return;

        Assert.True(File.Exists(Path.Combine(distDir, ExeName)),
            $"Expected {ExeName} in {distDir}");
    }

    [Fact]
    public void Package_ContainsDomainController()
    {
        var distDir = FindDistDirectory();
        if (distDir is null) return;

        Assert.True(Directory.Exists(Path.Combine(distDir, "DomainController")),
            $"Expected DomainController/ directory in {distDir}");
    }

    [Fact]
    public void Package_DoesNotContainPowerShellFolders()
    {
        var distDir = FindDistDirectory();
        if (distDir is null) return;

        Assert.False(Directory.Exists(Path.Combine(distDir, "Scripts")),
            "C# distribution should NOT contain Scripts/ folder");
        Assert.False(Directory.Exists(Path.Combine(distDir, "Modules")),
            "C# distribution should NOT contain Modules/ folder");
    }

    [Fact]
    public void Package_ExeSizeReasonable()
    {
        var distDir = FindDistDirectory();
        if (distDir is null) return;

        var exePath = Path.Combine(distDir, ExeName);
        var sizeMB = new FileInfo(exePath).Length / (1024.0 * 1024);

        Assert.True(sizeMB > 1, $"EXE should be > 1 MB, was {sizeMB:F1} MB");
        Assert.True(sizeMB < 100, $"EXE should be < 100 MB, was {sizeMB:F1} MB");
    }

    [Fact]
    public void Package_TotalSizeReasonable()
    {
        var distDir = FindDistDirectory();
        if (distDir is null) return;

        var totalBytes = Directory.GetFiles(distDir, "*", SearchOption.AllDirectories)
            .Sum(f => new FileInfo(f).Length);
        var totalMB = totalBytes / (1024.0 * 1024);

        Assert.True(totalMB < 150, $"Total package should be < 150 MB, was {totalMB:F1} MB");
    }
}
