using System.Net.Sockets;
namespace UopWork.Core;
public static class AgentConnection
{
    public static async Task ObserveAsync(PrinterConfig printer, Action<Telemetry> onData, Action<string> onConnection, CancellationToken stop)
    {
        while (!stop.IsCancellationRequested)
        {
            try
            {
                onConnection("Подключение…");
                using var client=new TcpClient { NoDelay=true };
                using (var connect=CancellationTokenSource.CreateLinkedTokenSource(stop))
                {
                    connect.CancelAfter(TimeSpan.FromSeconds(2));
                    await client.ConnectAsync(printer.Host,printer.Port,connect.Token).ConfigureAwait(false);
                }
                onConnection("Ожидание показаний");
                using var stream=client.GetStream();
                using var frame=new MemoryStream();
                var buffer=new byte[4096];
                while (!stop.IsCancellationRequested)
                {
                    using var timeout=CancellationTokenSource.CreateLinkedTokenSource(stop);
                    timeout.CancelAfter(TimeSpan.FromSeconds(8));
                    int count=await stream.ReadAsync(buffer,timeout.Token).ConfigureAwait(false);
                    if (count==0) throw new IOException("Соединение закрыто.");
                    for (int i=0;i<count;i++)
                    {
                        if (buffer[i]==10)
                        {
                            if (frame.Length>0) onData(Telemetry.Parse(frame.ToArray(),DateTimeOffset.Now));
                            frame.SetLength(0);
                        }
                        else
                        {
                            frame.WriteByte(buffer[i]);
                            if (frame.Length>16384) throw new IOException("Сообщение агента слишком длинное.");
                        }
                    }
                }
            }
            catch (OperationCanceledException) when (stop.IsCancellationRequested) { return; }
            catch (Exception ex) when (ex is IOException or SocketException or OperationCanceledException or FormatException or System.Text.Json.JsonException)
            { onConnection("Нет связи"); }
            try { await Task.Delay(TimeSpan.FromSeconds(2),stop).ConfigureAwait(false); }
            catch (OperationCanceledException) when (stop.IsCancellationRequested) { return; }
        }
    }
}
