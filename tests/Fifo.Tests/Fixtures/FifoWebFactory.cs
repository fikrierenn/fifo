using Microsoft.AspNetCore.Mvc.Testing;

namespace Fifo.Tests.Fixtures;

/// <summary>
/// WebApplicationFactory — app projesini test host olarak ayağa kaldırır.
/// Remote DB bağlantısını kullanır (appsettings.json'dan).
/// </summary>
public sealed class FifoWebFactory : WebApplicationFactory<App.Program>
{
}
