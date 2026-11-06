using System.Net;
using System.Net.Sockets;
namespace UopWork.Core;

// Camera credentials never go in a URL stored in settings.json.
public sealed record RecorderSettings
{
    public bool Enabled {get;init;}
    public string Host {get;init;}="";
    public int Port {get;init;}=554;
    public int Channel1 {get;init;}=1;
    public int Channel2 {get;init;}=2;
    public bool Substream {get;init;}=true;
    public string Username {get;init;}="";
    public string ProtectedPassword {get;init;}="";
    public RecorderSettings Validate()
    {
        if(Host is null||Username is null||ProtectedPassword is null||Username.Length>128||ProtectedPassword.Length>8192)
            throw new ArgumentException("Повреждены настройки регистратора.");
        if(Port is <1 or >65535||Channel1 is <1 or >64||Channel2 is <1 or >64)
            throw new ArgumentException("Проверьте RTSP-порт и номера каналов (1–64).");
        if(!Enabled)return this;
        if(!IPAddress.TryParse(Host,out var ip)||ip.AddressFamily!=AddressFamily.InterNetwork||Host.Split('.').Length!=4||ip.Equals(IPAddress.Any)||ip.Equals(IPAddress.Broadcast))
            throw new ArgumentException("Укажите IPv4 регистратора.");
        if(Channel1==Channel2)throw new ArgumentException("Выберите два разных канала камер.");
        if(string.IsNullOrWhiteSpace(Username))throw new ArgumentException("Укажите пользователя регистратора.");
        return this with{Host=ip.ToString(),Username=Username.Trim()};
    }
    public string StreamPath(int camera)
    {
        if(camera is not (1 or 2))throw new ArgumentOutOfRangeException(nameof(camera));
        int channel=camera==1?Channel1:Channel2;
        return $"/Streaming/Channels/{channel*100+(Substream?2:1)}";
    }
    public Uri BuildUri(int camera,string password)
    {
        Validate();if(!Enabled)throw new InvalidOperationException("Камеры отключены.");
        return new Uri($"rtsp://{Uri.EscapeDataString(Username)}:{Uri.EscapeDataString(password)}@{Host}:{Port}{StreamPath(camera)}");
    }
}
