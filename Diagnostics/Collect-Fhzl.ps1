param([ValidateRange(5,300)][int]$TimeoutSeconds=90)
$ErrorActionPreference='Stop'
$worker=$null
$folder=$null
try {
    $workerScript=Join-Path $PSScriptRoot 'Read-FhzlTree.ps1'
    if (-not (Test-Path -LiteralPath $workerScript)) { throw 'Read-FhzlTree.ps1 is missing. Extract the entire ZIP first.' }
    $powershell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $powershell)) { throw 'Windows PowerShell 5.1 is required.' }
    $reportRoot=Join-Path $PSScriptRoot 'reports'
    [void][System.IO.Directory]::CreateDirectory($reportRoot)
    $name='FHZL-diagnostic-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,6)
    $folder=Join-Path $reportRoot $name
    [void][System.IO.Directory]::CreateDirectory($folder)
    Write-Host 'Reading FHZL window. Do not close this console. Maximum wait:' $TimeoutSeconds 'seconds.'
    $start=[System.Diagnostics.ProcessStartInfo]::new()
    $start.FileName=$powershell
    $start.Arguments='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$workerScript+'" -OutputDirectory "'+$folder+'"'
    $start.UseShellExecute=$false
    $start.CreateNoWindow=$true
    $worker=[System.Diagnostics.Process]::Start($start)
    if (-not $worker.WaitForExit($TimeoutSeconds*1000)) {
        # Terminate only our capture process. Never stop the FHZL application.
        $worker.Kill()
        if (-not $worker.WaitForExit(5000)) { throw 'Capture did not stop. Partial files are in: '+$folder }
        @{status='timeout'; detail='Capture timeout. Partial elements.jsonl/report.txt may still be useful.'} |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $folder 'result.json') -Encoding UTF8
    }
    $resultPath=Join-Path $folder 'result.json'
    if (-not (Test-Path -LiteralPath $resultPath)) {
        @{status='failed'; detail='Capture exited without a summary. Exit code: '+$worker.ExitCode} |
            ConvertTo-Json | Set-Content -LiteralPath $resultPath -Encoding UTF8
    }
    $result=Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    $zip=Join-Path $reportRoot ($name+'.zip')
    Compress-Archive -Path (Join-Path $folder '*') -DestinationPath $zip
    Write-Host ''
    Write-Host 'Result:' $result.status
    if ($result.detail) { Write-Host $result.detail }
    Write-Host 'Report ZIP:' $zip
    Write-Host 'Send this ZIP in the chat. It is NOT uploaded automatically.'
    if ($result.status -eq 'window_not_found') {
        Write-Host 'Open FHZLPrinterManager in the same Windows session and try again.'
    }
    if ($result.status -eq 'failed' -or $result.status -eq 'window_not_found') { exit 1 }
} catch {
    Write-Host 'Could not create report:' $_.Exception.Message
    if ($folder) { Write-Host 'Available files:' $folder }
    exit 1
} finally {
    if ($null -ne $worker) {
        if (-not $worker.HasExited) { $worker.Kill(); [void]$worker.WaitForExit(5000) }
        $worker.Dispose()
    }
}
