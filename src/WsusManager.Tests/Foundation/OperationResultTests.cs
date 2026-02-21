using WsusManager.Core.Models;

namespace WsusManager.Tests.Foundation;

// ────────────────────────────────────────────────────────────────────────────────
// EDGE CASE AUDIT (Phase 18-02):
// ────────────────────────────────────────────────────────────────────────────────
// Foundation type - used throughout application:
// [x] Null message: Ok(null) - tested (default message)
// [x] Null exception: Fail("msg", null) - tested
// [ ] Empty message: Ok(""), Fail("") - missing
// [ ] Whitespace message: "   ", "\t\n" - missing
// [ ] Very long message (>1000 chars) - missing
// [ ] Null data in generic: Ok<T>(null, ...) - missing
// [ ] Boundary: Success flag with null/empty/whitespace combinations - missing
// [ ] Theory with multiple boundary values - missing (0, -1, int.MaxValue for error codes)
// ────────────────────────────────────────────────────────────────────────────────

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

    [Fact]
    public void Generic_Fail_With_Exception()
    {
        var ex = new TimeoutException("timed out");
        var result = OperationResult<string>.Fail("Timed out", ex);

        Assert.False(result.Success);
        Assert.Null(result.Data);
        Assert.Same(ex, result.Exception);
    }

    [Fact]
    public void Generic_Ok_Default_Message()
    {
        var result = OperationResult<bool>.Ok(true);

        Assert.True(result.Success);
        Assert.True(result.Data);
        Assert.Equal("Success", result.Message);
    }

    [Fact]
    public void Ok_And_Fail_Are_Distinct_By_Success_Flag()
    {
        var ok = OperationResult.Ok("done");
        var fail = OperationResult.Fail("error");

        Assert.True(ok.Success);
        Assert.False(fail.Success);
        Assert.NotEqual(ok, fail);
    }

    [Fact]
    public void Records_Support_Value_Equality()
    {
        var a = OperationResult.Ok("done");
        var b = OperationResult.Ok("done");

        Assert.Equal(a, b);
    }

    [Fact]
    public void Generic_Records_Support_Value_Equality()
    {
        var a = OperationResult<int>.Ok(42, "answer");
        var b = OperationResult<int>.Ok(42, "answer");

        Assert.Equal(a, b);
    }
}
