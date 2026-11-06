unit FleetForm;
{$mode objfpc}{$H+}
{$codepage utf8}
interface
uses Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Grids,
  Process, IniFiles, fpjson, jsonparser;
type
  TFleetForm = class(TForm)
  private
    Worker: TProcess;
    Tick: TTimer;
    HostEdit, IdEdit, NameEdit, PortEdit: TEdit;
    RunButton: TButton;
    StateLabel: TLabel;
    Grid: TStringGrid;
    Log, Details: TMemo;
    DetailText: array of string;
    Pending: string;
    LastSeen: array of QWord;
    procedure StartClick(Sender: TObject);
    procedure Poll(Sender: TObject);
    procedure HandleLine(const Line: string);
    procedure AddLog(const S: string);
    procedure ShowDetails(Sender: TObject);
    function FormatDetails(O: TJSONObject): string;
    function AddEdit(const Title, Value: string; X, W: Integer): TEdit;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;
var MainForm: TFleetForm; AgentMode: Boolean;
implementation
function TFleetForm.AddEdit(const Title, Value: string; X, W: Integer): TEdit;
var L: TLabel;
begin
  L := TLabel.Create(Self); L.Parent := Self; L.SetBounds(X, 10, W, 20); L.Caption := Title;
  Result := TEdit.Create(Self); Result.Parent := Self;
  Result.SetBounds(X, 32, W, 28); Result.Text := Value;
end;
constructor TFleetForm.Create(AOwner: TComponent);
var C: TIniFile; I: Integer;
const Headers: array[0..8] of string = ('ID', 'Принтер', 'Состояние', 'Слои',
  'Окончание', 'Тип окончания', 'Начало', 'Длительность', 'Получено');
begin
  inherited CreateNew(AOwner);
  Width := 1120; Height := 820; Constraints.MinWidth := 1060; Constraints.MinHeight := 760; Position := poScreenCenter;
  Caption := 'FHZL — общий монитор';
  if AgentMode then Caption := 'FHZL — сборщик показателей';
  C := TIniFile.Create(ChangeFileExt(Application.ExeName, '.ini'));
  try
    PortEdit := AddEdit('Порт', C.ReadString('network', 'port', '5055'), 12, 80);
    if AgentMode then begin
      HostEdit := AddEdit('IP компьютера монитора', C.ReadString('network', 'host', ''), 110, 220);
      IdEdit := AddEdit('Уникальный ID принтера', C.ReadString('printer', 'id', ''), 350, 180);
      NameEdit := AddEdit('Название принтера', C.ReadString('printer', 'name', ''), 550, 250);
    end;
  finally C.Free end;
  RunButton := TButton.Create(Self); RunButton.Parent := Self;
  RunButton.SetBounds(820, 30, 200, 30); RunButton.Caption := 'Запустить'; RunButton.OnClick := @StartClick;
  StateLabel := TLabel.Create(Self); StateLabel.Parent := Self;
  StateLabel.SetBounds(12, 78, 1060, 28); StateLabel.Caption := 'Введите настройки и нажмите «Запустить».';
  Grid := TStringGrid.Create(Self); Grid.Parent := Self; Grid.SetBounds(12, 110, 1070, 260);
  Grid.Anchors := [akLeft, akTop, akRight]; Grid.ColCount := 9; Grid.RowCount := 2;
  Grid.FixedRows := 1; Grid.FixedCols := 0; Grid.DefaultColWidth := 145;
  for I := 0 to 8 do Grid.Cells[I,0] := Headers[I];
  Grid.ColWidths[2] := 360; SetLength(LastSeen, 2); SetLength(DetailText, 2);
  Grid.OnClick := @ShowDetails;
  Details := TMemo.Create(Self); Details.Parent := Self;
  Details.SetBounds(12, 385, 1070, 220); Details.Anchors := [akLeft, akTop, akRight];
  Details.ReadOnly := True; Details.ScrollBars := ssAutoBoth;
  Details.Text := 'Выберите принтер в таблице для просмотра показателей и конца журнала.';
  Log := TMemo.Create(Self); Log.Parent := Self; Log.SetBounds(12, 620, 1070, 140);
  Log.Anchors := [akLeft, akTop, akRight, akBottom]; Log.ReadOnly := True; Log.ScrollBars := ssAutoVertical;
  Tick := TTimer.Create(Self); Tick.Interval := 100; Tick.OnTimer := @Poll;
end;
procedure TFleetForm.AddLog(const S: string);
begin
  Log.Lines.Add(FormatDateTime('hh:nn:ss',Now) + ' ' + S);
  while Log.Lines.Count > 200 do Log.Lines.Delete(0);
