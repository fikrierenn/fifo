using Dapper;
using App.Lib;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace App.Features.Run;

public class AcilisModel : PageModel
{
    private const int LongTimeoutSeconds = 1800;
    private readonly Db _db;
    private readonly RunQueue _runQueue;

    public AcilisModel(Db db, RunQueue runQueue)
    {
        _db = db;
        _runQueue = runQueue;
    }

    [BindProperty]
    public DateTime? EnvanterTarihi { get; set; }

    [BindProperty]
    public int? StkId { get; set; }

    public string? Status { get; private set; }
    public string? Error { get; private set; }

    public void OnGet()
    {
        EnvanterTarihi = new DateTime(2025, 12, 31);
    }

    public async Task<IActionResult> OnPostStartAsync()
    {
        if (EnvanterTarihi is null)
        {
            return new JsonResult(new { ok = false, error = "Envanter tarihi zorunludur." })
            {
                StatusCode = StatusCodes.Status400BadRequest
            };
        }

        var runId = Guid.NewGuid();

        using (var connection = _db.Open())
        {
            await connection.ExecuteAsync(
                """
                INSERT INTO bkm.fifo_Run (runId, runType, status, requestedAt)
                VALUES (@RunId, 'ACILIS', 'QUEUED', GETDATE());
                """,
                new { RunId = runId });
        }

        await _runQueue.QueueAsync(new RunRequest(
            runId,
            "ACILIS",
            EnvanterTarihi,
            null,
            null,
            null,
            null,
            StkId,
            CalistirAcilis: true,
            CalistirAlis: false,
            CalistirCikis: false));

        return new JsonResult(new { ok = true, runId });
    }

    public async Task<IActionResult> OnGetLogAsync(Guid runId)
    {
        using var connection = _db.Open();
        await connection.ExecuteAsync("SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;");

        var run = await connection.QuerySingleOrDefaultAsync<RunRow>(
            """
            SELECT
                status AS Status,
                startedAt AS StartedAt,
                endedAt AS EndedAt,
                message AS Message
            FROM bkm.fifo_Run
            WHERE runId = @RunId;
            """,
            new { RunId = runId });

        if (run is null)
        {
            return new JsonResult(new { ok = false, error = "Run bulunamadi." })
            {
                StatusCode = StatusCodes.Status404NotFound
            };
        }

        var steps = (await connection.QueryAsync<RunStepRow>(
            """
            SELECT
                stepKey AS StepKey,
                stepName AS StepName,
                status AS Status,
                startedAt AS StartedAt,
                endedAt AS EndedAt,
                message AS Message
            FROM bkm.fifo_RunStep
            WHERE runId = @RunId
            ORDER BY stepOrder;
            """,
            new { RunId = runId })).ToList();

        return new JsonResult(new
        {
            ok = true,
            status = run.Status,
            startedAt = run.StartedAt,
            endedAt = run.EndedAt,
            message = run.Message,
            steps = steps.Select(step => new
            {
                stepKey = step.StepKey,
                stepName = step.StepName,
                status = step.Status,
                startedAt = step.StartedAt,
                endedAt = step.EndedAt,
                message = step.Message
            })
        });
    }

    public async Task<IActionResult> OnPostAsync()
    {
        if (EnvanterTarihi is null)
        {
            Error = "Envanter tarihi zorunludur.";
            return Page();
        }

        try
        {
            using var connection = _db.Open();

            await connection.ExecuteAsync(
                """
                EXEC bkm.sp_fifo_StokMaliyetCalistir
                    @envanterTarihi = @EnvanterTarihi,
                    @stkID = @StkId,
                    @calistirAcilis = 1,
                    @calistirAlis = 0,
                    @calistirCikis = 0;
                """,
                new
                {
                    EnvanterTarihi,
                    StkId
                },
                commandTimeout: LongTimeoutSeconds);

            Status = "Devir katmani olusturuldu.";
        }
        catch (Exception ex)
        {
            Error = ex.Message;
        }

        return Page();
    }

    private sealed record RunRow(string Status, DateTime? StartedAt, DateTime? EndedAt, string? Message);

    private sealed record RunStepRow(
        string StepKey,
        string StepName,
        string Status,
        DateTime? StartedAt,
        DateTime? EndedAt,
        string? Message);
}
