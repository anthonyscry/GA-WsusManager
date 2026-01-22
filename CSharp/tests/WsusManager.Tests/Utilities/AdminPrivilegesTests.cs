using Xunit;
using WsusManager.Core.Utilities;

namespace WsusManager.Tests.Utilities;

public class AdminPrivilegesTests
{
    [Fact]
    public void IsAdmin_ReturnsBoolean()
    {
        // Act
        var result = AdminPrivileges.IsAdmin();

        // Assert
        Assert.IsType<bool>(result);
    }

    [Fact]
    public void GetCurrentUser_ReturnsValidUser()
    {
        // Act
        var (domain, username) = AdminPrivileges.GetCurrentUser();

        // Assert
        Assert.NotEmpty(domain);
        Assert.NotEmpty(username);
    }

    [Fact]
    public void RequireAdmin_WhenNotAdmin_ThrowsException()
    {
        // Skip test if running as admin
        if (AdminPrivileges.IsAdmin())
        {
            return; // Skip test when running as admin
        }

        // Act & Assert
        Assert.Throws<UnauthorizedAccessException>(() =>
            AdminPrivileges.RequireAdmin(throwOnFail: true));
    }
}