end;
procedure TFleetForm.StartClick(Sender: TObject);
var Port: Integer; C: TIniFile; Script: string;
begin
  if Assigned(Worker) then Exit;
  if not TryStrToInt(PortEdit.Text, Port) or (Port < 1) or (Port > 65535) then begin
    StateLabel.Caption := 'Укажите порт от 1 до 65535.'; Exit;
  end;
  if AgentMode then
    if (Trim(HostEdit.Text) = '') or (Trim(IdEdit.Text) = '') or (Trim(NameEdit.Text) = '') or
       (Length(IdEdit.Text) > 80) or (Length(NameEdit.Text) > 120) then begin
      StateLabel.Caption := 'Укажите адрес монитора, уникальный ID (до 80 символов) и имя (до 120).'; Exit;
    end;
  if AgentMode then Script := 'SendPrinter.ps1' else Script := 'ReceiveFleet.ps1';
  Script := ExtractFilePath(Application.ExeName) + Script;
  if not FileExists(Script) then begin StateLabel.Caption := UTF8String('Рядом с EXE не найден ') + Script; Exit end;
  try
    C := TIniFile.Create(ChangeFileExt(Application.ExeName, '.ini'));
    try
      C.WriteString('network', 'port', PortEdit.Text);
      if AgentMode then begin
        C.WriteString('network', 'host', Trim(HostEdit.Text));
        C.WriteString('printer', 'id', Trim(IdEdit.Text));
        C.WriteString('printer', 'name', Trim(NameEdit.Text));
      end;
    finally C.Free end;
    Worker := TProcess.Create(nil);
    Worker.Executable := GetEnvironmentVariable('SystemRoot') + '\System32\WindowsPowerShell\v1.0\powershell.exe';
    Worker.Parameters.Add('-NoLogo'); Worker.Parameters.Add('-NoProfile');
    Worker.Parameters.Add('-NonInteractive'); Worker.Parameters.Add('-ExecutionPolicy');
    Worker.Parameters.Add('Bypass'); Worker.Parameters.Add('-File'); Worker.Parameters.Add(Script);
    Worker.Parameters.Add('-Port'); Worker.Parameters.Add(IntToStr(Port));
    if AgentMode then begin
      Worker.Parameters.Add('-Server'); Worker.Parameters.Add(Trim(HostEdit.Text));
      Worker.Parameters.Add('-PrinterId'); Worker.Parameters.Add(Trim(IdEdit.Text));
      Worker.Parameters.Add('-PrinterName'); Worker.Parameters.Add(Trim(NameEdit.Text));
    end;
    Worker.Options := [poUsePipes, poStderrToOutPut, poNoConsole]; Worker.Execute;
    Pending := ''; RunButton.Enabled := False; PortEdit.Enabled := False;
    if AgentMode then begin HostEdit.Enabled := False; IdEdit.Enabled := False; NameEdit.Enabled := False end;
    StateLabel.Caption := 'Запуск...'; AddLog('Запуск');
  except on E: Exception do begin FreeAndNil(Worker); StateLabel.Caption := E.Message; AddLog(E.Message) end end;
end;
procedure TFleetForm.HandleLine(const Line: string);
var Data: TJSONData; O: TJSONObject; Kind, ID, Status, OldStatus: string; R, I: Integer;
begin
  Data := nil;
  try
  try
    Data := GetJSON(Line);
    if not (Data is TJSONObject) then Exit;
    O := TJSONObject(Data); Kind := O.Get('type', '');
    if Kind = 'error' then begin StateLabel.Caption := UTF8String('Ошибка: ') + O.Get('detail',''); AddLog(StateLabel.Caption); Exit end;
    if Kind = 'listening' then begin StateLabel.Caption := 'Приём запущен. Ожидание принтеров.'; AddLog(StateLabel.Caption); Exit end;
    if (Kind <> 'telemetry') or (O.Get('version',0) <> 1) then Exit;
    ID := O.Get('id',''); if ID = '' then Exit;
    R := 0;
    for I := 1 to Grid.RowCount-1 do if Grid.Cells[0,I] = ID then begin R := I; Break end;
    if R = 0 then begin
      if Grid.Cells[0,1] = '' then R := 1 else begin R := Grid.RowCount; Grid.RowCount := R+1; SetLength(LastSeen, R+1); SetLength(DetailText, R+1) end;
      Grid.Cells[0,R] := ID;
    end;
    Status := 'Показатели получены';
    DetailText[R] := FormatDetails(O);
    if Grid.Row = R then ShowDetails(Self);
    if (O.Find('extra') is TJSONObject) then
      if TJSONObject(O.Find('extra')).Get('alarm','') <> '' then
        Status := UTF8String('Сообщение FHZL: ') + TJSONObject(O.Find('extra')).Get('alarm','');
    if O.Get('state','') <> 'ok' then begin
      Status := O.Get('detail',UTF8String('Ошибка чтения'));
      if Pos('WINDOW_NOT_FOUND',Status)>0 then Status := 'Окно FHZL не найдено'
      else if Pos('TEXT_NOT_FOUND',Status)>0 then Status := 'Блок показателей не найден'
      else if Pos('READ_FAILED',Status)>0 then Status := 'Ошибка чтения окна FHZL';
    end;
    if AgentMode then begin
      if O.Get('sent',False) then StateLabel.Caption := 'Данные отправлены монитору.'
      else StateLabel.Caption := 'Нет связи с монитором. Повторное подключение автоматически.';
    end;
    OldStatus := Grid.Cells[2,R]; Grid.Cells[1,R] := O.Get('name',''); Grid.Cells[2,R] := Status;
    Grid.Cells[3,R] := O.Get('printed','') + ' / ' + O.Get('total','');
    Grid.Cells[4,R] := O.Get('finish','');
    if O.Get('finishKind','') = 'ESTIMATE' then Grid.Cells[5,R] := 'Расчётное'
    else if O.Get('finishKind','') = 'FINISHED' then Grid.Cells[5,R] := 'Фактическое'
    else Grid.Cells[5,R] := '';
    Grid.Cells[6,R] := O.Get('start',''); Grid.Cells[7,R] := O.Get('duration','');
    Grid.Cells[8,R] := FormatDateTime('dd.mm hh:nn:ss',Now); LastSeen[R] := GetTickCount64;
    if OldStatus <> Status then AddLog(Grid.Cells[1,R] + ': ' + Status);
  except on E: Exception do AddLog(UTF8String('Не удалось разобрать ответ: ') + Copy(Line,1,200)) end;
  finally Data.Free end;
