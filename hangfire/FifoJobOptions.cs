namespace Fifo.Hangfire;

public sealed class FifoJobOptions
{
    public const string SectionName = "FifoJob";

    /// <summary>Number of products per batch. Default: 500.</summary>
    public int BatchSize { get; set; } = 500;

    /// <summary>Per-product SP command timeout in seconds. Default: 120.</summary>
    public int CommandTimeoutSeconds { get; set; } = 120;

    /// <summary>Individual product errors do not stop the batch; run is cancelled after this many failures.</summary>
    public int MaxFailedProducts { get; set; } = 50;
}
