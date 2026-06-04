using Microsoft.Data.SqlClient;

namespace App.Lib;

public sealed class Db
{
    private readonly IConfiguration _config;

    public Db(IConfiguration config)
    {
        _config = config;
    }

    public SqlConnection Open()
    {
        var connectionString = _config.GetConnectionString("FifoDb");
        if (string.IsNullOrWhiteSpace(connectionString))
        {
            throw new InvalidOperationException("Missing ConnectionStrings:FifoDb.");
        }

        var connection = new SqlConnection(connectionString);
        connection.Open();
        return connection;
    }
}
