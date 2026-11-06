param([string]$ReportZip='')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../Agent/ParsePrinter.ps1')
function Check($Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
$print="Parameter:0.3mm, 300dpi, High`nPrinted / Total: 2279 / 2279`nStart time: 2026-11-05 10:12:25`nFinished time: 2026-11-06`n01:09:38`nLayer seconds(Avg.):48 ( 20.6 ) s`nTotal time: 14:05:12"
$s=Convert-FhzlSnapshot -PrintText $print -Alarm '1/1:Emian.2:Not set Home alarm' -StatusLines @('TEMP.: 24.67','HUM.: 31.86','X: 6.57','MainManual','Main PLC run') -FileText 'File path: D:/jobs/example.tif' -LogTail "incomplete`n[2026-11-06 10:00:00] Warning: old`n[2026-11-06 17:15:00] Info: latest" -LogState 'tail'
Check ($s.line -eq 'OK|STATE|FINISHED|2026-11-06 01:09:38|2279|2279|2026-11-05 10:12:25|14:05:12') 'Print fields or multiline date incorrect'
Check ($s.extra.layerSeconds -eq '48' -and $s.extra.layerAverage -eq '20.6') 'Layer seconds incorrect'
Check ($s.extra.temperature -eq '24.67' -and $s.extra.humidity -eq '31.86') 'Environment values incorrect'
Check ($s.extra.axes -eq 'X: 6.57' -and $s.extra.modes -eq 'MainManual') 'Status fields incorrect'
Check ($s.extra.alarm -eq '1/1:Emian.2:Not set Home alarm') 'Current alarm not retained verbatim'
Check ($s.extra.logTail -notmatch 'incomplete' -and $s.extra.logTail -match 'latest') 'Log framing incorrect'
$empty=Convert-FhzlSnapshot -Alarm '1/1:Alarm'
Check ($empty.line -eq 'ERROR|TEXT_NOT_FOUND' -and $empty.extra.alarm -eq '1/1:Alarm' -and $empty.extra.temperature -eq '') 'Missing print fields must not hide alarms or fabricate measurements'
$estimate=Convert-FhzlSnapshot -PrintText ($print.Replace('Finished time','Estimated Finished time'))
Check ($estimate.line -like 'OK|STATE|ESTIMATE|*') 'Estimate classified incorrectly'
Write-Output 'PASS: print fields, multiline dates, layers, environment, axes, alarm, recent log, missing fields, estimate'
if ($ReportZip) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip=[IO.Compression.ZipFile]::OpenRead($ReportZip)
    try {
        $entry=$zip.GetEntry('elements.jsonl'); $reader=[IO.StreamReader]::new($entry.Open())
        try { $records=@($reader.ReadToEnd() -split '\r?\n' | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json }) }
        finally { $reader.Dispose() }
        $printNode=$records | Where-Object { $_.automationId -eq 'WinPrintManage.centralwidget.lblPrintInfo' }
        $fileNode=$records | Where-Object { $_.automationId -eq 'WinPrintManage.centralwidget.lblFileInfo' }
        $toolbar=$records | Where-Object { $_.automationId -eq 'WinPrintManage.mainToolBar' }
        $alarm=$records | Where-Object { $_.parent -eq $toolbar.id -and $_.name -match '^\d+/\d+:' }
        $status=$records | Where-Object { $_.automationId -eq 'WinPrintManage.statusbar' }
        $statusLines=@($records | Where-Object { $_.parent -eq $status.id } | ForEach-Object { $_.name })
        $s=Convert-FhzlSnapshot -PrintText $printNode.name -FileText $fileNode.name -Alarm $alarm.name -StatusLines $statusLines
        Check ($s.line -like 'OK|STATE|FINISHED|*|2279|2279|*') 'Real snapshot print parsing failed'
        Check ($s.extra.temperature -eq '24.67' -and $s.extra.humidity -eq '31.86') 'Real snapshot environment parsing failed'
        Check ($s.extra.alarm -eq '1/1:Emian.2:Not set Home alarm') 'Real snapshot alarm parsing failed'
        Write-Output 'PASS: uploaded real FHZL snapshot parsed locally (report not copied into repository)'
    } finally { $zip.Dispose() }
}
