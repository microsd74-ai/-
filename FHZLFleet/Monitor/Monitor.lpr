program Monitor;
{$mode objfpc}{$H+}
uses Interfaces, Forms, MonitorWindow;
begin
  RequireDerivedFormResource := False;
  Application.Initialize;
  Application.CreateForm(TMonitorWindow, MonitorForm);
  Application.Run;
end.
