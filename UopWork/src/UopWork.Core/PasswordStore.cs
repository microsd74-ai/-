using System.Security.Cryptography;
using System.Text.Json;
namespace UopWork.Core;
public sealed class PasswordStore(string path)
{
    private const int Iterations = 210_000;
    private sealed record PasswordRecord(int Version, string Algorithm, int Iterations, string Salt, string Hash);
    public bool IsConfigured => File.Exists(path);
    public bool Verify(string password)
    {
        if (!IsConfigured) return false;
        if (new FileInfo(path).Length > 8192) throw new IOException("Повреждён файл пароля.");
        var record = JsonSerializer.Deserialize<PasswordRecord>(File.ReadAllText(path), SettingsStore.Json) ?? throw new IOException("Повреждён файл пароля.");
        if (record.Version != 1 || record.Algorithm != "PBKDF2-HMAC-SHA256" || record.Iterations is < Iterations or > 2_000_000)
            throw new IOException("Неверные параметры файла пароля.");
        byte[] salt,expected;
        try{salt=Convert.FromHexString(record.Salt);expected=Convert.FromHexString(record.Hash);}
        catch(FormatException ex){throw new IOException("Повреждён файл пароля.",ex);}
        if (salt.Length != 16 || expected.Length != 32) throw new IOException("Повреждён файл пароля.");
        var actual = Rfc2898DeriveBytes.Pbkdf2(password, salt, record.Iterations, HashAlgorithmName.SHA256, 32);
        try { return CryptographicOperations.FixedTimeEquals(actual, expected); }
        finally { CryptographicOperations.ZeroMemory(actual); }
    }
    public void Initialize(string password)
    {
        if (IsConfigured) throw new InvalidOperationException("Пароль уже создан.");
        Save(password, replace: false);
    }
    public void Change(string oldPassword, string newPassword)
    {
        if (!Verify(oldPassword)) throw new ArgumentException("Текущий пароль неверен.");
        Save(newPassword, replace: true);
    }
    private void Save(string password, bool replace)
    {
        if (password.Length < 8 || string.IsNullOrWhiteSpace(password)) throw new ArgumentException("Пароль должен содержать не менее 8 символов.");
        var salt = RandomNumberGenerator.GetBytes(16);
        var hash = Rfc2898DeriveBytes.Pbkdf2(password, salt, Iterations, HashAlgorithmName.SHA256, 32);
        try
        {
            var record = new PasswordRecord(1, "PBKDF2-HMAC-SHA256", Iterations, Convert.ToHexString(salt), Convert.ToHexString(hash));
            AtomicFile.Write(path, JsonSerializer.Serialize(record, SettingsStore.Json), replace);
        }
        finally { CryptographicOperations.ZeroMemory(hash); }
    }
}
