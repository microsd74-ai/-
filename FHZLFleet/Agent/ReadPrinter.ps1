Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
. (Join-Path $PSScriptRoot 'ParsePrinter.ps1')
$script:FhzlWindow=$null
function Read-FhzlProperty($Object,[string]$Name) {
    if ($null -eq $Object) { throw 'Unavailable element' }
    return $Object.GetType().GetProperty($Name).GetValue($Object,$null)
}
function Find-FhzlElement([string]$Id) {
    $condition=[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::AutomationIdProperty,$Id)
    return $script:FhzlWindow.FindFirst([System.Windows.Automation.TreeScope]::Descendants,$condition)
}
function Read-FhzlName($Element) {
    if ($null -eq $Element) { return '' }
    return [string](Read-FhzlProperty (Read-FhzlProperty $Element 'Current') 'Name')
}
function Get-FhzlLogTail($Log) {
    $failed=$false
    try {
        $pattern=$null
        if ($Log.TryGetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern,[ref]$pattern)) {
            $range=$pattern.DocumentRange.Clone()
            $range.MoveEndpointByRange([System.Windows.Automation.Text.TextPatternRangeEndpoint]::Start,$range,[System.Windows.Automation.Text.TextPatternRangeEndpoint]::End)
            [void]$range.MoveEndpointByUnit([System.Windows.Automation.Text.TextPatternRangeEndpoint]::Start,[System.Windows.Automation.Text.TextUnit]::Character,-6000)
            return @{text=[string]$range.GetText(6000); state='tail'; source='TextPattern'}
        }
    } catch { $failed=$true }
    # Qt providers may expose TextPattern but reject moving its endpoints.
    # ValuePattern reading succeeded in the real diagnostic: trim after reading.
    try {
        $pattern=$null
        if ($Log.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern,[ref]$pattern)) {
            $value=[string](Read-FhzlProperty (Read-FhzlProperty $pattern 'Current') 'Value')
            return @{text=$value.Substring([Math]::Max(0,$value.Length-6000)); state='tail'; source='ValuePattern'}
        }
    } catch { $failed=$true }
    $state='unavailable'
    if ($failed) { $state='read_error' }
    return @{text=''; state=$state; source=''}
}
function Get-PrinterTelemetry {
    $extra=[ordered]@{alarm=''; alarmRead=$false; logTail=''; logState='unavailable'}
    try {
        if ($null -ne $script:FhzlWindow) { [void](Read-FhzlName $script:FhzlWindow) }
        if ($null -eq $script:FhzlWindow) {
            $desktop=[System.Windows.Automation.AutomationElement]::RootElement
            $windows=$desktop.FindAll([System.Windows.Automation.TreeScope]::Children,[System.Windows.Automation.Condition]::TrueCondition)
            foreach ($window in $windows) {
                try {
                    if ((Read-FhzlName $window) -match 'FHZLPrinterManager') { $script:FhzlWindow=$window; break }
                } catch { }
            }
        }
        if ($null -eq $script:FhzlWindow) { return @{line='ERROR|WINDOW_NOT_FOUND'; extra=$extra} }
        $print=Read-FhzlName (Find-FhzlElement 'WinPrintManage.centralwidget.lblPrintInfo')
        $file=Read-FhzlName (Find-FhzlElement 'WinPrintManage.centralwidget.lblFileInfo')
        $toolbar=Find-FhzlElement 'WinPrintManage.mainToolBar'
        $alarm=''; $alarmRead=$false
        if ($null -ne $toolbar) {
            try {
                $items=@()
                foreach ($e in $toolbar.FindAll([System.Windows.Automation.TreeScope]::Children,[System.Windows.Automation.Condition]::TrueCondition)) {
                    $current=Read-FhzlProperty $e 'Current'
                    $items+=@{name=[string](Read-FhzlProperty $current 'Name'); class=[string](Read-FhzlProperty $current 'ClassName')}
                }
                $read=Get-FhzlToolbarAlarm -Items $items
                $alarm=$read.text; $alarmRead=$read.read
            } catch { $alarmRead=$false }
        }
        $status=Find-FhzlElement 'WinPrintManage.statusbar'
        $statusLines=@()
        if ($null -ne $status) {
            foreach ($e in $status.FindAll([System.Windows.Automation.TreeScope]::Children,[System.Windows.Automation.Condition]::TrueCondition)) {
                try { $statusLines+=Read-FhzlName $e } catch { }
            }
        }
        $tail=''; $logState='unavailable'
        try {
            $log=Find-FhzlElement 'WinPrintManage.dockWidgetLog.LogBrowserDialog.tabWidget.qt_tabwidget_stackedwidget.tab.txtLog'
            if ($null -ne $log) {
                $read=Get-FhzlLogTail $log
                $tail=$read.text; $logState=$read.state
            }
        } catch { $logState='read_error' }
        return Convert-FhzlSnapshot -PrintText $print -FileText $file -Alarm $alarm -AlarmRead $alarmRead -StatusLines $statusLines -LogTail $tail -LogState $logState
    } catch {
        $script:FhzlWindow=$null
        return @{line='ERROR|READ_FAILED'; extra=$extra}
    }
}
# Compatibility for earlier callers.
function Get-PrinterState { return (Get-PrinterTelemetry).line }
