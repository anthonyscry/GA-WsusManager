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

    // ─── Edge Case Tests (Phase 18-02) ────────────────────────────────────────

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("\t\n")]
    public void Ok_Handles_Null_Empty_Whitespace_Messages(string message)
    {
        var result = OperationResult.Ok(message);

        Assert.True(result.Success);
        // Message should be the provided value
        Assert.Equal(message, result.Message);
    }

    [Fact]
    public void Ok_Handles_Null_Message()
    {
        var result = OperationResult.Ok(null!);

        Assert.True(result.Success);
        // Null message is stored as-is
        Assert.Null(result.Message);
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("\t\n")]
    public void Fail_Handles_Null_Empty_Whitespace_Messages(string message)
    {
        var result = OperationResult.Fail(message);

        Assert.False(result.Success);
        // Message should be the provided value
        Assert.Equal(message, result.Message);
    }

    [Fact]
    public void Fail_Handles_Null_Message()
    {
        var result = OperationResult.Fail((string)null!);

        Assert.False(result.Success);
        // Null message is stored as-is
        Assert.Null(result.Message);
    }

    [Fact]
    public void Ok_Handles_Very_Long_Message()
    {
        // Very long message (>1000 chars)
        var longMessage = new string('a', 10000);
        var result = OperationResult.Ok(longMessage);

        Assert.True(result.Success);
        Assert.Equal(10000, result.Message.Length);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    [InlineData(int.MaxValue)]
    [InlineData(int.MinValue)]
    public void Generic_Fail_Handles_Boundary_Error_Codes(int errorCode)
    {
        var result = OperationResult<int>.Fail("Test", null);

        Assert.False(result.Success);
        // OperationResult<T>.Fail doesn't accept custom data value - uses default
        Assert.Equal(0, result.Data);
    }

    [Theory]
    [InlineData(null)]
    [InlineData(0)]
    [InlineData(-1)]
    [InlineData(int.MaxValue)]
    public void Generic_Ok_Handles_Null_And_Boundary_Data(int? data)
    {
        var result = OperationResult<int?>.Ok(data, "Test");

        Assert.True(result.Success);
        Assert.Equal(data, result.Data);
    }

    [Fact]
    public void Generic_Ok_Handles_Default_Data_For_Value_Types()
    {
        var result = OperationResult<int>.Ok(default, "Test");

        Assert.True(result.Success);
        Assert.Equal(0, result.Data);
    }

    [Fact]
    public void Generic_Ok_Handles_Null_Data_For_Reference_Types()
    {
        var result = OperationResult<string>.Ok(null!, "Test");

        Assert.True(result.Success);
        Assert.Null(result.Data);
    }

    [Theory]
    [InlineData(true, "")]
    [InlineData(true, "   ")]
    [InlineData(false, "")]
    [InlineData(false, "   ")]
    public void OperationResult_Combines_Success_And_Message_Correctly(bool success, string message)
    {
        var result = success
            ? OperationResult.Ok(message)
            : OperationResult.Fail(message);

        Assert.Equal(success, result.Success);
        Assert.Equal(message, result.Message);
    }

    [Fact]
    public void OperationResult_Handles_Null_Message()
    {
        var result = OperationResult.Fail((string)null!);

        Assert.False(result.Success);
        Assert.Null(result.Message);
    }

    [Fact]
    public void OperationResult_Handles_Exception_With_Null_Message()
    {
        var ex = new InvalidOperationException("test");
        var result = OperationResult.Fail(null!, ex);

        Assert.False(result.Success);
        Assert.Null(result.Message);
        Assert.Same(ex, result.Exception);
    }

    [Fact]
    public void Generic_Ok_Handles_Message_With_Special_Characters()
    {
        var specialMessage = "Test\n\r\t\"'\\\0🚀";
        var result = OperationResult.Ok(specialMessage);

        Assert.True(result.Success);
        Assert.Equal(specialMessage, result.Message);
    }

    [Theory]
    [InlineData(byte.MinValue)]
    [InlineData(byte.MaxValue)]
    [InlineData(short.MinValue)]
    [InlineData(short.MaxValue)]
    [InlineData(long.MaxValue)]
    [InlineData(long.MinValue)]
    public void Generic_Fail_Handles_Various_Numeric_Types_Boundaries<T>(T value)
        where T : struct
    {
        var result = OperationResult<T>.Fail("Test", null);

        Assert.False(result.Success);
        // Data is default value for the type
        Assert.Equal(default(T), result.Data);
    }
}
