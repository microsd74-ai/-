$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../Agent/ParsePrinter.ps1')
function Check($condition,$message){if(-not $condition){throw $message}}
$items=@(@{name='Exit';class='QToolButton'},@{name='';class='QToolBarSeparator'},@{name='';class='QLabel'},@{name='';class='QToolBarSeparator'})
$read=Get-FhzlToolbarAlarm -Items $items
Check ($read.read -and $read.text -eq '') 'Known empty label was not confirmed'
Check (-not (Get-FhzlToolbarAlarm -Items @()).read) 'Missing toolbar considered healthy'
Check (-not (Get-FhzlToolbarAlarm -Items $items[0..1]).read) 'Missing label considered healthy'
$items[2].name='unrecognized message'
Check (-not (Get-FhzlToolbarAlarm -Items $items).read) 'Unknown message considered healthy'
$items[2].name='3/3:E4.2:Sand box squeezes cylinder Alarm'
$read=Get-FhzlToolbarAlarm -Items $items
Check ($read.read -and $read.text -like '3/3:E4.2:*') 'Positive error lost'
$snapshot=Convert-FhzlSnapshot -AlarmRead $true
Check ($snapshot.extra.alarmRead -and $snapshot.extra.alarm -eq '') 'Empty alarm reliability lost in JSON payload'
Check (-not (Convert-FhzlSnapshot).extra.alarmRead) 'Default falsely confirms empty error state'
Write-Output 'PASS alarm source: known empty label, missing toolbar/label, unrecognized text, positive error, payload flag'
