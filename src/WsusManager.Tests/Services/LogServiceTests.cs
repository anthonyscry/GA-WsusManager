using WsusManager.Core.Logging;

namespace WsusManager.Tests.Services;

/// <summary>
/// Tests for LogService: initialization, log directory creation,
/// Flush(), and Dispose() safety.
/// </summary>
public class LogServiceTests : IDisposable
{
    private readonly string _tempDir;

    public LogServiceTests()
    {
        _tempDir = Path.Combine(Path.GetTempPath(), $"WsusManagerLogTests_{Guid.NewGuid():N}");
    }

    public void Dispose()
    {
        try { Directory.Delete(_tempDir, recursive: true); } catch { }
    }

    [Fact]
    public void Constructor_Creates_Log_Directory_If_Missing()
    {
        Assert.False(Directory.Exists(_tempDir));

        using var svc = new LogService(_tempDir);

        Assert.True(Directory.Exists(_tempDir));
    }

    [Fact]
    public void Info_Does_Not_Throw()
    {
        using var svc = new LogService(_tempDir);

        var ex = Record.Exception(() => svc.Info("Test message {Value}", 42));

        Assert.Null(ex);
    }

    [Fact]
    public void Warning_And_Error_Do_Not_Throw()
    {
        using var svc = new LogService(_tempDir);

        var ex = Record.Exception(() =>
        {
            svc.Warning("Warning {Code}", 100);
            svc.Error("Error {Code}", 500);
            svc.Error(new InvalidOperationException("test"), "Error with exception");
            svc.Debug("Debug message");
            svc.Fatal("Fatal message");
            svc.Fatal(new Exception("fatal"), "Fatal with exception");
        });

        Assert.Null(ex);
    }

    [Fact]
    public void LogStartup_Does_Not_Throw()
    {
        using var svc = new LogService(_tempDir);

        var ex = Record.Exception(() => svc.LogStartup("4.0.0", 250));

        Assert.Null(ex);
    }

    [Fact]
    public void Dispose_Can_Be_Called_Multiple_Times()
    {
        var svc = new LogService(_tempDir);
        svc.Dispose();

        var ex = Record.Exception(() => svc.Dispose());

        Assert.Null(ex);
    }

    [Fact]
    public void Flush_Does_Not_Throw()
    {
        using var svc = new LogService(_tempDir);

        var ex = Record.Exception(() => svc.Flush());

        Assert.Null(ex);
    }
}
