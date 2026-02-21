using WsusManager.Core.Services;
using WsusManager.Core.Services.Interfaces;
using Xunit;

namespace WsusManager.Tests.Services;

/// <summary>
/// Unit tests for <see cref="ScriptGeneratorService"/>.
/// Verifies that each operation type produces a valid, self-contained PowerShell script.
/// </summary>
public class ScriptGeneratorServiceTests
{
    private readonly IScriptGeneratorService _sut = new ScriptGeneratorService();

    // -------------------------------------------------------------------------
    // GetAvailableOperations
    // -------------------------------------------------------------------------

    [Fact]
    public void GetAvailableOperations_Returns_Five_Items()
    {
        var ops = _sut.GetAvailableOperations();
        Assert.Equal(5, ops.Count);
    }

    [Theory]
    [InlineData("Cancel Stuck Jobs")]
    [InlineData("Force Check-In")]
    [InlineData("Test Connectivity")]
    [InlineData("Run Diagnostics")]
    [InlineData("Mass GPUpdate")]
    public void GetAvailableOperations_Contains_Expected_Names(string expectedName)
    {
        var ops = _sut.GetAvailableOperations();
        Assert.Contains(expectedName, ops);
    }

    // -------------------------------------------------------------------------
    // All scripts must contain #Requires -RunAsAdministrator
    // -------------------------------------------------------------------------

    [Theory]
    [InlineData("Cancel Stuck Jobs")]
    [InlineData("Force Check-In")]
    [InlineData("Test Connectivity")]
    [InlineData("Run Diagnostics")]
    [InlineData("Mass GPUpdate")]
    public void GenerateScript_AllOperations_Contain_RequiresRunAsAdministrator(string operationType)
    {
        var script = _sut.GenerateScript(operationType);
        Assert.Contains("#Requires -RunAsAdministrator", script);
    }

    // -------------------------------------------------------------------------
    // Scripts must contain the WSUS Manager header
    // -------------------------------------------------------------------------

    [Theory]
    [InlineData("Cancel Stuck Jobs")]
    [InlineData("Force Check-In")]
    [InlineData("Test Connectivity")]
    [InlineData("Run Diagnostics")]
    [InlineData("Mass GPUpdate")]
    public void GenerateScript_AllOperations_Contain_WsusManagerHeader(string operationType)
    {
        var script = _sut.GenerateScript(operationType);
        Assert.Contains("# WSUS Manager -", script);
        Assert.Contains("# Generated:", script);
        Assert.Contains("# Run this script on the target host as Administrator.", script);
    }

    // -------------------------------------------------------------------------
    // Scripts must end with the standard Read-Host pause
    // -------------------------------------------------------------------------

    [Theory]
    [InlineData("Cancel Stuck Jobs")]
    [InlineData("Force Check-In")]
    [InlineData("Test Connectivity")]
    [InlineData("Run Diagnostics")]
    [InlineData("Mass GPUpdate")]
    public void GenerateScript_AllOperations_Contain_EndingPause(string operationType)
    {
        var script = _sut.GenerateScript(operationType);
        Assert.Contains("Script complete. Press Enter to exit.", script);
        Assert.Contains("Read-Host", script);
    }

    // -------------------------------------------------------------------------
    // CancelStuckJobs
    // -------------------------------------------------------------------------

    [Fact]
    public void GenerateScript_CancelStuckJobs_Contains_StopService()
    {
        var script = _sut.GenerateScript("Cancel Stuck Jobs");
        Assert.Contains("Stop-Service wuauserv", script);
        Assert.Contains("Stop-Service bits", script);
    }

    [Fact]
    public void GenerateScript_CancelStuckJobs_Contains_ClearCache()
    {
        var script = _sut.GenerateScript("Cancel Stuck Jobs");
        Assert.Contains("SoftwareDistribution", script);
        Assert.Contains("Remove-Item", script);
    }

    [Fact]
    public void GenerateScript_CancelStuckJobs_Contains_StartService()
    {
        var script = _sut.GenerateScript("Cancel Stuck Jobs");
        Assert.Contains("Start-Service bits", script);
        Assert.Contains("Start-Service wuauserv", script);
    }

