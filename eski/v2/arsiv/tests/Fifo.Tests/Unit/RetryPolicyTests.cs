using Fifo.Hangfire;
using FluentAssertions;

namespace Fifo.Tests.Unit;

public class RetryPolicyTests
{
    [Fact]
    public void IsApplicationError_NonSqlException_ReturnsFalse()
    {
        var ex = new InvalidOperationException("test");
        FifoRetryPolicy.IsApplicationError(ex).Should().BeFalse();
    }

    [Fact]
    public void IsApplicationError_NullException_ReturnsFalse()
    {
        // Null olmayan ama SqlException olmayan
        var ex = new TimeoutException("timeout");
        FifoRetryPolicy.IsApplicationError(ex).Should().BeFalse();
    }
}
