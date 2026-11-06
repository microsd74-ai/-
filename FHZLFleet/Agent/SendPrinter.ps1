param(
    [ValidateRange(1,65535)][int]$Port=5055,
    [Parameter(Mandatory=$true)][string]$PrinterId,
    [Parameter(Mandatory=$true)][string]$PrinterName
)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[System.Text.UTF8Encoding]::new($false)
$listener=$null
$clients=[System.Collections.Generic.List[object]]::new()
function Publish($value) {
    [Console]::Out.WriteLine(($value | ConvertTo-Json -Compress -Depth 4))
    [Console]::Out.Flush()
}
try {
    . (Join-Path $PSScriptRoot 'ReadPrinter.ps1')
    $listener=[System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any,$Port)
    $listener.Start()
    Publish @{type='listening'; detail="Port $Port"}
    $nextRead=[DateTime]::MinValue
    while ($true) {
        if ($listener.Pending()) {
            $tcp=$listener.AcceptTcpClient()
            if ($clients.Count -ge 16) { $tcp.Close() } else {
                $tcp.NoDelay=$true; $tcp.SendTimeout=250
                $clients.Add($tcp)
            }
        }
        if ([DateTime]::UtcNow -ge $nextRead) {
            $extra=$null
            if (Get-Command Get-PrinterTelemetry -ErrorAction SilentlyContinue) {
                $snapshot=Get-PrinterTelemetry
                $line=$snapshot.line; $extra=$snapshot.extra
            } else { $line = Get-PrinterState }
            $parts = $line -split '\|'
            $message = [ordered]@{
                type='telemetry'; version=1; id=$PrinterId; name=$PrinterName
                state='reader_error'; detail=$line; finishKind=''; finish=''
                printed=''; total=''; start=''; duration=''
            }
            if ($parts.Count -eq 8 -and $parts[0] -eq 'OK' -and $parts[1] -eq 'STATE') {
                $message.state = 'ok'; $message.detail = ''
                $message.finishKind=$parts[2]; $message.finish=$parts[3]
                $message.printed=$parts[4]; $message.total=$parts[5]
                $message.start=$parts[6]; $message.duration=$parts[7]
            }
            if ($null -ne $extra) { $message['extra']=$extra }

            $bytes=[System.Text.Encoding]::UTF8.GetBytes(($message | ConvertTo-Json -Compress -Depth 4)+"`n")
            if ($bytes.Length -gt 16000 -and $null -ne $extra) {
                $extra.logTail=''; $extra.logState='omitted_by_size'
                $bytes=[System.Text.Encoding]::UTF8.GetBytes(($message | ConvertTo-Json -Compress -Depth 4)+"`n")
            }
            foreach ($tcp in @($clients.ToArray())) {
                try {
                    if ($tcp.Client.Poll(0,[System.Net.Sockets.SelectMode]::SelectRead) -and $tcp.Available -eq 0) { throw 'Disconnected' }
                    $tcp.GetStream().Write($bytes,0,$bytes.Length)
                } catch { $tcp.Close(); [void]$clients.Remove($tcp) }
            }
            $message['connections']=$clients.Count
            Publish $message
            $nextRead=[DateTime]::UtcNow.AddSeconds(1)
        }
        Start-Sleep -Milliseconds 25
    }
} catch {
    Publish @{type='error'; detail=$_.Exception.Message}
    exit 1
} finally {
    foreach ($tcp in $clients) { $tcp.Close() }
    if ($null -ne $listener) { $listener.Stop() }
}
