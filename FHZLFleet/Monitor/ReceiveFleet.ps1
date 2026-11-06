param([Parameter(Mandatory=$true)][string]$TargetsFile)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[System.Text.UTF8Encoding]::new($false)
$targets=@{}
function Publish($value) {
    [Console]::Out.WriteLine(($value | ConvertTo-Json -Compress -Depth 4))
    [Console]::Out.Flush()
}
function Status($c,[string]$state) {
    if ($c.status -ne $state) {
        $c.status=$state
        Publish @{type='connection'; id=$c.endpoint; state=$state}
    }
}
function Drop($c) {
    if ($null -ne $c.tcp) { $c.tcp.Close() }
    $c.tcp=$null; $c.task=$null; $c.buffer.Clear()
    $c.retry=[DateTime]::UtcNow.AddSeconds(2)
    Status $c 'disconnected'
}
try {
    $nextConfig=[DateTime]::MinValue
    while ($true) {
        if ([DateTime]::UtcNow -ge $nextConfig) {
            try {
                $doc=Get-Content -LiteralPath $TargetsFile -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($null -eq $doc -or $doc.targets -isnot [array]) { throw 'Invalid targets file' }
                $desired=@{}
                foreach ($endpoint in $doc.targets) {
                    if ($endpoint -isnot [string] -or $endpoint -notmatch '^([0-9.]+):(\d+)$') { throw 'Invalid endpoint' }
                    $hostName=$Matches[1]; $portNumber=[int]$Matches[2]
                    $ip=$null
                    if (-not [Net.IPAddress]::TryParse($hostName,[ref]$ip) -or $ip.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork -or $portNumber -lt 1 -or $portNumber -gt 65535) { throw 'Invalid IPv4 or port' }
                    $desired[$endpoint]=@{hostName=$hostName; port=$portNumber}
                }
                if ($desired.Count -gt 128) { throw 'Too many printers' }
                foreach ($endpoint in @($targets.Keys)) {
                    if (-not $desired.ContainsKey($endpoint)) {
                        if ($null -ne $targets[$endpoint].tcp) { $targets[$endpoint].tcp.Close() }
                        $targets.Remove($endpoint)
                    }
                }
                foreach ($endpoint in $desired.Keys) {
                    if (-not $targets.ContainsKey($endpoint)) {
                        $targets[$endpoint]=@{endpoint=$endpoint; hostName=$desired[$endpoint].hostName; port=$desired[$endpoint].port; tcp=$null; task=$null; buffer=[Collections.Generic.List[byte]]::new(); retry=[DateTime]::MinValue; last=[DateTime]::MinValue; started=[DateTime]::MinValue; status=''}
                    }
                }
                $configError=''
            } catch {
                # A file being replaced must not interrupt already connected printers.
                if ($configError -ne $_.Exception.Message) { Publish @{type='config_error'; detail=$_.Exception.Message}; $configError=$_.Exception.Message }
            }
            $nextConfig=[DateTime]::UtcNow.AddSeconds(1)
        }
        foreach ($c in @($targets.Values)) {
            try {
                if ($null -eq $c.tcp) {
                    if ([DateTime]::UtcNow -lt $c.retry) { continue }
                    $c.tcp=[Net.Sockets.TcpClient]::new()
                    $c.started=[DateTime]::UtcNow
                    $c.task=$c.tcp.ConnectAsync($c.hostName,$c.port)
                    Status $c 'connecting'
                }
                if ($null -ne $c.task) {
                    if (-not $c.task.IsCompleted) {
                        if (([DateTime]::UtcNow-$c.started).TotalSeconds -gt 1) { Drop $c }
                        continue
                    }
                    [void]$c.task.GetAwaiter().GetResult()
                    $c.task=$null; $c.tcp.NoDelay=$true; $c.last=[DateTime]::UtcNow
                    Status $c 'connected'
                }
                $tcp=$c.tcp
                if ($tcp.Client.Poll(0,[Net.Sockets.SelectMode]::SelectRead) -and $tcp.Available -eq 0) { throw 'Disconnected' }
                if (([DateTime]::UtcNow-$c.last).TotalSeconds -gt 8) { throw 'No fresh telemetry' }
                $available=$tcp.Available
                if ($available -gt 0) {
                    $bytes=New-Object byte[] ([Math]::Min(4096,$available))
                    $count=$tcp.GetStream().Read($bytes,0,$bytes.Length)
                    if ($count -le 0) { throw 'Disconnected' }
                    for ($i=0; $i -lt $count; $i++) {
                        if ($bytes[$i] -eq 10) {
                            $line=[Text.Encoding]::UTF8.GetString($c.buffer.ToArray())
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
                            # The configured endpoint owns the row, even if two agents share an ID.
                            $m | Add-Member -NotePropertyName printerId -NotePropertyValue $m.id -Force
                            $m.id=$c.endpoint
                            Publish $m
                        } else {
                            $c.buffer.Add($bytes[$i])
                            if ($c.buffer.Count -gt 16384) { throw 'Message too long' }
                        }
                    }
                }
            } catch { Drop $c }
        }
        Start-Sleep -Milliseconds 25
    }
} catch {
    Publish @{type='error'; detail=$_.Exception.Message}
    exit 1
} finally {
    foreach ($c in $targets.Values) { if ($null -ne $c.tcp) { $c.tcp.Close() } }
}
