namespace Reclaim.Domain.Auditing;

public enum AuditEventType
{
    AccountRegistered,
    LoginSucceeded,
    LoginFailed,
    Logout,
    PasswordChanged,
    RefreshTokenReuseDetected,
    AccountDeletionRequested,
    AccountPurged,
    ProtectionRemovalRequested,
    ProtectionRemovalCancelled,
}
