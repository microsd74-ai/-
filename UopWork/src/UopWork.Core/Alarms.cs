using System.Text.Json;
using System.Text.RegularExpressions;
namespace UopWork.Core;

public sealed record AlarmOccurrence(Guid Id, string Key, string Text, DateTimeOffset AppearedAt,
    DateTimeOffset LastSeenAt, bool Acknowledged = false);
public sealed record AlarmChange(DateTimeOffset At, string Kind, Guid OccurrenceId, string Text);

// The legacy UI rotates one message at a time. A change of message is not proof
// that an earlier alarm cleared. Only a successfully read empty label clears it.
public sealed class AlarmTracker
{
    private readonly Dictionary<string, AlarmOccurrence> active = new(StringComparer.Ordinal);
    public IReadOnlyCollection<AlarmOccurrence> Active => active.Values;
    public bool NeedsAttention => active.Values.Any(a => !a.Acknowledged);
    public event Action<AlarmChange>? Changed;
    public static string Normalize(string text) => Regex.Replace(
        Regex.Replace(text, @"^\s*\d+/\d+\s*:", "").Trim(), @"\s+", " ");
    public void Observe(string text, bool confirmedEmpty, DateTimeOffset now)
    {
        if (!string.IsNullOrWhiteSpace(text))
        {
            var key = Normalize(text);
            if (active.TryGetValue(key, out var previous))
                active[key] = previous with { Text = text.Trim(), LastSeenAt = now };
            else
            {
                var entry = new AlarmOccurrence(Guid.NewGuid(), key, text.Trim(), now, now);
                active.Add(key, entry);
                Changed?.Invoke(new(now, "Появление", entry.Id, entry.Text));
            }
        }
        else if (confirmedEmpty)
        {
            var cleared = active.Values.ToArray(); active.Clear();
            foreach (var entry in cleared) Changed?.Invoke(new(now, "Снятие", entry.Id, entry.Text));
        }
    }
    public void Acknowledge(string key, DateTimeOffset now)
    {
        if (!active.TryGetValue(key, out var entry) || entry.Acknowledged) return;
        active[key] = entry with { Acknowledged = true };
        Changed?.Invoke(new(now, "Подтверждение", entry.Id, entry.Text));
    }
    public void AcknowledgeAll(DateTimeOffset now)
    { foreach (var key in active.Keys.ToArray()) Acknowledge(key, now); }
}
public sealed record AlarmHistoryEntry(Guid PrinterId, string PrinterName, AlarmChange Change)
{
    [System.Text.Json.Serialization.JsonIgnore]
    public string Display => $"{Change.At.ToLocalTime():dd.MM.yyyy HH:mm:ss}  {PrinterName} · {Change.Kind}\n{Change.Text}";
}
public sealed class AlarmHistoryStore(string path)
{
    public const int Limit = 2000;
    public List<AlarmHistoryEntry> Load()
    {
        if (!File.Exists(path)) return [];
        if (new FileInfo(path).Length > 64 * 1024 * 1024) throw new IOException("Слишком большой файл истории аварий.");
        var entries = JsonSerializer.Deserialize<List<AlarmHistoryEntry>>(File.ReadAllText(path))
            ?? throw new IOException("Повреждена история аварий.");
        if (entries.Any(e => e is null || e.Change is null)) throw new IOException("Повреждена запись истории аварий.");
        return entries.TakeLast(Limit).ToList();
    }
    public void Save(IEnumerable<AlarmHistoryEntry> entries) =>
        AtomicFile.Write(path, JsonSerializer.Serialize(entries.TakeLast(Limit)));
}
