using System.Net;
using FluentAssertions;
using Fifo.Tests.Fixtures;

namespace Fifo.Tests.Web;

[Trait("Category", "Integration")]
public class PageTests : IClassFixture<FifoWebFactory>
{
    private readonly HttpClient _client;

    public PageTests(FifoWebFactory factory) => _client = factory.CreateClient();

    [Theory]
    [InlineData("/")]
    [InlineData("/Fifo/Wizard")]
    [InlineData("/Rapor/SorunluStoklar")]
    [InlineData("/Rapor/IslemLog")]
    public async Task Page_ReturnsSuccess(string url)
    {
        var response = await _client.GetAsync(url);

        response.StatusCode.Should().Be(HttpStatusCode.OK);
    }

    [Fact]
    public async Task DevreDisiDurum_ReturnsJson()
    {
        var response = await _client.GetAsync("/api/devredisi/durum?stkId=1");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        response.Content.Headers.ContentType?.MediaType.Should().Be("application/json");
    }

    [Fact]
    public async Task DevreDisiListe_ReturnsJsonWithSayisi()
    {
        var response = await _client.GetAsync("/api/devredisi/liste");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var json = await response.Content.ReadAsStringAsync();
        json.Should().Contain("sayisi");
    }

    [Fact]
    public async Task UrunAra_ShortQuery_ReturnsEmptyArray()
    {
        var response = await _client.GetAsync("/api/urun-ara?q=ab");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var json = await response.Content.ReadAsStringAsync();
        json.Should().Be("[]");
    }
}
