program ScaledMonitor;
{$mode objfpc}{$H+}
uses Interfaces,Forms,Controls,MonitorWindow;
begin
  RequireDerivedFormResource:=False;
  Application.Initialize;
  Application.CreateForm(TMonitorWindow,MonitorForm);
  MonitorForm.AutoAdjustLayout(lapAutoAdjustForDPI,96,120,1080,1350);
  MonitorForm.Width:=1350;MonitorForm.Height:=1125;
  if MonitorForm.Scale96ToForm(100)<>125 then Halt(3);
  WriteLn('TEST: 125% DPI, 100 logical units = ',MonitorForm.Scale96ToForm(100),' physical pixels');
  Application.Run;
end.
