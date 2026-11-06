using System.Globalization;
using System.Text.Json;
namespace UopWork.Core;
public sealed record Telemetry(
    string Name, bool ReadSucceeded, string Detail, int? Printed, int? Total,
    string Finish, string FinishKind, string File, string Mode, string Axes,
    string Temperature, string Humidity, string Alarm, bool? AlarmRead,
    string PrinterLog, DateTimeOffset ReceivedAt)
{
    public double Progress => Printed is >= 0 && Total is > 0 ? Math.Clamp((double)Printed.Value / Total.Value, 0, 1) : 0;
    public bool ErrorsKnownEmpty => AlarmRead == true && string.IsNullOrWhiteSpace(Alarm);
    public static Telemetry Parse(ReadOnlyMemory<byte> json, DateTimeOffset received)
    {
        using var doc = JsonDocument.Parse(json, new() { MaxDepth = 16 });
        var r = doc.RootElement;
        if (Text(r,"type") != "telemetry" || !r.TryGetProperty("version",out var version) || (version.ValueKind!=JsonValueKind.Number || !version.TryGetInt32(out var number) || number!=1))
            throw new FormatException("Неподдерживаемое сообщение агента.");
        var state=Text(r,"state");
        if (state is not ("ok" or "reader_error")) throw new FormatException("Неверное состояние чтения.");
        var extra = r.TryGetProperty("extra",out var e) && e.ValueKind==JsonValueKind.Object ? e : default;
        var alarm=Text(extra,"alarm");
        bool? alarmRead=extra.ValueKind==JsonValueKind.Object && extra.TryGetProperty("alarmRead",out var flag) && flag.ValueKind is JsonValueKind.True or JsonValueKind.False ? flag.GetBoolean() : null;
        return new(Text(r,"name"),state=="ok",Text(r,"detail"),Number(r,"printed"),Number(r,"total"),
            Text(r,"finish"),Text(r,"finishKind"),Text(extra,"file"),Text(extra,"modes"),Text(extra,"axes"),
            Text(extra,"temperature"),Text(extra,"humidity"),alarm,alarmRead,Text(extra,"logTail"),received);
    }
    private static int? Number(JsonElement e,string key) => int.TryParse(Text(e,key),NumberStyles.None,CultureInfo.InvariantCulture,out var n) && n>=0 ? n : null;
    private static string Text(JsonElement e,string key)
    {
        if (e.ValueKind!=JsonValueKind.Object || !e.TryGetProperty(key,out var p)) return "";
        if (p.ValueKind!=JsonValueKind.String) throw new FormatException($"Неверное поле агента: {key}");
        var s=p.GetString()??"";
        if (s.Length>8192) throw new FormatException("Поле агента слишком длинное.");
        return s;
    }
}