    [Fact]
    public void GenerateScript_CancelStuckJobs_AcceptsInternalKey()
    {
        var script = _sut.GenerateScript("CancelStuckJobs");
        Assert.Contains("#Requires -RunAsAdministrator", script);
        Assert.Contains("Stop-Service wuauserv", script);
    }

    // -------------------------------------------------------------------------
    // ForceCheckIn
    // -------------------------------------------------------------------------

    [Fact]
    public void GenerateScript_ForceCheckIn_Contains_GpUpdate()
    {
        var script = _sut.GenerateScript("Force Check-In");
        Assert.Contains("gpupdate /force", script);
    }

    [Fact]
    public void GenerateScript_ForceCheckIn_Contains_WuaucltCommands()
    {
        var script = _sut.GenerateScript("Force Check-In");
        Assert.Contains("wuauclt /resetauthorization", script);
        Assert.Contains("wuauclt /detectnow", script);
        Assert.Contains("wuauclt /reportnow", script);
    }

    [Fact]
    public void GenerateScript_ForceCheckIn_Contains_UsoclientBlock()
    {
        var script = _sut.GenerateScript("Force Check-In");
        Assert.Contains("usoclient", script);
        Assert.Contains("StartScan", script);
    }

    [Fact]
    public void GenerateScript_ForceCheckIn_AcceptsInternalKey()
    {
        var script = _sut.GenerateScript("ForceCheckIn");
        Assert.Contains("gpupdate /force", script);
    }

    // -------------------------------------------------------------------------
    // TestConnectivity
    // -------------------------------------------------------------------------

    [Fact]
    public void GenerateScript_TestConnectivity_Contains_WsusServerUrl()
    {
        var script = _sut.GenerateScript("Test Connectivity", wsusServerUrl: "http://wsus-lab:8530");
        Assert.Contains("wsus-lab", script);
    }

    [Fact]
    public void GenerateScript_TestConnectivity_Contains_Port_Tests()
    {
        var script = _sut.GenerateScript("Test Connectivity", wsusServerUrl: "http://wsus-lab:8530");
        Assert.Contains("8530", script);
        Assert.Contains("8531", script);
        Assert.Contains("Test-NetConnection", script);
    }

    [Fact]
    public void GenerateScript_TestConnectivity_Contains_DnsResolution()
    {
        var script = _sut.GenerateScript("Test Connectivity", wsusServerUrl: "http://wsus-lab:8530");
        Assert.Contains("GetHostAddresses", script);
    }

    [Fact]
    public void GenerateScript_TestConnectivity_UsesPlaceholderWhenUrlIsNull()
    {
        var script = _sut.GenerateScript("Test Connectivity", wsusServerUrl: null);
        Assert.Contains("WSUS-SERVER", script);
    }

    [Fact]
    public void GenerateScript_TestConnectivity_ExtractsHostnameFromUrl()
    {
        var script = _sut.GenerateScript("Test Connectivity", wsusServerUrl: "http://my-wsus-host.domain.local:8530");
        Assert.Contains("my-wsus-host.domain.local", script);
        // Should not contain the port number as part of the hostname assignment
        Assert.Contains("$WsusServer = \"my-wsus-host.domain.local\"", script);
    }

    [Fact]
    public void GenerateScript_TestConnectivity_AcceptsInternalKey()
    {
        var script = _sut.GenerateScript("TestConnectivity", wsusServerUrl: "http://wsus-lab:8530");
        Assert.Contains("wsus-lab", script);
    }

    // -------------------------------------------------------------------------
    // RunDiagnostics
    // -------------------------------------------------------------------------

    [Fact]
    public void GenerateScript_RunDiagnostics_Contains_RegistryRead()
    {
        var script = _sut.GenerateScript("Run Diagnostics");
        Assert.Contains("WUServer", script);
        Assert.Contains("WUStatusServer", script);
        Assert.Contains("UseWUServer", script);
    }

    [Fact]
    public void GenerateScript_RunDiagnostics_Contains_ServiceStatusCheck()
    {
        var script = _sut.GenerateScript("Run Diagnostics");
        Assert.Contains("Get-Service", script);
        Assert.Contains("wuauserv", script);
        Assert.Contains("bits", script);
        Assert.Contains("cryptsvc", script);
    }

