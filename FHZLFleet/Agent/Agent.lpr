program Agent;
{$mode objfpc}{$H+}
uses Interfaces, Forms, FleetForm;
begin
  RequireDerivedFormResource := False;
  Application.Initialize;
  AgentMode := True;
  Application.CreateForm(TFleetForm, MainForm);
  Application.Run;
end.
