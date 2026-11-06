# Runs the real scripts against a simulated UI Automation boundary.
# It does not validate Windows/FHZL accessibility providers.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$temp=Join-Path ([IO.Path]::GetTempPath()) ('fhzl-test-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
try {
    foreach ($file in @('Collect-Fhzl.ps1','Read-FhzlTree.ps1')) {
        $tokens=$null; $errors=$null
        [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root $file),[ref]$tokens,[ref]$errors)
        if ($errors.Count) { throw ($errors | Out-String) }
    }
    Write-Output 'PASS: PowerShell syntax'
    $mock=@'
Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
namespace System.Windows.Automation {
    public enum TreeScope { Children }
    public enum TextPatternRangeEndpoint { Start, End }
    public enum TextUnit { Character }
    public class Condition { public static object TrueCondition = new object(); }
    public class ValuePattern { public static string Pattern = "Value"; }
    public class TextPattern { public static string Pattern = "Text"; }
    public class Kind { public string ProgrammaticName = "ControlType.Text"; }
    public class Properties {
        public string Name {get; set;}
        public string AutomationId {get; set;} = "";
        public string ClassName {get; set;} = "Mock";
        public string BoundingRectangle {get; set;} = "0,0,100,20";
        public Kind ControlType {get; set;} = new Kind();
        public bool IsOffscreen {get; set;} public bool IsPassword {get; set;}
        public int ProcessId {get; set;} = 123;
    }
    public class PatternName { public string ProgrammaticName; public PatternName(string n) { ProgrammaticName=n; } }
    public class ValueData { public string Value {get; set;} }
    public class MockValue { public ValueData Current {get; set;} = new ValueData(); }
    public class Range {
        public string Text;
        public int Start=0, End=-1;
        private int Limit { get { return End<0 ? Text.Length : End; } }
        public string GetText(int n) { return Text.Substring(Start,Math.Min(n,Limit-Start)); }
        public Range Clone() { return new Range { Text=Text, Start=Start, End=Limit }; }
        public void MoveEndpointByRange(TextPatternRangeEndpoint a,Range b,TextPatternRangeEndpoint c) { Start=b.Limit; }
        public int MoveEndpointByUnit(TextPatternRangeEndpoint a,TextUnit u,int n) { int old=Start; Start=Math.Max(0,Start+n); return Start-old; }
    }
    public class MockText { public Range DocumentRange = new Range(); }
    public class AutomationElement {
        public static AutomationElement RootElement;
        public Properties Props = new Properties();
        public Properties Current { get { if (Gone) throw new Exception("Unavailable element"); return Props; } }
        public bool Gone;
        public AutomationElement Parent;
        public List<AutomationElement> Children = new List<AutomationElement>();
        public MockValue Value;
        public MockText Text;
        public AutomationElement(string n) { Props.Name=n; }
        public AutomationElement Add(AutomationElement c) { c.Parent=this; Children.Add(c); return c; }
        public AutomationElement[] FindAll(TreeScope s, object c) { return Children.ToArray(); }
        public PatternName[] GetSupportedPatterns() { return new[] { new PatternName("MockPattern") }; }
        public bool TryGetCurrentPattern(string p, out object value) {
            value = p=="Value" ? (object)Value : (object)Text;
            return value!=null;
        }
        public static void Setup() {
            RootElement=new AutomationElement("Desktop");
            RootElement.Add(new AutomationElement("Unrelated application"));
            var window=RootElement.Add(new AutomationElement("FHZLPrinterManager, Ver:1.0.1"));
            window.Add(new AutomationElement("Emian.2:Not set Home alarm"));
            var pressure=window.Add(new AutomationElement("Channel 1"));
            pressure.Value=new MockValue(); pressure.Value.Current.Value="-5.76";
            var log=window.Add(new AutomationElement("System Run Log"));
            log.Text=new MockText(); log.Text.DocumentRange.Text="Warning [5484]: Not set Home alarm"+new string('x',9000)+"\n[2026-11-06 17:15:00] Latest event";
            var password=window.Add(new AutomationElement("SECRET")); password.Props.IsPassword=true;
            password.Add(new AutomationElement("CHILD_SECRET"));
            window.Add(new AutomationElement("Gone" )).Gone=true;
        }
    }
    public class TreeWalker {
        public static TreeWalker RawViewWalker = new TreeWalker();
        public AutomationElement GetFirstChild(AutomationElement e) { return e.Children.Count>0 ? e.Children[0] : null; }
        public AutomationElement GetNextSibling(AutomationElement e) {
            if (e.Parent==null) return null;
            int i=e.Parent.Children.IndexOf(e)+1;
            return i<e.Parent.Children.Count ? e.Parent.Children[i] : null;
        }
    }
}
"@
[System.Windows.Automation.AutomationElement]::Setup()
'@
    $original=Get-Content -LiteralPath (Join-Path $root 'Read-FhzlTree.ps1') -Raw
    if (-not $original.Contains('    Add-Type -AssemblyName UIAutomationClient')) { throw 'Test boundary changed' }
    $capture=$original.Replace('    Add-Type -AssemblyName UIAutomationClient',$mock).Replace('    Add-Type -AssemblyName UIAutomationTypes','')
    $worker=Join-Path $temp 'Read-FhzlTree.ps1'
    Set-Content -LiteralPath $worker -Value $capture -Encoding UTF8
    $pwsh=(Get-Process -Id $PID).Path
    function Capture([string]$Name,[string[]]$Extra=@()) {
        $out=Join-Path $temp $Name
        [void][IO.Directory]::CreateDirectory($out)
        & $pwsh -NoLogo -NoProfile -File $worker -OutputDirectory $out @Extra
        return $out
    }
    $out=Capture 'normal'
    $records=@(Get-Content -LiteralPath (Join-Path $out 'elements.jsonl') | ForEach-Object { $_ | ConvertFrom-Json })
    $result=Get-Content -LiteralPath (Join-Path $out 'result.json') -Raw | ConvertFrom-Json
    if ($result.status -ne 'partial' -or $records.Count -ne 6 -or $result.errors -lt 1) { throw ('Expected six nodes and an inaccessible-element error: '+($result | ConvertTo-Json -Compress)) }
    if (-not ($records | Where-Object { $_.value -eq '-5.76' })) { throw 'Missing ValuePattern data' }
    if (-not ($records | Where-Object { $_.text -like '*5484*' })) { throw 'Missing TextPattern data' }
    if (-not ($records | Where-Object { $_.textTail -like '*Latest event*' -and $_.text -notlike '*Latest event*' })) { throw 'Log tail was not captured independently of its beginning' }
    if ((Get-Content -LiteralPath (Join-Path $out 'elements.jsonl') -Raw) -match 'SECRET|Unrelated application') { throw 'Private/unrelated data captured' }
    foreach ($record in $records) {
        if ($record.parent -ne 0 -and -not ($records | Where-Object { $_.id -eq $record.parent })) { throw 'Missing parent record' }
        if ($record.path -notlike 'window-1*') { throw 'Unexpected element path' }
    }
    Write-Output 'PASS: names, pressure ValuePattern, log TextPattern, password subtree omission, stale element and parent paths'
    $limited=Capture 'limited' @('-MaxNodes','2')
    $result=Get-Content -LiteralPath (Join-Path $limited 'result.json') -Raw | ConvertFrom-Json
    if (-not $result.limited -or $result.nodes -ne 2) { throw 'Node limit failed' }
    Write-Output 'PASS: node limit produces an explicit partial result'
    Set-Content -LiteralPath $worker -Value ($capture.Replace('FHZLPrinterManager, Ver:1.0.1','Another window')) -Encoding UTF8
    $missing=Capture 'missing'
    $result=Get-Content -LiteralPath (Join-Path $missing 'result.json') -Raw | ConvertFrom-Json
    if ($result.status -ne 'window_not_found' -or $result.nodes -ne 0) { throw 'Missing-window outcome incorrect' }
    Write-Output 'PASS: no FHZL window gives an explicit failure summary'
    Set-Content -LiteralPath $worker -Value $capture -Encoding UTF8
    # Run the real coordinator with only its Windows executable path replaced.
    $coordinator=Get-Content -LiteralPath (Join-Path $root 'Collect-Fhzl.ps1') -Raw
    $needle="    `$powershell=Join-Path `$env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'"
    if (-not $coordinator.Contains($needle)) { throw 'Coordinator test boundary changed' }
    $coordinator=$coordinator.Replace($needle,"    `$powershell='"+$pwsh.Replace("'","''")+"'")
    $collect=Join-Path $temp 'Collect-Fhzl.ps1'
    Set-Content -LiteralPath $collect -Value $coordinator -Encoding UTF8
    & $pwsh -NoLogo -NoProfile -File $collect -TimeoutSeconds 15
    if ($LASTEXITCODE -ne 0) { throw 'Coordinator failed' }
    $zip=Get-ChildItem (Join-Path $temp 'reports') -Filter '*.zip' | Select-Object -First 1
    if ($null -eq $zip) { throw 'No ZIP' }
    $expanded=Join-Path $temp 'expanded'
    Expand-Archive -LiteralPath $zip.FullName -DestinationPath $expanded
    if (-not (Test-Path (Join-Path $expanded 'elements.jsonl'))) { throw 'ZIP missing elements' }
    Write-Output 'PASS: coordinator starts worker and creates a readable report ZIP'
    Set-Content -LiteralPath $worker -Value 'Start-Sleep -Seconds 30' -Encoding UTF8
    & $pwsh -NoLogo -NoProfile -File $collect -TimeoutSeconds 5
    if ($LASTEXITCODE -ne 0) { throw 'Timeout capture did not preserve report' }
    $summaries=@(Get-ChildItem (Join-Path $temp 'reports') -Recurse -Filter 'result.json' | ForEach-Object { Get-Content $_.FullName -Raw | ConvertFrom-Json })
    if (-not ($summaries | Where-Object { $_.status -eq 'timeout' })) { throw 'Missing timeout summary' }
    Write-Output 'PASS: blocked worker terminated, timeout summary archived'
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force
}
