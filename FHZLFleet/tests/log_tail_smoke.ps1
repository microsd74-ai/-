$ErrorActionPreference='Stop'
# Load only real, read-only helper functions; no Windows or FHZL required.
$tokens=$null; $errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '../Agent/ReadPrinter.ps1'),[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
foreach ($name in @('Read-FhzlProperty','Get-FhzlLogTail')) {
    $function=$ast.Find({param($a) $a -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -eq $name},$true)
    . ([scriptblock]::Create($function.Extent.Text))
}
Add-Type -TypeDefinition @'
using System;
namespace System.Windows.Automation {
 public class TextPattern { public static string Pattern="Text"; }
 public class ValuePattern { public static string Pattern="Value"; }
 }
namespace System.Windows.Automation.Text {
 public enum TextPatternRangeEndpoint { Start, End }
 public enum TextUnit { Character }
}
public class TailValue { public string Value {get;set;} }
public class TailValuePattern { public TailValue Current {get;set;} }
public class TailRange {
 public bool Fail; public string Content;
 public TailRange Clone() { return this; }
 public void MoveEndpointByRange(System.Windows.Automation.Text.TextPatternRangeEndpoint a,TailRange b,System.Windows.Automation.Text.TextPatternRangeEndpoint c) {
  if (Fail) throw new NotSupportedException("Qt range endpoints unsupported");
 }
 public int MoveEndpointByUnit(System.Windows.Automation.Text.TextPatternRangeEndpoint a,System.Windows.Automation.Text.TextUnit u,int n) { return n; }
 public string GetText(int n) { return Content.Substring(Math.Max(0,Content.Length-n)); }
}
public class TailTextPattern { public TailRange DocumentRange {get;set;} }
public class TailElement {
 public bool TextSupported=true, ValueSupported=true, FailRange=true, FailValue=false;
 public string Content;
 public bool TryGetCurrentPattern(string name,out object pattern) {
  if (name=="Text") { pattern=new TailTextPattern{DocumentRange=new TailRange{Fail=FailRange,Content=Content}}; return TextSupported; }
  if (FailValue) throw new Exception("Value provider failure");
  pattern=new TailValuePattern{Current=new TailValue{Value=Content}}; return ValueSupported;
 }
}
'@
$e=[TailElement]::new(); $e.Content=('OLD DATA '*1500)+"`n[2026-11-06 17:34:00] Warning: newest event"
$r=Get-FhzlLogTail $e
if ($r.state -ne 'tail' -or $r.source -ne 'ValuePattern' -or $r.text -notlike '*newest event' -or $r.text.Length -ne 6000) { throw 'Fallback failed' }
Write-Output 'PASS: unsupported text endpoints fall back to the LAST 6000 ValuePattern characters'
$e.FailRange=$false; $r=Get-FhzlLogTail $e
if ($r.source -ne 'TextPattern' -or $r.text -notlike '*newest event') { throw 'TextPattern path failed' }
Write-Output 'PASS: supported TextPattern still preferred'
$e.TextSupported=$false; $e.ValueSupported=$false; $r=Get-FhzlLogTail $e
if ($r.state -ne 'unavailable') { throw 'Missing patterns misreported' }
$e.TextSupported=$true; $e.FailRange=$true; $e.FailValue=$true; $r=Get-FhzlLogTail $e
if ($r.state -ne 'read_error' -or $r.text -ne '') { throw 'Provider failures misreported' }
Write-Output 'PASS: missing patterns and provider failures are distinct; no fabricated log'
