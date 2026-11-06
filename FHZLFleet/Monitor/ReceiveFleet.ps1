param([ValidateRange(1,65535)][int]$Port=5055)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[System.Text.UTF8Encoding]::new($false)
$listener=$null
$clients=[System.Collections.Generic.List[object]]::new()
function Publish($value) {
    [Console]::Out.WriteLine(($value | ConvertTo-Json -Compress -Depth 4))
    [Console]::Out.Flush()
}
try {
    $listener=[System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any,$Port)
    $listener.Start()
    Publish @{type='listening'; detail="Port $Port"}
    while ($true) {
        if ($listener.Pending()) {
            $tcp=$listener.AcceptTcpClient()
            if ($clients.Count -ge 128) { $tcp.Close() } else {
                $clients.Add(@{tcp=$tcp; buffer=[System.Collections.Generic.List[byte]]::new(); last=[DateTime]::UtcNow})
            }
        }
        foreach ($c in @($clients.ToArray())) {
            try {
                $tcp=$c.tcp
                if ($tcp.Client.Poll(0,[System.Net.Sockets.SelectMode]::SelectRead) -and $tcp.Available -eq 0) { throw 'Disconnected' }
                if (([DateTime]::UtcNow-$c.last).TotalSeconds -gt 15) { throw 'Idle timeout' }
                $available=$tcp.Available
                if ($available -gt 0) {
                    $bytes=New-Object byte[] ([Math]::Min(4096,$available))
                    $count=$tcp.GetStream().Read($bytes,0,$bytes.Length)
                    if ($count -le 0) { throw 'Disconnected' }
                    for ($i=0; $i -lt $count; $i++) {
                        if ($bytes[$i] -eq 10) {
                            $line=[System.Text.Encoding]::UTF8.GetString($c.buffer.ToArray())
                            $c.buffer.Clear()
                            $m=$line | ConvertFrom-Json
                            if ($m.type -ne 'telemetry' -or $m.version -ne 1 -or
                                $m.id -isnot [string] -or $m.name -isnot [string] -or
                                [string]::IsNullOrWhiteSpace($m.id) -or $m.id.Length -gt 80 -or
                                $m.name.Length -gt 120 -or $m.state -notin @('ok','reader_error')) { throw 'Invalid message' }
                            foreach ($field in @('finishKind','finish','printed','total','start','duration','detail')) {
                                if ($m.$field -isnot [string] -or $m.$field.Length -gt 2048) { throw 'Invalid field' }
                            }
                            if ($m.PSObject.Properties.Name -contains 'extra') {
                                if ($m.extra -isnot [pscustomobject]) { throw 'Invalid extra data' }
                                foreach ($property in $m.extra.PSObject.Properties) {
                                    if ($property.Name -notin @('alarm','file','parameters','layerSeconds','layerAverage','temperature','humidity','axes','modes','plcLabels','logTail','logState')) { throw 'Unknown extra field' }
                                    $limit=500
                                    if ($property.Name -eq 'logTail') { $limit=3000 }
                                    if ($property.Value -isnot [string] -or $property.Value.Length -gt $limit) { throw 'Invalid extra field' }
                                }
                            }
                            $c.last=[DateTime]::UtcNow
                            Publish $m
                        } else {
                            $c.buffer.Add($bytes[$i])
                            if ($c.buffer.Count -gt 16384) { throw 'Message too long' }
                        }
                    }
                }
            } catch {
                $c.tcp.Close()
                [void]$clients.Remove($c)
            }
        }
        Start-Sleep -Milliseconds 25
    }
} catch {
    Publish @{type='error'; detail=$_.Exception.Message}
    exit 1
} finally {
    foreach ($c in $clients) { $c.tcp.Close() }
    if ($null -ne $listener) { $listener.Stop() }
}
