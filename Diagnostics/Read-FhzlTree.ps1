param(
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [ValidateRange(1,10000)][int]$MaxNodes=2500,
    [ValidateRange(1,100)][int]$MaxDepth=35
)
$ErrorActionPreference='Stop'
$utf8=[System.Text.UTF8Encoding]::new($true)
$nodes=$null
$text=$null
# Reflection makes provider getter failures explicit; PowerShell can otherwise
# silently turn a failing property getter into a null value.
function Read-Property($Object,[string]$Name) {
    if ($null -eq $Object) { throw ('Unavailable object for property '+$Name) }
    $property=$Object.GetType().GetProperty($Name)
    if ($null -eq $property) { throw ('Missing property '+$Name) }
    return $property.GetValue($Object,$null)
}
$result=[ordered]@{status='starting'; windows=0; nodes=0; limited=$false; errors=0; detail=''; capturedAt=[DateTime]::Now.ToString('o')}
try {
    $nodes=[System.IO.StreamWriter]::new((Join-Path $OutputDirectory 'elements.jsonl'),$false,$utf8)
    $nodes.AutoFlush=$true
    $text=[System.IO.StreamWriter]::new((Join-Path $OutputDirectory 'report.txt'),$false,$utf8)
    $text.AutoFlush=$true
    $text.WriteLine('FHZL UI Automation diagnostic. Read-only capture.')
    $text.WriteLine('Captured: '+$result.capturedAt)
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
    $root=[System.Windows.Automation.AutomationElement]::RootElement
    $windows=$root.FindAll([System.Windows.Automation.TreeScope]::Children,[System.Windows.Automation.Condition]::TrueCondition)
    $walker=[System.Windows.Automation.TreeWalker]::RawViewWalker
    $stack=[System.Collections.Generic.Stack[object]]::new()
    $windowIndex=0
    foreach ($window in $windows) {
        try {
            if ((Read-Property (Read-Property $window 'Current') 'Name') -notmatch 'FHZLPrinterManager') { continue }
            $windowIndex++
            if ($windowIndex -gt 10) { $result.limited=$true; break }
            $stack.Push(@{element=$window; parent=0; depth=0; path="window-$windowIndex"})
            $result.windows++
        } catch { $result.errors++ }
    }
    if ($result.windows -eq 0) {
        $result.status='window_not_found'
        $result.detail='Open FHZLPrinterManager in the same Windows session and run this capture again.'
    } else {
        $budget=5*1024*1024
        while ($stack.Count -gt 0) {
            if ($result.nodes -ge $MaxNodes -or $budget -le 0) { $result.limited=$true; break }
            $entry=$stack.Pop()
            $element=$entry.element
            $id=$result.nodes+1
            $record=[ordered]@{id=$id; parent=$entry.parent; path=$entry.path; depth=$entry.depth; name=''; automationId=''; className=''; controlType=''; isOffscreen=$null; processId=0; bounds=''; patterns=@(); value=''; valueTail=''; valueLength=0; text=''; textTail=''; patternErrors=@(); error=''; passwordSkipped=$false}
            try {
                $current=Read-Property $element 'Current'
                if (Read-Property $current 'IsPassword') {
                    $record.passwordSkipped=$true
                } else {
                    $record.name=([string](Read-Property $current 'Name'))
                    if ($record.name.Length -gt 8192) { $record.name=$record.name.Substring(0,8192); $result.limited=$true }
                    $record.automationId=([string](Read-Property $current 'AutomationId'))
                    $record.className=([string](Read-Property $current 'ClassName'))
                    $record.controlType=([string](Read-Property $current 'ControlType').ProgrammaticName)
                    $record.isOffscreen=(Read-Property $current 'IsOffscreen')
                    $record.processId=(Read-Property $current 'ProcessId')
                    $record.bounds=([string](Read-Property $current 'BoundingRectangle'))
                    try { $record.patterns=@($element.GetSupportedPatterns() | ForEach-Object { $_.ProgrammaticName }) }
                    catch { $result.errors++ }
                    try {
                        $pattern=$null
                        if ($element.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern,[ref]$pattern)) {
                            $v=[string](Read-Property (Read-Property $pattern 'Current') 'Value')
                            $record.valueLength=$v.Length
                            $record.valueTail=$v.Substring([Math]::Max(0,$v.Length-8192))
                            if ($v.Length -gt 8192) { $v=$v.Substring(0,8192); $result.limited=$true }
                            $record.value=$v
                        }
                    } catch { $result.errors++; $record.patternErrors+=('ValuePattern: '+$_.Exception.GetBaseException().Message) }
                    try {
                        $pattern=$null
                        if ($element.TryGetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern,[ref]$pattern)) {
                            $record.text=[string]$pattern.DocumentRange.GetText(8192)
                            if ($record.text.Length -ge 8192) { $result.limited=$true }
                            # Read the end of the document without scrolling or selecting.
                            $range=$pattern.DocumentRange.Clone()
                            $range.MoveEndpointByRange([System.Windows.Automation.Text.TextPatternRangeEndpoint]::Start,$range,[System.Windows.Automation.Text.TextPatternRangeEndpoint]::End)
                            [void]$range.MoveEndpointByUnit([System.Windows.Automation.Text.TextPatternRangeEndpoint]::Start,[System.Windows.Automation.Text.TextUnit]::Character,-8192)
                            $record.textTail=$range.GetText(8192)
                        }
                    } catch { $result.errors++; $record.patternErrors+=('TextPattern: '+$_.Exception.GetBaseException().Message) }
                }
            } catch {
                $record.error=$_.Exception.Message
                $result.errors++
            }
            $line=$record | ConvertTo-Json -Compress -Depth 5
            $nodes.WriteLine($line)
            $budget-=$utf8.GetByteCount($line)
            $text.WriteLine(('  '*$entry.depth)+"[$id] "+$record.controlType+' class='+$record.className+' automationId='+$record.automationId)
            if ($record.passwordSkipped) { $text.WriteLine('  [Password field omitted]') }
            foreach ($field in @('name','value','valueTail','text','textTail','patternErrors','error')) {
                if ($record[$field]) { $text.WriteLine('  '+$field+': '+$record[$field]) }
            }
            $result.nodes++
            # Password subtrees are omitted too. No input, focus, selection or scrolling calls.
            if ($record.passwordSkipped) { continue }
            if ($entry.depth -ge $MaxDepth) { $result.limited=$true; continue }
            try {
                $children=[System.Collections.Generic.List[object]]::new()
                $child=$walker.GetFirstChild($element)
                while ($null -ne $child) {
                    if ($children.Count -ge $MaxNodes) { $result.limited=$true; break }
                    $children.Add($child)
                    $child=$walker.GetNextSibling($child)
                }
                for ($i=$children.Count-1; $i -ge 0; $i--) {
                    $stack.Push(@{element=$children[$i]; parent=$id; depth=$entry.depth+1; path=($entry.path+'/'+$i)})
                }
            } catch { $result.errors++ }
        }
        $result.status='complete'
        if ($result.limited -or $result.errors -gt 0) { $result.status='partial' }
    }
} catch {
    $result.status='failed'
    $result.detail=$_.Exception.Message
} finally {
    if ($null -ne $nodes) { $nodes.Dispose() }
    if ($null -ne $text) { $text.Dispose() }
    $result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'result.json') -Encoding UTF8
}
if ($result.status -eq 'failed' -or $result.status -eq 'window_not_found') { exit 1 }
