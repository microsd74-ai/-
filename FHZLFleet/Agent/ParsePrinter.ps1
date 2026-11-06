# Pure parsing, independent of Windows UI Automation.
function Get-FhzlMatch([string]$Text,[string]$Pattern) {
    $m=[regex]::Match($Text,$Pattern)
    if ($m.Success) { return ($m.Groups[1].Value.Trim() -replace '\s+',' ') }
    return ''
}
function Convert-FhzlSnapshot {
    param([string]$PrintText='', [string]$FileText='', [string]$Alarm='', [string[]]$StatusLines=@(), [string]$LogTail='', [string]$LogState='unavailable')
    $kind=''
    if ($PrintText -match '(?i)Estimate(?:d)?\s+Finished\s*time') { $kind='ESTIMATE' }
    elseif ($PrintText -match '(?i)Finished\s*time') { $kind='FINISHED' }
    $printed=Get-FhzlMatch $PrintText '(?im)^\s*Printed\s*/\s*Total\s*:\s*(\d+)\s*/\s*\d+'
    $total=Get-FhzlMatch $PrintText '(?im)^\s*Printed\s*/\s*Total\s*:\s*\d+\s*/\s*(\d+)'
    $finish=Get-FhzlMatch $PrintText '(?im)^\s*(?:Estimate(?:d)?\s+)?Finished\s*time\s*:\s*(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})'
    $start=Get-FhzlMatch $PrintText '(?im)^\s*Start\s*time\s*:\s*(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})'
    $duration=Get-FhzlMatch $PrintText '(?im)^\s*Total\s*time\s*:\s*(\d+:\d{2}:\d{2})'
    $extra=[ordered]@{
        alarm=$Alarm
        file=Get-FhzlMatch $FileText '(?im)^\s*File\s+path\s*:\s*(.+)$'
        parameters=Get-FhzlMatch $PrintText '(?im)^\s*Parameter\s*:\s*(.+)$'
        layerSeconds=Get-FhzlMatch $PrintText '(?im)^\s*Layer\s+seconds\(Avg\.\)\s*:\s*([\d.]+)'
        layerAverage=Get-FhzlMatch $PrintText '(?im)^\s*Layer\s+seconds\(Avg\.\)\s*:\s*[\d.]+\s*\(\s*([\d.]+)'
        temperature=''; humidity=''; axes=''; modes=''; plcLabels=''; logTail=''; logState=$LogState
    }
    $axes=@(); $modes=@(); $plc=@()
    foreach ($s in $StatusLines) {
        if ($s -match '^TEMP\.\s*:\s*([-+\d.]+)') { $extra.temperature=$Matches[1] }
        elseif ($s -match '^HUM\.\s*:\s*([-+\d.]+)') { $extra.humidity=$Matches[1] }
        elseif ($s -match '^(X|Y|LZ|RZ|PS|XS)\s*:\s*[-+\d.]+') { $axes+=$s }
        elseif ($s -match '^(Main|Auxiliary)(Manual|Auto)$') { $modes+=$s }
        elseif ($s -match '^(Main|Ink|Feeder) PLC ') { $plc+=$s }
    }
    $extra.axes=$axes -join '; '; $extra.modes=$modes -join '; '; $extra.plcLabels=$plc -join '; '
    # Send only recent complete lines; never label historical warnings as current alarms.
    $lines=@($LogTail -split '\r?\n' | Where-Object { $_ -match '^\[\d{4}-\d{2}-\d{2} ' } | Select-Object -Last 20)
    $selected=[System.Collections.Generic.List[string]]::new(); $length=0
    for ($i=$lines.Count-1; $i -ge 0; $i--) {
        if ($length+$lines[$i].Length+1 -gt 3000) { break }
        $selected.Insert(0,$lines[$i]); $length+=$lines[$i].Length+1
    }
    $extra.logTail=$selected -join "`n"
    foreach ($key in @('alarm','file','parameters','axes','modes','plcLabels')) {
        if ($extra[$key].Length -gt 500) { $extra[$key]=$extra[$key].Substring(0,500) }
    }
    $line='ERROR|TEXT_NOT_FOUND'
    if ($printed -ne '' -and $total -ne '') {
        $line=@('OK','STATE',$kind,$finish,$printed,$total,$start,$duration) -join '|'
    }
    return @{line=$line; extra=$extra}
}
