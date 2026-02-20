using WsusManager.Core.Models;

namespace WsusManager.Tests.Foundation;

public class OperationResultTests
{
    [Fact]
    public void Ok_Creates_Successful_Result()
    {
        var result = OperationResult.Ok("All good");
        Assert.True(result.Success);
        Assert.Equal("All good", result.Message);
        Assert.Null(result.Exception);
    }

    [Fact]
    public void Ok_Uses_Default_Message()
    {
        var result = OperationResult.Ok();
        Assert.True(result.Success);
        Assert.Equal("Success", result.Message);
    }

    [Fact]
    public void Fail_Creates_Failed_Result()
    {
        var ex = new InvalidOperationException("test");
        var result = OperationResult.Fail("Something broke", ex);
        Assert.False(result.Success);
        Assert.Equal("Something broke", result.Message);
        Assert.Same(ex, result.Exception);
    }

    [Fact]
    public void Fail_Without_Exception()
    {
        var result = OperationResult.Fail("Failed");
        Assert.False(result.Success);
        Assert.Null(result.Exception);
    }

    [Fact]
    public void Generic_Ok_Includes_Data()
    {
        var result = OperationResult<int>.Ok(42, "Got the answer");
        Assert.True(result.Success);
        Assert.Equal(42, result.Data);
        Assert.Equal("Got the answer", result.Message);
    }

    [Fact]
    public void Generic_Fail_Has_Default_Data()
    {
        var result = OperationResult<int>.Fail("No data");
        Assert.False(result.Success);
        Assert.Equal(0, result.Data);
    }
}
