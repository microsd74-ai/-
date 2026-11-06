using System.Security.Cryptography;
using System.Text;
namespace UopWork.Desktop;

// DPAPI CurrentUser: bound to this Windows account, not a shared app key.
public static class CameraSecrets
{
    private static readonly byte[] Entropy=Encoding.UTF8.GetBytes("UOP WORK recorder password v1");
    public static string Protect(string password)=>Convert.ToBase64String(ProtectedData.Protect(Encoding.UTF8.GetBytes(password),Entropy,DataProtectionScope.CurrentUser));
    public static string Unprotect(string encrypted)=>string.IsNullOrEmpty(encrypted)?"":Encoding.UTF8.GetString(ProtectedData.Unprotect(Convert.FromBase64String(encrypted),Entropy,DataProtectionScope.CurrentUser));
}
