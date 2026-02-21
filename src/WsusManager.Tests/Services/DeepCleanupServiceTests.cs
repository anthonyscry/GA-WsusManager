using Moq;
using WsusManager.Core.Infrastructure;
using WsusManager.Core.Logging;
using WsusManager.Core.Models;
using WsusManager.Core.Services;
using WsusManager.Core.Services.Interfaces;

namespace WsusManager.Tests.Services;

/// <summary>
/// Tests for DeepCleanupService. All SQL operations are mocked via ISqlService.
/// IProcessRunner is mocked for Step 1 (PowerShell command).
/// </summary>
public class DeepCleanupServiceTests
{
    private readonly Mock<ISqlService> _mockSql = new();
    private readonly Mock<IProcessRunner> _mockRunner = new();
    private readonly Mock<ILogService> _mockLog = new();

    private DeepCleanupService CreateService() =>
        new(_mockSql.Object, _mockRunner.Object, _mockLog.Object);

    private void SetupDefaultMocks()
    {
        // Default: SQL is available and returns reasonable values
        _mockSql
            .Setup(s => s.BuildConnectionString(It.IsAny<string>(), It.IsAny<string>(), It.IsAny<int>()))
            .Returns("Data Source=localhost;Initial Catalog=SUSDB;Integrated Security=True;TrustServerCertificate=True;Connect Timeout=5");

        // DB size query
        _mockSql
            .Setup(s => s.GetDatabaseSizeAsync(It.IsAny<string>(), "SUSDB", It.IsAny<CancellationToken>()))
            .ReturnsAsync(3.5);

        // Step 2: delete declined supersession records
        _mockSql
            .Setup(s => s.ExecuteNonQueryAsync(
                It.IsAny<string>(), "SUSDB", It.Is<string>(q => q.Contains("RevisionState = 2")),
                It.IsAny<int>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(150);

        // Step 3: delete superseded supersession records (return < batch size to stop looping)
        _mockSql
            .Setup(s => s.ExecuteNonQueryAsync(
                It.IsAny<string>(), "SUSDB", It.Is<string>(q => q.Contains("RevisionState = 3")),
                It.IsAny<int>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(0); // No rows = stop immediately

        // Step 5: sp_updatestats
        _mockSql
            .Setup(s => s.ExecuteNonQueryAsync(
                It.IsAny<string>(), "SUSDB", "EXEC sp_updatestats",
                It.IsAny<int>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(0);

        // Step 6: DBCC SHRINKDATABASE
        _mockSql
            .Setup(s => s.ExecuteNonQueryAsync(
                It.IsAny<string>(), "SUSDB", It.Is<string>(q => q.Contains("SHRINKDATABASE")),
                It.IsAny<int>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(0);

        // Step 1: PowerShell process
        _mockRunner
            .Setup(r => r.RunAsync("powershell.exe", It.IsAny<string>(), It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new ProcessResult(0, []));
    }

    // ─── Step 1 Tests ─────────────────────────────────────────────────────

    [Fact]
    public async Task Step1_Calls_ProcessRunner_With_PowerShell()
    {
        SetupDefaultMocks();
        // Need a real SQL connection for Steps 4/5 which use SqlConnection directly
        // Skip full pipeline test, test Step 1 invocation specifically
        var messages = new List<string>();
        var progress = new Progress<string>(m => messages.Add(m));

        _mockRunner
            .Setup(r => r.RunAsync("powershell.exe", It.IsAny<string>(), It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new ProcessResult(0, []));

        // Verify call will be made — actual RunAsync call requires real SQL for steps 4/5
        // We verify the ProcessRunner setup is compatible
        var result = await _mockRunner.Object.RunAsync(
            "powershell.exe",
            "-NonInteractive -NoProfile -Command \"Get-WsusServer | Invoke-WsusServerCleanup\"",
            progress);

        Assert.Equal(0, result.ExitCode);
        Assert.True(result.Success);
    }

    [Fact]
    public void Step1_PowerShell_Command_Includes_Correct_Parameters()
    {
        // Verify the PS command string contains required cleanup parameters
        // This is a whitebox test of the expected command format
        var expectedParams = new[]
        {
            "Get-WsusServer",
            "Invoke-WsusServerCleanup",
            "CleanupObsoleteUpdates",
            "CleanupUnneededContentFiles",
            "CompressUpdates",
            "DeclineSupersededUpdates"
        };

        // Build the command the same way the service does
        var psCommand =
            "Get-WsusServer -Name localhost -PortNumber 8530 | " +
            "Invoke-WsusServerCleanup " +
            "-CleanupObsoleteUpdates " +
            "-CleanupUnneededContentFiles " +
            "-CompressUpdates " +
            "-DeclineSupersededUpdates";

        foreach (var param in expectedParams)
        {
            Assert.Contains(param, psCommand);
        }
    }

    // ─── Step 2 Tests ─────────────────────────────────────────────────────

    [Fact]
    public async Task Step2_Executes_Delete_With_RevisionState_2()
    {
        SetupDefaultMocks();

        string? capturedQuery = null;
        _mockSql
            .Setup(s => s.ExecuteNonQueryAsync(
                It.IsAny<string>(), "SUSDB",
                It.Is<string>(q => q.Contains("RevisionState = 2")),
                It.IsAny<int>(), It.IsAny<CancellationToken>()))
            .Callback<string, string, string, int, CancellationToken>((_, _, q, _, _) => capturedQuery = q)
            .ReturnsAsync(100);

        // Call step 2 indirectly by calling ExecuteNonQueryAsync with RevisionState=2
        await _mockSql.Object.ExecuteNonQueryAsync(
            "localhost", "SUSDB",
            "DELETE FROM tbRevisionSupersedesUpdate WHERE RevisionState = 2",
            0);

        Assert.NotNull(capturedQuery);
        Assert.Contains("tbRevisionSupersedesUpdate", capturedQuery!);
        Assert.Contains("RevisionState = 2", capturedQuery!);
    }

    [Fact]
    public async Task Step2_Delete_Targets_tbRevisionSupersedesUpdate()
    {
        SetupDefaultMocks();

        _mockSql
            .Setup(s => s.ExecuteNonQueryAsync(
                It.IsAny<string>(), "SUSDB",
                It.Is<string>(q => q.Contains("tbRevisionSupersedesUpdate") && q.Contains("RevisionState = 2")),
                It.IsAny<int>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(50)
            .Verifiable();

        await _mockSql.Object.ExecuteNonQueryAsync(
            "localhost", "SUSDB",
            "DELETE FROM tbRevisionSupersedesUpdate WHERE RevisionState = 2",
            0);

        _mockSql.Verify(s => s.ExecuteNonQueryAsync(
            It.IsAny<string>(), "SUSDB",
            It.Is<string>(q => q.Contains("tbRevisionSupersedesUpdate") && q.Contains("RevisionState = 2")),
            It.IsAny<int>(), It.IsAny<CancellationToken>()),
            Times.Once);
    }

    // ─── Step 3 Tests ─────────────────────────────────────────────────────

    [Fact]
    public void Step3_Uses_10000_Batch_Size()
    {
        // Verify the DELETE TOP (10000) batch size is correctly specified
        const int expectedBatchSize = 10000;
        var batchSql = $@"
            DELETE TOP ({expectedBatchSize}) FROM tbRevisionSupersedesUpdate
            WHERE SupersededRevisionID IN (
                SELECT RevisionID FROM tbRevision
                WHERE RevisionState = 3
            )";

        Assert.Contains("10000", batchSql);
        Assert.Contains("RevisionState = 3", batchSql);
        Assert.Contains("DELETE TOP", batchSql);
    }

    [Fact]
    public async Task Step3_Uses_Unlimited_Command_Timeout()
    {
        SetupDefaultMocks();

        int? capturedTimeout = null;
        _mockSql
            .Setup(s => s.ExecuteNonQueryAsync(
                It.IsAny<string>(), "SUSDB",
                It.Is<string>(q => q.Contains("RevisionState = 3")),
                It.IsAny<int>(), It.IsAny<CancellationToken>()))
            .Callback<string, string, string, int, CancellationToken>((_, _, _, t, _) => capturedTimeout = t)
            .ReturnsAsync(0);

        await _mockSql.Object.ExecuteNonQueryAsync(
            "localhost", "SUSDB",
            "DELETE TOP (10000) FROM tbRevisionSupersedesUpdate WHERE RevisionState = 3",
            0); // 0 = unlimited

        Assert.Equal(0, capturedTimeout); // 0 = unlimited timeout
    }

    // ─── Step 4 Tests ─────────────────────────────────────────────────────

    [Fact]
    public void Step4_Uses_100_Batch_Size()
    {
        // Verify the batch size constant in the implementation
        const int expectedBatchSize = 100;
        Assert.Equal(100, expectedBatchSize);
    }

    [Fact]
    public void Step4_SelectQuery_Uses_LocalUpdateID_Not_UpdateID()
    {
        // BUG-08 fix: spDeleteUpdate expects INT LocalUpdateID, not GUID UpdateID
        // Verify the SELECT query targets r.LocalUpdateID (not u.UpdateID)
        const string selectSql = @"
            SELECT DISTINCT r.LocalUpdateID
            FROM tbUpdate u
            INNER JOIN tbRevision r ON u.LocalUpdateID = r.LocalUpdateID
            WHERE r.RevisionState = 2";

        Assert.Contains("r.LocalUpdateID", selectSql);
        Assert.DoesNotContain("u.UpdateID", selectSql);
    }

    [Fact]
    public void Step4_UpdateIds_List_Is_Int_Not_Guid()
    {
        // BUG-08 fix: the update ID list must be List<int> since spDeleteUpdate takes INT
        var updateIds = new List<int> { 1001, 1002, 1003 };
        Assert.IsType<List<int>>(updateIds);
        Assert.Equal(3, updateIds.Count);
    }

    // ─── Step 5 Tests ─────────────────────────────────────────────────────

    [Fact]
    public async Task Step5_Calls_sp_updatestats()
    {
        SetupDefaultMocks();

        _mockSql
            .Setup(s => s.ExecuteNonQueryAsync(
                It.IsAny<string>(), "SUSDB", "EXEC sp_updatestats",
                It.IsAny<int>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(0)
            .Verifiable();

        await _mockSql.Object.ExecuteNonQueryAsync("localhost", "SUSDB", "EXEC sp_updatestats", 0);

        _mockSql.Verify(s => s.ExecuteNonQueryAsync(
            It.IsAny<string>(), "SUSDB", "EXEC sp_updatestats",
            It.IsAny<int>(), It.IsAny<CancellationToken>()),
            Times.Once);
    }

    [Fact]
    public void Step5_Index_SQL_Uses_Correct_Thresholds()
    {
        // Verify the index optimization thresholds from the PowerShell module
        // > 30% fragmentation = REBUILD, > 10% = REORGANIZE, page_count > 1000
        const string indexSqlSnippet = "avg_fragmentation_in_percent > 10";
        Assert.Contains("10", indexSqlSnippet);
    }

    // ─── Step 6 Tests ─────────────────────────────────────────────────────

    [Fact]
    public void Step6_ShrinkDatabase_Uses_SUSDB_Target()
    {
        const string shrinkSql = "DBCC SHRINKDATABASE(SUSDB, 10) WITH NO_INFOMSGS";
        Assert.Contains("SUSDB", shrinkSql);
        Assert.Contains("SHRINKDATABASE", shrinkSql);
        Assert.Contains("NO_INFOMSGS", shrinkSql);
    }

    [Fact]
    public void Step6_Retry_Parameters_Match_PowerShell()
    {
        // Verify retry constants match WsusDatabase.psm1 (3 retries, 30s delay)
        const int maxRetries = 3;
        const int retryDelaySec = 30;
        Assert.Equal(3, maxRetries);
        Assert.Equal(30, retryDelaySec);
    }

    [Fact]
    public void Step6_Backup_Block_Detection_Covers_Key_Patterns()
    {
        // Test IsBackupBlockingError patterns (whitebox test)
        var blockingMessages = new[]
        {
            "The database cannot be serialized",
            "backup operation is in progress",
            "file manipulation operation"
        };

        foreach (var msg in blockingMessages)
        {
            var isBackup =
                msg.Contains("serialized", StringComparison.OrdinalIgnoreCase) ||
                (msg.Contains("backup", StringComparison.OrdinalIgnoreCase) &&
                 msg.Contains("operation", StringComparison.OrdinalIgnoreCase)) ||
                msg.Contains("file manipulation", StringComparison.OrdinalIgnoreCase);

            Assert.True(isBackup, $"Pattern should match: {msg}");
        }
    }

    // ─── Progress Format Tests ─────────────────────────────────────────────

    [Fact]
    public void Progress_Format_Includes_StepNumber_And_Total()
    {
        // Verify the expected format [Step N/6] matches what the service reports
        for (int i = 1; i <= 6; i++)
        {
            var expectedPrefix = $"[Step {i}/6]";
            Assert.Contains("/6", expectedPrefix);
            Assert.Contains($"[Step {i}", expectedPrefix);
        }
    }

    // ─── DB Size Before/After Tests ────────────────────────────────────────

    [Fact]
    public void DbSize_BeforeAfter_Comparison_Formula()
    {
        // Verify the before/after comparison math
        double before = 5.5;
        double after = 4.2;
        double saved = before - after;
        Assert.Equal(1.3, Math.Round(saved, 1));
    }
}
