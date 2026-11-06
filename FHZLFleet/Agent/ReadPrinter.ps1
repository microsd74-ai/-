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
function Get-PrinterTelemetry {
    $extra=[ordered]@{alarm=''; logTail=''; logState='unavailable'}
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
        $alarm=''
        if ($null -ne $toolbar) {
            foreach ($e in $toolbar.FindAll([System.Windows.Automation.TreeScope]::Children,[System.Windows.Automation.Condition]::TrueCondition)) {
                try { $s=Read-FhzlName $e; if ($s -match '^\d+/\d+:') { $alarm=$s; break } } catch { }
            }
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
                $pattern=$null
                if ($log.TryGetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern,[ref]$pattern)) {
                    $range=$pattern.DocumentRange.Clone()
                    $range.MoveEndpointByRange([System.Windows.Automation.TextPatternRangeEndpoint]::Start,$range,[System.Windows.Automation.TextPatternRangeEndpoint]::End)
                    [void]$range.MoveEndpointByUnit([System.Windows.Automation.TextPatternRangeEndpoint]::Start,[System.Windows.Automation.TextUnit]::Character,-6000)
                    $tail=$range.GetText(6000); $logState='tail'
                }
            }
        } catch { $logState='read_error' }
        return Convert-FhzlSnapshot -PrintText $print -FileText $file -Alarm $alarm -StatusLines $statusLines -LogTail $tail -LogState $logState
    } catch {
        $script:FhzlWindow=$null
        return @{line='ERROR|READ_FAILED'; extra=$extra}
    }
}
# Compatibility for earlier callers.
function Get-PrinterState { return (Get-PrinterTelemetry).line }
