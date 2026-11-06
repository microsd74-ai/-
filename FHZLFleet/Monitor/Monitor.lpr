program Monitor;
{$mode objfpc}{$H+}
uses Interfaces, Forms, MonitorWindow;
{$IFDEF MSWINDOWS}{$R WindowsTheme.res}{$ENDIF}
begin
  RequireDerivedFormResource := False;
  Application.Initialize;
  Application.CreateForm(TMonitorWindow, MonitorForm);
  Application.Run;
end.
