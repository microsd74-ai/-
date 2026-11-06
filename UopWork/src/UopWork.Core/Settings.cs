using System.Net;
using System.Net.Sockets;
using System.Text.Json;

namespace UopWork.Core;

public sealed record PrinterConfig(Guid Id, string Name, string Host, int Port = 5055)
{
    public RecorderSettings? Cameras {get;init;}
    public string Endpoint => $"{Host}:{Port}";
    public PrinterConfig Validate()
    {
        if (Id == Guid.Empty || string.IsNullOrWhiteSpace(Name) || Name.Length > 120)
            throw new ArgumentException("Укажите название принтера (до 120 символов).");
        if (!IPAddress.TryParse(Host, out var address) || address.AddressFamily != AddressFamily.InterNetwork ||
            Host.Split('.').Length != 4 || address.Equals(IPAddress.Any) || address.Equals(IPAddress.Broadcast))
            throw new ArgumentException("Укажите IPv4 компьютера принтера.");
        if (Port is < 1 or > 65535) throw new ArgumentException("Порт должен быть от 1 до 65535.");
        return this with { Name = Name.Trim(), Host = address.ToString(), Cameras=Cameras?.Validate() };
    }
}
public sealed record AppSettings(string Theme, List<PrinterConfig> Printers)
{
    public string AlarmSoundFile { get; init; } = "";
    public string StopSoundFile { get; init; } = "";
    public static AppSettings Empty => new("Dark", []);
    public AppSettings Validate()
    {
        if (AlarmSoundFile is null || AlarmSoundFile.Length > 1024 || StopSoundFile is null || StopSoundFile.Length > 1024) throw new ArgumentException("Неверный путь звукового файла.");
        if (Theme is not ("Light" or "Dark" or "Terminal")) throw new ArgumentException("Неизвестная тема оформления.");
        if (Printers is null || Printers.Any(p => p is null)) throw new ArgumentException("Повреждён список принтеров.");
        if (Printers.Count > 128) throw new ArgumentException("Поддерживается до 128 принтеров.");
        var items = Printers.Select(p => p.Validate()).ToList();
        if (items.Select(p => p.Id).Distinct().Count() != items.Count ||
            items.Select(p => p.Endpoint).Distinct(StringComparer.OrdinalIgnoreCase).Count() != items.Count ||
            items.Select(p => p.Name).Distinct(StringComparer.OrdinalIgnoreCase).Count() != items.Count)
            throw new ArgumentException("Названия и адреса принтеров должны быть уникальными.");
        return this with { Printers = items };
    }
}
public sealed class SettingsStore(string path)
{
    public string Path { get; } = path;
    internal static readonly JsonSerializerOptions Json = new() { WriteIndented = true, PropertyNameCaseInsensitive = true };
    public AppSettings Load()
    {
        if (!File.Exists(Path)) return AppSettings.Empty;
        if (new FileInfo(Path).Length > 1_048_576) throw new IOException("Слишком большой файл настроек.");
        return (JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(Path), Json) ?? throw new IOException("Пустой файл настроек.")).Validate();
    }
    public void Save(AppSettings settings) => AtomicFile.Write(Path, JsonSerializer.Serialize(settings.Validate(), Json));
    public static IReadOnlyList<PrinterConfig> ImportLazarus(string file)
    {
        if (new FileInfo(file).Length > 1_048_576) throw new IOException("Слишком большой файл списка.");
        using var doc = JsonDocument.Parse(File.ReadAllText(file));
        var items = new List<PrinterConfig>();
        if (doc.RootElement.TryGetProperty("printers", out var printers))
            foreach (var p in printers.EnumerateArray())
                items.Add(new(Guid.NewGuid(), p.GetProperty("name").GetString() ?? "", p.GetProperty("host").GetString() ?? "", p.GetProperty("port").GetInt32()));
        else if (doc.RootElement.TryGetProperty("targets", out var targets))
            foreach (var p in targets.EnumerateArray())
            {
                var parts = (p.GetString() ?? "").Split(':');
                if (parts.Length != 2 || !int.TryParse(parts[1], out var port)) throw new IOException("Неверный адрес в списке.");
                items.Add(new(Guid.NewGuid(), $"Принтер {items.Count + 1}", parts[0], port));
            }
        else throw new IOException("В файле нет списка принтеров.");
        return new AppSettings("Dark", items).Validate().Printers;
    }
}
internal static class AtomicFile
{
    internal static void Write(string path, string text, bool replace = true)
    {
        Directory.CreateDirectory(System.IO.Path.GetDirectoryName(System.IO.Path.GetFullPath(path))!);
        var temp = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            using (var file = new FileStream(temp, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                var bytes = System.Text.Encoding.UTF8.GetBytes(text);
                file.Write(bytes); file.Flush(flushToDisk: true);
            }
            File.Move(temp, path, overwrite: replace);
        }
        finally { if (File.Exists(temp)) File.Delete(temp); }
    }
}
