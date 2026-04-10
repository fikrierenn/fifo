using System.Reflection;
using System.Text;

namespace App.Lib;

public static class CsvExporter
{
    public static byte[] ToCsv<T>(IEnumerable<T> items, string separator = ";")
    {
        var props = typeof(T).GetProperties(BindingFlags.Public | BindingFlags.Instance);
        var sb = new StringBuilder();

        // Header
        sb.AppendLine(string.Join(separator, props.Select(p => p.Name)));

        // Rows
        foreach (var item in items)
        {
            var values = props.Select(p =>
            {
                var val = p.GetValue(item);
                if (val == null) return "";
                if (val is decimal d) return d.ToString("0.######");
                if (val is DateTime dt) return dt.ToString("yyyy-MM-dd HH:mm:ss");
                return val.ToString()?.Replace(separator, " ") ?? "";
            });
            sb.AppendLine(string.Join(separator, values));
        }

        // UTF-8 BOM + content
        var bom = new byte[] { 0xEF, 0xBB, 0xBF };
        var content = Encoding.UTF8.GetBytes(sb.ToString());
        return bom.Concat(content).ToArray();
    }
}
