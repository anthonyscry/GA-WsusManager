using Moq;
using WsusManager.Core.Logging;
using WsusManager.Core.Services;

namespace WsusManager.Tests.Services;

/// <summary>
/// Tests for GpoDeploymentService: source directory validation,
/// destination directory creation, instruction text content, and file copying.
/// </summary>
public class GpoDeploymentServiceTests
{
    private readonly Mock<ILogService> _mockLog = new();

    private GpoDeploymentService CreateService() =>
        new(_mockLog.Object);

    [Fact]
    public async Task Deploy_Returns_Failure_When_Source_Not_Found()
    {
        var service = CreateService();

        // In test environment, DomainController/ won't be next to the test DLL
        var result = await service.DeployGpoFilesAsync();

        Assert.False(result.Success);
        Assert.Contains("DomainController", result.Message);
    }

    [Fact]
    public void BuildInstructionText_Contains_Required_Steps()
    {
        var text = GpoDeploymentService.BuildInstructionText();

        Assert.Contains(@"C:\WSUS\WSUS GPO", text);
        Assert.Contains("Domain Controller", text);
        Assert.Contains("Set-WsusGroupPolicy.ps1", text);
        Assert.Contains("gpupdate /force", text);
        Assert.Contains("wuauclt /detectnow", text);
    }

    [Fact]
    public void CopyDirectory_Copies_Files_Recursively()
    {
        var sourceDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        var destDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());

        try
        {
            // Create source structure
            Directory.CreateDirectory(Path.Combine(sourceDir, "SubDir"));
            File.WriteAllText(Path.Combine(sourceDir, "file1.txt"), "content1");
            File.WriteAllText(Path.Combine(sourceDir, "SubDir", "file2.txt"), "content2");

            var count = GpoDeploymentService.CopyDirectory(sourceDir, destDir, null);

            Assert.Equal(2, count);
            Assert.True(File.Exists(Path.Combine(destDir, "file1.txt")));
            Assert.True(File.Exists(Path.Combine(destDir, "SubDir", "file2.txt")));
            Assert.Equal("content1", File.ReadAllText(Path.Combine(destDir, "file1.txt")));
            Assert.Equal("content2", File.ReadAllText(Path.Combine(destDir, "SubDir", "file2.txt")));
        }
        finally
        {
            if (Directory.Exists(sourceDir)) Directory.Delete(sourceDir, true);
            if (Directory.Exists(destDir)) Directory.Delete(destDir, true);
        }
    }

    [Fact]
    public void CopyDirectory_Overwrites_Existing_Files()
    {
        var sourceDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        var destDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());

        try
        {
            Directory.CreateDirectory(sourceDir);
            Directory.CreateDirectory(destDir);
            File.WriteAllText(Path.Combine(sourceDir, "file.txt"), "new content");
            File.WriteAllText(Path.Combine(destDir, "file.txt"), "old content");

            GpoDeploymentService.CopyDirectory(sourceDir, destDir, null);

            Assert.Equal("new content", File.ReadAllText(Path.Combine(destDir, "file.txt")));
        }
        finally
        {
            if (Directory.Exists(sourceDir)) Directory.Delete(sourceDir, true);
            if (Directory.Exists(destDir)) Directory.Delete(destDir, true);
        }
    }

    [Fact]
    public void SourceDirectoryName_Is_DomainController()
    {
        Assert.Equal("DomainController", GpoDeploymentService.SourceDirectoryName);
    }

    [Fact]
    public void DefaultDestination_Is_Correct()
    {
        Assert.Equal(@"C:\WSUS\WSUS GPO", GpoDeploymentService.DefaultDestination);
    }

    [Fact]
    public void GetSearchPaths_Returns_Two_Paths()
    {
        var service = CreateService();
        var paths = service.GetSearchPaths();

        Assert.Equal(2, paths.Length);
        Assert.All(paths, p => Assert.Contains(GpoDeploymentService.SourceDirectoryName, p));
    }

    [Fact]
    public void LocateSourceDirectory_Returns_Null_When_Directory_Missing()
    {
        var service = CreateService();

        // In test environment, DomainController/ won't be next to the test assembly
        var result = service.LocateSourceDirectory();

        Assert.Null(result);
    }

    [Fact]
    public void CopyDirectory_Returns_Zero_For_Empty_Source()
    {
        var sourceDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        var destDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());

        try
        {
            Directory.CreateDirectory(sourceDir);

            var count = GpoDeploymentService.CopyDirectory(sourceDir, destDir, null);

            Assert.Equal(0, count);
        }
        finally
        {
            if (Directory.Exists(sourceDir)) Directory.Delete(sourceDir, true);
            if (Directory.Exists(destDir)) Directory.Delete(destDir, true);
        }
    }
}
