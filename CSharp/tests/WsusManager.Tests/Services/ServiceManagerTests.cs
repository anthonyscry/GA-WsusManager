using Xunit;
using WsusManager.Core.Services;

namespace WsusManager.Tests.Services;

public class ServiceManagerTests
{
    [Fact]
    public void ServiceExists_KnownService_ReturnsTrue()
    {
        // Arrange - Windows service that should exist
        var serviceName = "Winmgmt"; // Windows Management Instrumentation

        // Act
        var result = ServiceManager.ServiceExists(serviceName);

        // Assert
        Assert.True(result);
    }

    [Fact]
    public void ServiceExists_NonExistentService_ReturnsFalse()
    {
        // Arrange
        var serviceName = "NonExistentService12345";

        // Act
        var result = ServiceManager.ServiceExists(serviceName);

        // Assert
        Assert.False(result);
    }

    [Fact]
    public void GetWsusServiceStatus_ReturnsAllServices()
    {
        // Act
        var status = ServiceManager.GetWsusServiceStatus();

        // Assert
        Assert.NotNull(status);
        Assert.Contains("SQL Server Express", status.Keys);
        Assert.Contains("WSUS Service", status.Keys);
        Assert.Contains("IIS", status.Keys);
    }

    [Fact]
    public void IsServiceRunning_WindowsService_ChecksCorrectly()
    {
        // Arrange - Service that should be running on Windows
        var serviceName = "Winmgmt";

        // Act
        var result = ServiceManager.IsServiceRunning(serviceName);

        // Assert - WMI service should be running
        Assert.True(result);
    }
}
