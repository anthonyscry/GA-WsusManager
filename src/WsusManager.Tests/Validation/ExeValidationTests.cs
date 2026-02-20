using System.Diagnostics;

namespace WsusManager.Tests.Validation;

/// <summary>
/// Post-build validation tests for the published single-file EXE.
/// All tests skip gracefully when the EXE is not present (e.g., during normal dotnet test).
/// These tests run AFTER dotnet publish in CI to validate the EXE artifact.
/// C# equivalent of the PowerShell Tests\ExeValidation.Tests.ps1.
/// </summary>
public class ExeValidationTests
{
    private const string ExeName = "WsusManager.App.exe";
    private const string RenamedExeName = "WsusManager.exe";

    /// <summary>
    /// Searches for the published C# EXE in common output locations.
    /// Returns null if not found (tests will skip).
    /// Checks WSUS_EXE_PATH env var first, then common publish output paths.
    /// Does NOT search dist/ (which contains the PowerShell EXE).
    /// </summary>
    private static string? FindPublishedExe()
    {
        // Allow CI to specify exact path via environment variable
        var envPath = Environment.GetEnvironmentVariable("WSUS_EXE_PATH");
        if (!string.IsNullOrEmpty(envPath) && File.Exists(envPath))
            return envPath;

        var testDir = AppContext.BaseDirectory;

        // Search paths relative to test assembly location (C# publish output only)
        var searchPaths = new[]
        {
            // dotnet publish output (standard location)
            Path.Combine(testDir, "..", "..", "..", "..", "WsusManager.App", "bin", "Release",
                "net9.0-windows", "win-x64", "publish", ExeName),
            // publish/ folder at repo src/ level
            Path.Combine(testDir, "..", "..", "..", "..", "..", "publish", ExeName),
            Path.Combine(testDir, "..", "..", "..", "..", "..", "publish", RenamedExeName),
            // Adjacent to test assembly (CI may copy here)
            Path.Combine(testDir, ExeName),
            Path.Combine(testDir, RenamedExeName),
        };

        foreach (var path in searchPaths)
        {
            var fullPath = Path.GetFullPath(path);
            if (File.Exists(fullPath))
                return fullPath;
        }

        return null;
    }

    [Fact]
    public void PeHeader_HasMzSignature()
    {
        var exePath = FindPublishedExe();
        if (exePath is null)
        {
            // Skip: EXE not found (normal during development)
            return;
        }

        using var fs = new FileStream(exePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
        var header = new byte[2];
        fs.ReadExactly(header, 0, 2);

        Assert.Equal((byte)'M', header[0]);
        Assert.Equal((byte)'Z', header[1]);
    }

    [Fact]
    public void PeHeader_HasPeSignature()
    {
        var exePath = FindPublishedExe();
        if (exePath is null) return;

        using var fs = new FileStream(exePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);

        // Read PE offset from 0x3C
        fs.Seek(0x3C, SeekOrigin.Begin);
        var offsetBytes = new byte[4];
        fs.ReadExactly(offsetBytes, 0, 4);
        var peOffset = BitConverter.ToInt32(offsetBytes, 0);

        // Read PE signature at that offset
        fs.Seek(peOffset, SeekOrigin.Begin);
        var peSignature = new byte[4];
        fs.ReadExactly(peSignature, 0, 4);

        // PE\0\0
        Assert.Equal((byte)'P', peSignature[0]);
        Assert.Equal((byte)'E', peSignature[1]);
        Assert.Equal((byte)0, peSignature[2]);
        Assert.Equal((byte)0, peSignature[3]);
    }

    [Fact]
    public void Architecture_Is64Bit()
    {
        var exePath = FindPublishedExe();
        if (exePath is null) return;

        using var fs = new FileStream(exePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);

        // Get PE offset
        fs.Seek(0x3C, SeekOrigin.Begin);
        var offsetBytes = new byte[4];
        fs.ReadExactly(offsetBytes, 0, 4);
        var peOffset = BitConverter.ToInt32(offsetBytes, 0);

        // Optional header magic is at PE offset + 4 (PE sig) + 20 (COFF header)
        var optionalHeaderOffset = peOffset + 4 + 20;
        fs.Seek(optionalHeaderOffset, SeekOrigin.Begin);
        var magic = new byte[2];
        fs.ReadExactly(magic, 0, 2);
        var magicValue = BitConverter.ToUInt16(magic, 0);

        // PE32+ = 0x020B (64-bit)
        Assert.Equal(0x020B, magicValue);
    }

    [Fact]
    public void VersionInfo_HasProductName()
    {
        var exePath = FindPublishedExe();
        if (exePath is null) return;

        var versionInfo = FileVersionInfo.GetVersionInfo(exePath);

        Assert.Equal("WSUS Manager", versionInfo.ProductName);
    }

    [Fact]
    public void VersionInfo_HasCompanyName()
    {
        var exePath = FindPublishedExe();
        if (exePath is null) return;

        var versionInfo = FileVersionInfo.GetVersionInfo(exePath);

        Assert.Equal("GA-ASI", versionInfo.CompanyName);
    }

    [Fact]
    public void VersionInfo_HasVersion()
    {
        var exePath = FindPublishedExe();
        if (exePath is null) return;

        var versionInfo = FileVersionInfo.GetVersionInfo(exePath);

        Assert.NotNull(versionInfo.FileVersion);
        Assert.StartsWith("4.0", versionInfo.FileVersion);
    }

    [Fact]
    public void FileSize_WithinExpectedRange()
    {
        var exePath = FindPublishedExe();
        if (exePath is null) return;

        var fileInfo = new FileInfo(exePath);
        var sizeMB = fileInfo.Length / (1024.0 * 1024);

        Assert.True(sizeMB > 1, $"EXE should be > 1 MB, was {sizeMB:F1} MB");
        Assert.True(sizeMB < 100, $"EXE should be < 100 MB, was {sizeMB:F1} MB");
    }
}
