using Dapper;
using App.Lib;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace App.Features.Run;

public class IndexModel : PageModel
{
    private const int LongTimeoutSeconds = 1800;
    private readonly Db _db;
    private readonly RunQueue _runQueue;

    public IndexModel(Db db, RunQueue runQueue)
    {
        _db = db;
        _runQueue = runQueue;
    }

    [BindProperty]
    public DateTime? AlisBaslangic { get; set; }

    [BindProperty]
    public DateTime? AlisBitis { get; set; }

    [BindProperty]
    public DateTime? SatisBaslangic { get; set; }

    [BindProperty]
    public DateTime? SatisBitis { get; set; }

    [BindProperty]
    public int? StkId { get; set; }

    [BindProperty]
    public bool CalistirAlis { get; set; } = true;

    [BindProperty]
    public bool CalistirCikis { get; set; } = true;

    public SummaryModel Summary { get; private set; } = new();
    public List<FifoRow> Rows { get; } = [];
    public bool ShowResults { get; private set; }
    public string? DonemStatus { get; private set; }
    public string? DonemError { get; private set; }

    public void OnGet()
    {
        var today = DateTime.Today;
        var donemBaslangic = new DateTime(2026, 1, 1);
        var donemBitis = today < donemBaslangic ? donemBaslangic : today;

        AlisBaslangic = donemBaslangic;
        AlisBitis = donemBitis;
        SatisBaslangic = donemBaslangic;
        SatisBitis = donemBitis;
    }

    public async Task<IActionResult> OnPostStartAsync()
    {
        if (CalistirAlis && (AlisBaslangic is null || AlisBitis is null))
        {
            return new JsonResult(new { ok = false, error = "Alis tarihleri zorunludur." })
            {
                StatusCode = StatusCodes.Status400BadRequest
            };
        }

        if (CalistirCikis && (SatisBaslangic is null || SatisBitis is null))
        {
            return new JsonResult(new { ok = false, error = "Satis tarihleri zorunludur." })
            {
                StatusCode = StatusCodes.Status400BadRequest
            };
        }

        if (!CalistirAlis && !CalistirCikis)
        {
            return new JsonResult(new { ok = false, error = "En az bir adim secilmeli." })
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
                VALUES (@RunId, 'DONEM', 'QUEUED', GETDATE());
                """,
                new { RunId = runId });
        }

        await _runQueue.QueueAsync(new RunRequest(
            runId,
            "DONEM",
            null,
            AlisBaslangic,
            AlisBitis,
            SatisBaslangic,
            SatisBitis,
            StkId,
            CalistirAcilis: false,
            CalistirAlis: CalistirAlis,
            CalistirCikis: CalistirCikis));

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
        if (CalistirAlis && (AlisBaslangic is null || AlisBitis is null))
        {
            DonemError = "Alis tarihleri zorunludur.";
            return Page();
        }

        if (CalistirCikis && (SatisBaslangic is null || SatisBitis is null))
        {
            DonemError = "Satis tarihleri zorunludur.";
            return Page();
        }

        if (!CalistirAlis && !CalistirCikis)
        {
            DonemError = "En az bir adim secilmeli.";
            return Page();
        }

        try
        {
            using var connection = _db.Open();

            await connection.ExecuteAsync(
                """
                EXEC bkm.sp_fifo_StokMaliyetCalistir
                    @alisBaslangic = @AlisBaslangic,
                    @alisBitis = @AlisBitis,
                    @satisBaslangic = @SatisBaslangic,
                    @satisBitis = @SatisBitis,
                    @stkID = @StkId,
                    @calistirAcilis = 0,
                    @calistirAlis = @CalistirAlis,
                    @calistirCikis = @CalistirCikis;
                """,
                new
                {
                    AlisBaslangic,
                    AlisBitis,
                    SatisBaslangic,
                    SatisBitis,
                    StkId,
                    CalistirAlis,
                    CalistirCikis
                },
                commandTimeout: LongTimeoutSeconds);

            if (CalistirCikis && SatisBaslangic is not null && SatisBitis is not null)
            {
                await LoadResultsAsync(connection);
                ShowResults = true;
            }

            DonemStatus = "Donem calistirma tamamlandi.";
        }
        catch (Exception ex)
        {
            DonemError = ex.Message;
        }

        return Page();
    }

    private async Task LoadResultsAsync(System.Data.IDbConnection connection)
    {
        Summary = await connection.QuerySingleOrDefaultAsync<SummaryModel>(
            """
            SELECT
                COUNT(*) AS LineCount,
                COUNT(DISTINCT stkID) AS ProductCount,
                ISNULL(SUM(cikisTutar), 0) AS TotalCost
            FROM bkm.fifo_StokMaliyetCikis
            WHERE hareketTarihi >= @SatisBaslangic
              AND hareketTarihi <= @SatisBitis
              AND (@StkId IS NULL OR stkID = @StkId);
            """,
            new { SatisBaslangic, SatisBitis, StkId }) ?? new SummaryModel();

        var rows = await connection.QueryAsync<FifoRow>(
            """
            SELECT TOP 200
                stkID AS StkId,
                hareketTarihi AS HareketTarihi,
                hareketTipi AS HareketTipi,
                miktar AS Miktar,
                birimMaliyet AS BirimMaliyet,
                cikisTutar AS CikisTutar
            FROM bkm.fifo_StokMaliyetCikis
            WHERE hareketTarihi >= @SatisBaslangic
              AND hareketTarihi <= @SatisBitis
              AND (@StkId IS NULL OR stkID = @StkId)
            ORDER BY hareketTarihi DESC, stkID;
            """,
            new { SatisBaslangic, SatisBitis, StkId });

        Rows.Clear();
        Rows.AddRange(rows);
    }

    public sealed class SummaryModel
    {
        public int LineCount { get; init; }
        public int ProductCount { get; init; }
        public decimal TotalCost { get; init; }
    }

    public sealed class FifoRow
    {
        public int StkId { get; init; }
        public DateTime HareketTarihi { get; init; }
        public string HareketTipi { get; init; } = string.Empty;
        public decimal Miktar { get; init; }
        public decimal BirimMaliyet { get; init; }
        public decimal CikisTutar { get; init; }
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