end;
procedure TFleetForm.ShowDetails(Sender: TObject);
var S: string; R: Integer;
begin
  R := Grid.Row;
  if (R < 1) or (R > High(DetailText)) or (DetailText[R] = '') then Exit;
  S := DetailText[R];
  if (LastSeen[R] <> 0) and (GetTickCount64 - LastSeen[R] > 5000) then
    S := UTF8String('ВНИМАНИЕ: данные устарели.') + LineEnding + S;
  if Details.Text <> S then Details.Text := S;
end;
function TFleetForm.FormatDetails(O: TJSONObject): string;
var E: TJSONObject; L: TStringList;
  procedure Field(const Title, Key: string);
  var V: string;
  begin
    V := E.Get(Key, ''); if V = '' then V := UTF8String('недоступно');
    L.Add(Title + ': ' + V);
  end;
begin
  Result := UTF8String('Этот сборщик передаёт только основные показатели. Обновите его для подробных данных.');
  if not (O.Find('extra') is TJSONObject) then Exit;
  E := TJSONObject(O.Find('extra')); L := TStringList.Create;
  try
    Field('Сообщение FHZL (как в верхней строке)', 'alarm');
    Field('Файл (как показывает FHZL)', 'file'); Field('Параметры печати', 'parameters');
    Field('Секунд на слой', 'layerSeconds'); Field('Среднее секунд на слой', 'layerAverage');
    Field('Температура', 'temperature'); Field('Влажность', 'humidity');
    Field('Координаты', 'axes'); Field('Режимы', 'modes'); Field('Текст меток PLC', 'plcLabels');
    L.Add('Давление каналов и цвета индикаторов пока не считываются.');
    L.Add(''); L.Add('Последние строки журнала FHZL (история, не список текущих аварий):');
    L.Add(E.Get('logTail', ''));
    if E.Get('logState','') <> 'tail' then
      L.Add(UTF8String('Конец журнала недоступен: ') + E.Get('logState','unavailable'));
    Result := L.Text;
  finally L.Free end;
end;
procedure TFleetForm.Poll(Sender: TObject);
var B: array[0..4095] of Byte; N, P, I: Integer; Part, Line: string;
begin
  if Assigned(Worker) then begin
    N := Worker.Output.NumBytesAvailable;
    if N > SizeOf(B) then N := SizeOf(B);
    if N > 0 then begin
      N := Worker.Output.Read(B[0],N);
      if N>0 then begin SetLength(Part,N); Move(B[0],Part[1],N); Pending := Pending+Part end;
      P := Pos(#10,Pending);
      while P>0 do begin
        Line := Trim(Copy(Pending,1,P-1)); Delete(Pending,1,P);
        if Line<>'' then HandleLine(Line); P := Pos(#10,Pending);
      end;
      if Length(Pending)>65536 then begin Pending := ''; AddLog('Слишком длинный ответ сброшен') end;
    end;
    if not Worker.Running and (Worker.Output.NumBytesAvailable=0) then begin
      StateLabel.Caption := 'Процесс остановлен. Проверьте журнал и настройки.';
      AddLog(StateLabel.Caption); FreeAndNil(Worker); RunButton.Enabled := True; PortEdit.Enabled := True;
      if AgentMode then begin HostEdit.Enabled := True; IdEdit.Enabled := True; NameEdit.Enabled := True end;
    end;
  end;
  for I := 1 to High(LastSeen) do
    if (LastSeen[I]<>0) and (GetTickCount64-LastSeen[I]>5000) then begin
      if Grid.Cells[2,I]<>UTF8String('Нет свежих данных — связь или сборщик недоступны') then
        AddLog(Grid.Cells[1,I]+UTF8String(': нет свежих данных'));
      Grid.Cells[2,I] := UTF8String('Нет свежих данных — связь или сборщик недоступны');
    end;
  ShowDetails(Self);
end;
destructor TFleetForm.Destroy;
begin
  Tick.Enabled := False;
  if Assigned(Worker) then begin if Worker.Running then Worker.Terminate(0); FreeAndNil(Worker) end;
  inherited Destroy;
end;
end.
