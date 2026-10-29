namespace Reclaim.Domain.Common;

/// <summary>Raised when an operation would violate a domain rule.</summary>
public class DomainException(string message) : Exception(message);
