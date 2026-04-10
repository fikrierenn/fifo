using System.Threading.Channels;

namespace App.Lib;

public sealed record RunRequest(
    Guid RunId,
    string RunType,
    DateTime? EnvanterTarihi,
    DateTime? AlisBaslangic,
    DateTime? AlisBitis,
    DateTime? SatisBaslangic,
    DateTime? SatisBitis,
    int? StkId,
    bool CalistirAcilis,
    bool CalistirAlis,
    bool CalistirCikis);

public sealed class RunQueue
{
    private readonly Channel<RunRequest> _channel = Channel.CreateUnbounded<RunRequest>();

    public ValueTask QueueAsync(RunRequest request)
    {
        return _channel.Writer.WriteAsync(request);
    }

    public IAsyncEnumerable<RunRequest> DequeueAllAsync(CancellationToken cancellationToken)
    {
        return _channel.Reader.ReadAllAsync(cancellationToken);
    }
}
