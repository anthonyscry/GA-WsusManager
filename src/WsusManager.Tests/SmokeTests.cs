namespace WsusManager.Tests;

/// <summary>
/// Basic smoke tests to verify the solution compiles and core types are accessible.
/// </summary>
public class SmokeTests
{
    [Fact]
    public void Solution_Compiles_And_Core_Types_Accessible()
    {
        // Verify that the Core project's assembly is loadable
        var coreAssembly = typeof(WsusManager.Core.Models.OperationResult).Assembly;
        Assert.NotNull(coreAssembly);
    }
}
