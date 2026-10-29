using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Options;

namespace Reclaim.Infrastructure.Security;

public sealed class FieldEncryptionOptions
{
    public const string SectionName = "FieldEncryption";

    /// <summary>Key used for new writes.</summary>
    public string ActiveKeyId { get; set; } = "";

    /// <summary>
    /// Key id to base64 256-bit key. Old keys stay listed after rotation so existing rows can
    /// still be read; a row records which key encrypted it.
    /// </summary>
    public Dictionary<string, string> Keys { get; set; } = [];
}

/// <summary>
/// AES-256-GCM encryption for sensitive free text (entry notes and similar), so a raw database
/// dump doesn't expose it. Stored as <c>enc:{keyId}:{base64(nonce | tag | ciphertext)}</c>.
/// </summary>
public sealed class FieldEncryptor
{
    private const string Prefix = "enc:";
    private const int NonceSize = 12;
    private const int TagSize = 16;

    private readonly string _activeKeyId;
    private readonly Dictionary<string, byte[]> _keys;

    public FieldEncryptor(IOptions<FieldEncryptionOptions> options)
    {
        var o = options.Value;
        _keys = o.Keys.ToDictionary(k => k.Key, k => Convert.FromBase64String(k.Value));
        if (_keys.Values.Any(k => k.Length != 32))
            throw new InvalidOperationException("FieldEncryption keys must be 256-bit (32 bytes, base64-encoded).");
        if (!_keys.ContainsKey(o.ActiveKeyId))
            throw new InvalidOperationException("FieldEncryption:ActiveKeyId must name one of FieldEncryption:Keys.");
        if (o.ActiveKeyId.Contains(':'))
            throw new InvalidOperationException("FieldEncryption key ids cannot contain ':'.");
        _activeKeyId = o.ActiveKeyId;
    }

    public string Encrypt(string plaintext)
    {
        var data = Encoding.UTF8.GetBytes(plaintext);
        var output = new byte[NonceSize + TagSize + data.Length];
        var nonce = output.AsSpan(0, NonceSize);
        RandomNumberGenerator.Fill(nonce);

        using var aes = new AesGcm(_keys[_activeKeyId], TagSize);
        aes.Encrypt(nonce, data, output.AsSpan(NonceSize + TagSize), output.AsSpan(NonceSize, TagSize));
        return $"{Prefix}{_activeKeyId}:{Convert.ToBase64String(output)}";
    }

    public string Decrypt(string stored)
    {
        if (!stored.StartsWith(Prefix, StringComparison.Ordinal))
            throw new CryptographicException("Value is not an encrypted field.");
        var separator = stored.IndexOf(':', Prefix.Length);
        if (separator < 0)
            throw new CryptographicException("Encrypted field is malformed.");

        var keyId = stored[Prefix.Length..separator];
        if (!_keys.TryGetValue(keyId, out var key))
            throw new CryptographicException($"Encryption key '{keyId}' is not configured.");

        var input = Convert.FromBase64String(stored[(separator + 1)..]);
        if (input.Length < NonceSize + TagSize)
            throw new CryptographicException("Encrypted field is malformed.");

        var plaintext = new byte[input.Length - NonceSize - TagSize];
        using var aes = new AesGcm(key, TagSize);
        aes.Decrypt(input.AsSpan(0, NonceSize), input.AsSpan(NonceSize + TagSize), input.AsSpan(NonceSize, TagSize), plaintext);
        return Encoding.UTF8.GetString(plaintext);
    }
}
