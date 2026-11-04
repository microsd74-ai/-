program Monitor;
{$mode objfpc}{$H+}
uses Interfaces, Forms, FleetForm;
begin
  RequireDerivedFormResource := False;
  Application.Initialize;
  AgentMode := False;
  Application.CreateForm(TFleetForm, MainForm);
  Application.Run;
end.
