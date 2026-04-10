using System.Text;
using App.Lib;
using FluentAssertions;

namespace Fifo.Tests.Unit;

public class CsvExporterTests
{
    private record TestRow(string Ad, decimal Fiyat, DateTime Tarih);

    [Fact]
    public void ToCsv_WithItems_StartsWithUtf8Bom()
    {
        var data = new[] { new TestRow("A", 1.5m, DateTime.Now) };
        var bytes = CsvExporter.ToCsv(data);

        bytes[0].Should().Be(0xEF);
        bytes[1].Should().Be(0xBB);
        bytes[2].Should().Be(0xBF);
    }

    [Fact]
    public void ToCsv_WithItems_ContainsHeaderRow()
    {
        var data = new[] { new TestRow("A", 1m, DateTime.Now) };
        var csv = GetCsvString(data);

        csv.Should().StartWith("Ad;Fiyat;Tarih");
    }

    [Fact]
    public void ToCsv_DecimalFormat_NoTrailingZeros()
    {
        var data = new[] { new TestRow("X", 56.123456m, DateTime.Now) };
        var csv = GetCsvString(data);

        // Türkçe locale'de decimal separator virgül olabilir
        csv.Should().Match(s => s.Contains("56.123456") || s.Contains("56,123456"));
    }

    [Fact]
    public void ToCsv_DateTimeFormat_CorrectPattern()
    {
        var dt = new DateTime(2026, 3, 24, 14, 30, 0);
        var data = new[] { new TestRow("X", 1m, dt) };
        var csv = GetCsvString(data);

        csv.Should().Contain("2026-03-24 14:30:00");
    }

    [Fact]
    public void ToCsv_SeparatorInValue_ReplacedWithSpace()
    {
        var data = new[] { new TestRow("A;B", 1m, DateTime.Now) };
        var csv = GetCsvString(data);

        // Satır verisi "A B" olmalı (noktalı virgül boşlukla değiştirilmeli)
        csv.Should().Contain("A B");
    }

    [Fact]
    public void ToCsv_EmptyCollection_ReturnsHeaderOnly()
    {
        var data = Array.Empty<TestRow>();
        var csv = GetCsvString(data);
        var lines = csv.Split(Environment.NewLine, StringSplitOptions.RemoveEmptyEntries);

        lines.Should().HaveCount(1);
        lines[0].Should().Be("Ad;Fiyat;Tarih");
    }

    private static string GetCsvString<T>(IEnumerable<T> data)
    {
        var bytes = CsvExporter.ToCsv(data);
        // BOM'u atla (3 byte)
        return Encoding.UTF8.GetString(bytes, 3, bytes.Length - 3);
    }
}
