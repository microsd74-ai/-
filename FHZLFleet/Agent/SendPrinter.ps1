param(
    [Parameter(Mandatory=$true)][string]$Server,
    [ValidateRange(1,65535)][int]$Port = 5055,
    [Parameter(Mandatory=$true)][string]$PrinterId,
    [Parameter(Mandatory=$true)][string]$PrinterName
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$client = $null
$nextConnect = [DateTime]::MinValue
function Publish($value) {
    [Console]::Out.WriteLine(($value | ConvertTo-Json -Compress -Depth 4))
    [Console]::Out.Flush()
}
try {
    . (Join-Path $PSScriptRoot 'ReadPrinter.ps1')
    while ($true) {
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
            if ($null -eq $client -and [DateTime]::UtcNow -ge $nextConnect) {
                try {
                    $client = [System.Net.Sockets.TcpClient]::new()
                    $task = $client.ConnectAsync($Server, $Port)
                    if (-not $task.Wait(500)) { throw 'Connection timeout' }
                    $task.GetAwaiter().GetResult()
                    $client.SendTimeout = 500
                    $client.NoDelay = $true
                } catch {
                    if ($null -ne $client) { $client.Close(); $client=$null }
                    $nextConnect = [DateTime]::UtcNow.AddSeconds(2)
                }
            }
            $sent = $false
            if ($null -ne $client) {
                try {
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($message | ConvertTo-Json -Compress -Depth 4) + "`n")
                    if ($bytes.Length -gt 16000 -and $null -ne $extra) {
                        $extra.logTail=''; $extra.logState='omitted_by_size'
                        $bytes = [System.Text.Encoding]::UTF8.GetBytes(($message | ConvertTo-Json -Compress -Depth 4) + "`n")
                    }
                    $client.GetStream().Write($bytes, 0, $bytes.Length)
                    $sent = $true
                } catch {
                    $client.Close(); $client=$null
                    $nextConnect = [DateTime]::UtcNow.AddSeconds(2)
                }
            }
            $message['sent'] = $sent
            Publish $message
        Start-Sleep -Milliseconds 1000
    }
} catch {
    Publish @{type='error'; detail=$_.Exception.Message}
    exit 1
} finally {
    if ($null -ne $client) { $client.Close() }
}