    [Fact]
    public void GenerateScript_RunDiagnostics_Contains_PendingRebootCheck()
    {
        var script = _sut.GenerateScript("Run Diagnostics");
        Assert.Contains("RebootRequired", script);
    }

    [Fact]
    public void GenerateScript_RunDiagnostics_Contains_AgentVersionRead()
    {
        var script = _sut.GenerateScript("Run Diagnostics");
        Assert.Contains("AgentVersion", script);
    }

    [Fact]
    public void GenerateScript_RunDiagnostics_AcceptsInternalKey()
    {
        var script = _sut.GenerateScript("RunDiagnostics");
        Assert.Contains("WUServer", script);
    }

    // -------------------------------------------------------------------------
    // MassGpUpdate
    // -------------------------------------------------------------------------

    [Fact]
    public void GenerateScript_MassGpUpdate_Contains_ProvidedHostnames()
    {
        var hosts = new[] { "MACHINE01", "MACHINE02", "MACHINE03" };
        var script = _sut.GenerateScript("Mass GPUpdate", hostnames: hosts);

        Assert.Contains("MACHINE01", script);
        Assert.Contains("MACHINE02", script);
        Assert.Contains("MACHINE03", script);
    }

    [Fact]
    public void GenerateScript_MassGpUpdate_NullHostnames_GeneratesPlaceholderTemplate()
    {
        var script = _sut.GenerateScript("Mass GPUpdate", hostnames: null);
        Assert.Contains("HOST1", script);
        Assert.Contains("HOST2", script);
        Assert.Contains("HOST3", script);
    }

    [Fact]
    public void GenerateScript_MassGpUpdate_EmptyHostnames_GeneratesPlaceholderTemplate()
    {
        var script = _sut.GenerateScript("Mass GPUpdate", hostnames: Array.Empty<string>());
        Assert.Contains("HOST1", script);
        Assert.Contains("HOST2", script);
    }

    [Fact]
    public void GenerateScript_MassGpUpdate_Contains_TestWSMan()
    {
        var script = _sut.GenerateScript("Mass GPUpdate");
        Assert.Contains("Test-WSMan", script);
    }

    [Fact]
    public void GenerateScript_MassGpUpdate_Contains_InvokeCommand()
    {
        var script = _sut.GenerateScript("Mass GPUpdate");
        Assert.Contains("Invoke-Command", script);
    }

    [Fact]
    public void GenerateScript_MassGpUpdate_Contains_GpUpdate()
    {
        var script = _sut.GenerateScript("Mass GPUpdate");
        Assert.Contains("gpupdate /force", script);
    }

    [Fact]
    public void GenerateScript_MassGpUpdate_Contains_SummaryOutput()
    {
        var script = _sut.GenerateScript("Mass GPUpdate");
        Assert.Contains("Summary", script);
        Assert.Contains("passed", script);
        Assert.Contains("failed", script);
    }

    [Fact]
    public void GenerateScript_MassGpUpdate_AcceptsInternalKey()
    {
        var script = _sut.GenerateScript("MassGpUpdate");
        Assert.Contains("#Requires -RunAsAdministrator", script);
    }

    // -------------------------------------------------------------------------
    // Unknown operation type
    // -------------------------------------------------------------------------

    [Fact]
    public void GenerateScript_UnknownOperationType_ThrowsArgumentException()
    {
        Assert.Throws<ArgumentException>(() => _sut.GenerateScript("UnknownOperation"));
    }

    [Fact]
    public void GenerateScript_EmptyOperationType_ThrowsArgumentException()
    {
        Assert.Throws<ArgumentException>(() => _sut.GenerateScript(string.Empty));
    }

    // -------------------------------------------------------------------------
    // No external dependencies
    // -------------------------------------------------------------------------

    [Theory]
    [InlineData("Cancel Stuck Jobs")]
    [InlineData("Force Check-In")]
    [InlineData("Run Diagnostics")]
    [InlineData("Mass GPUpdate")]
    public void GenerateScript_AllOperations_DoNotContainImportModule(string operationType)
    {
        var script = _sut.GenerateScript(operationType);
        Assert.DoesNotContain("Import-Module", script);
    }
}
