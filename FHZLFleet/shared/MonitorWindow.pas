unit MonitorWindow;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses Classes,SysUtils,Forms,Controls,StdCtrls,ExtCtrls,Graphics,Process,
  fpjson,jsonparser,Dialogs,PrinterSettings,AdminSecurity,FleetTheme,Menus,Math;
type
  TPrinterView = class
  public
    ID,Connection: string;
    Snapshot: TJSONObject;
    Received: QWord;
    Events: TStringList;
    constructor Create(const Endpoint: string);
    destructor Destroy; override;
    procedure Event(const Text: string);
  end;
  TMonitorWindow = class(TForm)
  private
    Config: TPrinterConfig;
    Password: TAdminPassword;
    States: TList;
    Worker: TProcess;
    Timer: TTimer;
    Pending,GlobalError: string;
    FUpdating: Boolean;
    Header,Body: TPanel;
    WarningBox,MetaBox,JournalBox,EventsBox: TThemeCard;
    Scroller: TScrollBox;
    PickerButton,ManageButton: TThemeButton;
    ChoiceMenu: TPopupMenu;
    WarningIcon: TFleetIcon;
    FLayout: Boolean;
    Cards: array[0..3] of TThemeCard;
    CardTitles: array[0..3] of TLabel;
    CardValues: array[0..3] of TLabel;
    Picker: TComboBox;

    Badge,PrinterTitle,Subtitle,WarningTitle,WarningText,FileLabel,ModeLabel,AxesLabel,TimeLabel,ExtraLabel: TLabel;
    Dot: TShape;
    PrinterLog,ConnectionLog: TMemo;
    procedure BuildUI;
    procedure OpenChoice(Sender: TObject);
    procedure ChooseItem(Sender: TObject);
    function U(Value: Integer): Integer;
    procedure LayoutBody(Sender: TObject);
    procedure SelectPrinter(Sender: TObject);
    procedure Manage(Sender: TObject);
    procedure SettingsChanged(Sender: TObject);
    procedure Poll(Sender: TObject);
    procedure StartWorker;
    procedure HandleLine(const Line: string);
    procedure Render;
    procedure RefreshNames;
    function FindState(const ID: string): TPrinterView;
    function Selected: TPrinterView;
    function NameFor(Index: Integer): string;
    function SettingsPath: string;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;
var MonitorForm: TMonitorWindow;
implementation
uses AdminWindows;
const Background = ThemeBackground; Ink = $003B3026; Muted = $007A7066; Border = $00DDD6CF;
function NewLabel(Owner: TComponent; Parent: TWinControl; const Text: string; X,Y,W,H,Size: Integer; Bold: Boolean=False): TLabel;
begin
  Result := TLabel.Create(Owner); Result.Parent := Parent; Result.SetBounds(X,Y,W,H);
  Result.AutoSize := False; Result.Transparent := True; Result.Caption := Text; Result.Font.Size := Size;
  Result.Font.Color := Ink; if Bold then Result.Font.Style := [fsBold];
end;
function Card(Owner: TComponent; Parent: TWinControl; X,Y,W,H: Integer): TThemeCard;
begin
  Result := TThemeCard.Create(Owner); Result.Parent := Parent; Result.SetBounds(X,Y,W,H);
end;
function IconAt(Owner:TComponent;Parent:TWinControl;Kind:TFleetIconKind;X,Y,W:Integer):TFleetIcon;
begin Result:=TFleetIcon.Create(Owner);Result.Parent:=Parent;Result.SetBounds(X,Y,W,W);Result.Kind:=Kind end;
constructor TPrinterView.Create(const Endpoint: string);
begin inherited Create; ID := Endpoint; Connection := 'disconnected'; Events := TStringList.Create end;
destructor TPrinterView.Destroy;
begin Snapshot.Free; Events.Free; inherited Destroy end;
procedure TPrinterView.Event(const Text: string);
begin
  Events.Add(FormatDateTime('hh:nn:ss',Now)+'  '+Text);
  while Events.Count>200 do Events.Delete(0);
end;
constructor TMonitorWindow.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner); Caption := 'FHZL — общий монитор';
  Position := poScreenCenter; Width := 1080; Height := 900; Constraints.MinWidth := 900; Constraints.MinHeight := 720;
  Font.Name := 'Segoe UI'; Font.Size := 10; Color := Background;
  States := TList.Create; Config := TPrinterConfig.Create(SettingsPath);
  Password := TAdminPassword.Create(ChangeFileExt(Application.ExeName,'.admin.json'));
  BuildUI;
  Timer := TTimer.Create(Self); Timer.Interval := 100; Timer.OnTimer := @Poll;
  SettingsChanged(Self);
end;
function TMonitorWindow.SettingsPath: string;
begin Result := ChangeFileExt(Application.ExeName,'.targets.json') end;
procedure TMonitorWindow.BuildUI;
var I: Integer;
const Titles: array[0..3] of string = ('Слои','Окончание','Температура','Влажность');
begin
  Header := TPanel.Create(Self); Header.Parent := Self; Header.Align := alTop; Header.Height := 72;
  Header.OnResize := @LayoutBody;
  Header.BevelOuter := bvNone; Header.ParentBackground := False; Header.Color := clWhite;
  NewLabel(Self,Header,'Принтер',24,24,90,28,11,True);
  Picker := TComboBox.Create(Self); Picker.Parent := Header; Picker.SetBounds(120,20,310,34);
  Picker.Style := csDropDownList; Picker.OnChange := @SelectPrinter; Picker.Visible := False;
  ChoiceMenu := TPopupMenu.Create(Self);
  PickerButton := TThemeButton.Create(Self); PickerButton.Parent := Header;
  PickerButton.SetBounds(120,18,310,38); PickerButton.DropDown := True; PickerButton.Caption := 'Выберите принтер'; PickerButton.OnClick := @OpenChoice;
  Dot := TShape.Create(Self); Dot.Parent := Header; Dot.SetBounds(453,30,11,11); Dot.Shape := stCircle; Dot.Pen.Style := psClear;
  Badge := NewLabel(Self,Header,'Нет подключения',474,24,270,28,10); Badge.Anchors := [akLeft,akTop];
  ManageButton := TThemeButton.Create(Self); ManageButton.Parent := Header;
  ManageButton.SetBounds(ClientWidth-198,18,174,38); ManageButton.Anchors := [akLeft,akTop];
  ManageButton.Icon := fiLock; ManageButton.Caption := 'Управление'; ManageButton.OnClick := @Manage;
  Scroller := TScrollBox.Create(Self); Scroller.Parent := Self; Scroller.Align := alClient; Scroller.BorderStyle := bsNone;
  Scroller.Color := Background; Scroller.HorzScrollBar.Visible := False; Scroller.OnResize := @LayoutBody;
  Body := TPanel.Create(Self); Body.Parent := Scroller; Body.Align := alTop; Body.Height := 794;
  Body.BevelOuter := bvNone; Body.ParentBackground := False; Body.Color := Background; Body.OnResize := @LayoutBody;
  PrinterTitle := NewLabel(Self,Body,'Выберите принтер',24,16,900,38,22,True);
  Subtitle := NewLabel(Self,Body,'Показания выбранного принтера',24,57,900,25,10); Subtitle.Font.Color := Muted;
  WarningBox := Card(Self,Body,24,94,900,80);
  WarningTitle := NewLabel(Self,WarningBox,'Ожидание показателей',20,12,850,25,12,True);
  WarningText := NewLabel(Self,WarningBox,'Добавьте принтер через «Управление».',20,40,850,30,10);
  WarningText.WordWrap := True; WarningIcon := IconAt(Self,WarningBox,fiWarning,18,22,32); WarningIcon.Ink := $0011A5E9;
  for I := 0 to 3 do begin
    Cards[I] := Card(Self,Body,24+I*240,190,224,96);
    IconAt(Self,Cards[I],TFleetIconKind(Ord(fiLayers)+I),18,14,28);
    CardTitles[I] := NewLabel(Self,Cards[I],Titles[I],58,16,150,24,10,True);
    CardValues[I] := NewLabel(Self,Cards[I],'—',18,42,190,42,22,True);
    CardValues[I].Alignment := taCenter;
    if I=1 then begin CardValues[I].Font.Size := 13; CardValues[I].WordWrap := True; CardValues[I].Top := 38; CardValues[I].Height := 52 end;
  end;
  MetaBox := Card(Self,Body,24,302,900,152);
  FileLabel := NewLabel(Self,MetaBox,'Файл: —',18,12,850,25,10); FileLabel.ShowHint := True;
  ModeLabel := NewLabel(Self,MetaBox,'Режим: —',18,39,850,25,10);
  AxesLabel := NewLabel(Self,MetaBox,'Координаты: —',18,66,850,25,10);
  TimeLabel := NewLabel(Self,MetaBox,'Обновлено: —',18,93,850,25,10);
  ExtraLabel := NewLabel(Self,MetaBox,'',18,120,850,23,9); ExtraLabel.Font.Color := Muted;
  JournalBox := Card(Self,Body,24,470,900,182);
  JournalBox.HeadingHeight := 42; IconAt(Self,JournalBox,fiDocument,18,9,24);
  NewLabel(Self,JournalBox,'Журнал принтера',54,11,750,25,12,True);
  PrinterLog := TMemo.Create(Self); PrinterLog.Parent := JournalBox; PrinterLog.SetBounds(18,46,864,120);
  PrinterLog.ReadOnly := True; PrinterLog.BorderStyle := bsNone; PrinterLog.ScrollBars := ssAutoVertical;
  PrinterLog.WordWrap := True; PrinterLog.Color := clWhite;
  EventsBox := Card(Self,Body,24,668,900,108);
  EventsBox.HeadingHeight := 42; IconAt(Self,EventsBox,fiLink,18,9,24);
  NewLabel(Self,EventsBox,'События подключения',54,11,750,25,12,True);
  ConnectionLog := TMemo.Create(Self); ConnectionLog.Parent := EventsBox; ConnectionLog.SetBounds(18,42,864,50);
  ConnectionLog.ReadOnly := True; ConnectionLog.BorderStyle := bsNone; ConnectionLog.ScrollBars := ssAutoVertical;
  ConnectionLog.WordWrap := True; ConnectionLog.Color := clWhite;
  LayoutBody(Self);
end;
function TMonitorWindow.U(Value:Integer):Integer;
begin Result:=Scale96ToForm(Value) end;
procedure TMonitorWindow.OpenChoice(Sender:TObject);
var I:Integer; Item:TMenuItem; P:TPoint;
begin
  ChoiceMenu.Items.Clear;
  for I:=0 to Picker.Items.Count-1 do begin
    Item:=TMenuItem.Create(ChoiceMenu);Item.Caption:=Picker.Items[I];Item.Tag:=I;
    Item.Checked:=I=Picker.ItemIndex;Item.RadioItem:=True;Item.OnClick:=@ChooseItem;ChoiceMenu.Items.Add(Item);
  end;
  if ChoiceMenu.Items.Count=0 then Exit;
  P:=PickerButton.ClientToScreen(Point(0,PickerButton.Height+U(3)));ChoiceMenu.PopUp(P.X,P.Y);
end;
procedure TMonitorWindow.ChooseItem(Sender:TObject);
begin Picker.ItemIndex:=TMenuItem(Sender).Tag;SelectPrinter(Self) end;
procedure TMonitorWindow.LayoutBody(Sender: TObject);
var W,CW,I,L,JH,EH:Integer;
begin
  if FLayout or not Assigned(EventsBox) then Exit;
  FLayout:=True;
  try
    Header.Height:=U(66);
    W:=Min(U(1000),Body.ClientWidth-U(40)); if W<U(740) then W:=U(740);
    L:=(Body.ClientWidth-W) div 2;
    ManageButton.SetBounds(L+W-U(180),U(15),U(180),U(38));
    PickerButton.SetBounds(L+U(96),U(15),U(310),U(38));
    { The compact toolbar follows the same centred column as the dashboard. }
    Header.Controls[0].SetBounds(L,U(23),U(90),U(28));
    Dot.SetBounds(L+U(430),U(29),U(10),U(10)); Badge.SetBounds(L+U(450),U(23),U(250),U(26));
    Body.Height:=Max(U(680),Scroller.ClientHeight);
    PrinterTitle.SetBounds(L,U(12),W,U(36)); Subtitle.SetBounds(L,U(51),W,U(25));
    WarningBox.SetBounds(L,U(86),W,U(72)); WarningTitle.SetBounds(U(66),U(12),W-U(86),U(24));
    WarningText.SetBounds(U(66),U(39),W-U(86),U(28));WarningIcon.SetBounds(U(18),U(20),U(32),U(32));
    CW:=(W-U(36)) div 4;
    for I:=0 to 3 do begin
      Cards[I].SetBounds(L+I*(CW+U(12)),U(172),CW,U(88));
      CardTitles[I].SetBounds(U(56),U(16),CW-U(68),U(22));
      CardValues[I].SetBounds(U(12),U(41),CW-U(24),U(40));
      if I=1 then begin CardValues[I].Top:=U(38);CardValues[I].Height:=U(48) end;
    end;
    MetaBox.SetBounds(L,U(274),W,U(138));
    FileLabel.SetBounds(U(18),U(10),W-U(36),U(23));ModeLabel.SetBounds(U(18),U(35),W-U(36),U(23));
    AxesLabel.SetBounds(U(18),U(60),W-U(36),U(23));TimeLabel.SetBounds(U(18),U(85),W-U(36),U(23));
    ExtraLabel.SetBounds(U(18),U(110),W-U(36),U(22));
    EH:=U(104);JH:=Body.Height-U(426)-EH-U(30);
    JournalBox.SetBounds(L,U(426),W,JH);PrinterLog.SetBounds(U(18),U(52),W-U(36),JH-U(66));
    EventsBox.SetBounds(L,U(426)+JH+U(14),W,EH);ConnectionLog.SetBounds(U(18),U(51),W-U(36),EH-U(63));
  finally FLayout:=False end;
end;
function TMonitorWindow.FindState(const ID: string): TPrinterView;
var I: Integer;
begin
  Result := nil;
  for I := 0 to States.Count-1 do if TPrinterView(States[I]).ID=ID then Exit(TPrinterView(States[I]));
end;
function TMonitorWindow.Selected: TPrinterView;
begin
  Result := nil;
  if (Picker.ItemIndex>=0) and (Picker.ItemIndex<Picker.Items.Count) then Result := TPrinterView(Picker.Items.Objects[Picker.ItemIndex]);
end;
function TMonitorWindow.NameFor(Index: Integer): string;
var V: TPrinterView;
begin
  Result := Config.Items[Index].Name;
  if Result=Endpoint(Config.Items[Index]) then begin
    Result := UTF8String('Принтер ')+IntToStr(Index+1);
    V := FindState(Endpoint(Config.Items[Index]));
    if Assigned(V) and Assigned(V.Snapshot) and (V.Snapshot.Get('name','')<>'') then Result := V.Snapshot.Get('name','');
  end;
end;
procedure TMonitorWindow.RefreshNames;
var I,N: Integer;
begin
  if Picker.Items.Count<>Config.Count then Exit;
  FUpdating := True; N := Picker.ItemIndex;
  try
    for I := 0 to Config.Count-1 do if Picker.Items[I]<>NameFor(I) then Picker.Items[I] := NameFor(I);
    Picker.ItemIndex := N;
  finally FUpdating := False end;
end;
procedure TMonitorWindow.SettingsChanged(Sender: TObject);
var ID: string; I,N: Integer; V: TPrinterView;
begin
  ID := ''; if Assigned(Selected) then ID := Selected.ID;
  try
    Config.Load;
    FUpdating := True;
    try
      Picker.Items.Clear;
      for I := States.Count-1 downto 0 do if Config.FindEndpoint(TPrinterView(States[I]).ID)<0 then begin TPrinterView(States[I]).Free; States.Delete(I) end;
      N := 0;
      for I := 0 to Config.Count-1 do begin
        V := FindState(Endpoint(Config.Items[I]));
        if not Assigned(V) then begin V := TPrinterView.Create(Endpoint(Config.Items[I])); States.Add(V) end;
        Picker.Items.AddObject(NameFor(I),V); if V.ID=ID then N := I;
      end;
      if Picker.Items.Count>0 then Picker.ItemIndex := N else Picker.ItemIndex := -1;
    finally FUpdating := False end;
    GlobalError := ''; if Config.Count>0 then StartWorker;
  except on E: Exception do GlobalError := E.Message end;
  Render;
end;
procedure TMonitorWindow.SelectPrinter(Sender: TObject);
begin if not FUpdating then Render end;
procedure TMonitorWindow.Manage(Sender: TObject);
begin
  try OpenPrinterManagement(SettingsPath,Password,@SettingsChanged)
  except on E: Exception do MessageDlg('Управление',E.Message,mtError,[mbOK],0) end;
end;
procedure TMonitorWindow.StartWorker;
var Script: string;
begin
  if Assigned(Worker) then Exit;
  Script := ExtractFilePath(Application.ExeName)+'ReceiveFleet.ps1';
  if not FileExists(Script) then raise Exception.Create('Не найден ReceiveFleet.ps1 рядом с EXE');
  Worker := TProcess.Create(nil);
  try
    Worker.Executable := GetEnvironmentVariable('SystemRoot')+'\System32\WindowsPowerShell\v1.0\powershell.exe';
    Worker.Parameters.Add('-NoLogo'); Worker.Parameters.Add('-NoProfile'); Worker.Parameters.Add('-NonInteractive');
    Worker.Parameters.Add('-ExecutionPolicy'); Worker.Parameters.Add('Bypass'); Worker.Parameters.Add('-File'); Worker.Parameters.Add(Script);
    Worker.Parameters.Add('-TargetsFile'); Worker.Parameters.Add(SettingsPath); Worker.Options := [poUsePipes,poStderrToOutPut,poNoConsole];
    Worker.Execute; Pending := '';
  except FreeAndNil(Worker); raise end;
end;
procedure TMonitorWindow.HandleLine(const Line: string);
var D: TJSONData; O: TJSONObject; V: TPrinterView; Kind,Status,PreviousState,ID: string;
begin
  if Line='System.Threading.Tasks.VoidTaskResult' then Exit;
  D := nil;
  try
    try
      D := GetJSON(Line); if not (D is TJSONObject) then raise Exception.Create('Неверный ответ считывателя');
      O := TJSONObject(D); Kind := O.Get('type','');
      if (Kind='error') or (Kind='config_error') then begin GlobalError := O.Get('detail',UTF8String('Ошибка считывателя')); Exit end;
      ID := O.Get('id',''); if Config.FindEndpoint(ID)<0 then Exit;
      V := FindState(ID); if not Assigned(V) then Exit;
      if Kind='connection' then begin
        V.Connection := O.Get('state','');
        if V.Connection='connecting' then Status := 'Подключение к принтеру...'
        else if V.Connection='connected' then Status := 'Связь установлена, ожидание показаний'
        else Status := 'Связь потеряна. Повторное подключение автоматически.';
        V.Event(Status); Exit;
      end;
      if (Kind<>'telemetry') or (O.Get('version',0)<>1) then Exit;
      PreviousState := ''; if Assigned(V.Snapshot) then PreviousState := V.Snapshot.Get('state','')+'|'+V.Snapshot.Get('detail','');
      Status := O.Get('state','')+'|'+O.Get('detail','');
      if Status<>PreviousState then begin
        if O.Get('state','')='ok' then V.Event('Показания получены')
        else V.Event(UTF8String('Ошибка чтения FHZL: ')+O.Get('detail',''));
      end;
      V.Snapshot.Free; V.Snapshot := TJSONObject(O.Clone);
      V.Snapshot.Add('receivedDisplay',FormatDateTime('dd.mm.yyyy hh:nn:ss',Now));
      V.Received := GetTickCount64; V.Connection := 'connected'; GlobalError := '';
      RefreshNames;
    except on Ex: Exception do GlobalError := UTF8String('Ошибка ответа: ')+Ex.Message end;
  finally D.Free end;
end;
procedure TMonitorWindow.Render;
var V: TPrinterView; O,E: TJSONObject; Stale: Boolean; S,Alarm,State,Value: string; I: Integer;
  function Extra(const Key: string): string;
  begin Result := ''; if Assigned(E) then Result := E.Get(Key,'') end;
  function OrDash(const Text: string): string;
  begin if Text='' then Result := '—' else Result := Text end;
  procedure MemoText(M: TMemo; const Text: string);
  begin if TrimRight(M.Text)<>TrimRight(Text) then M.Text := Text end;
begin
  V := Selected; O := nil; E := nil;
  if Assigned(V) then PickerButton.Caption := Picker.Text else PickerButton.Caption := 'Выберите принтер';
  if Assigned(V) then O := V.Snapshot;
  if Assigned(O) and (O.Find('extra') is TJSONObject) then E := TJSONObject(O.Find('extra'));
  Stale := not Assigned(V);
  if Assigned(V) then Stale := (V.Received=0) or (GetTickCount64-V.Received>5000) or (V.Connection<>'connected');
  if Assigned(V) then PrinterTitle.Caption := Picker.Text else PrinterTitle.Caption := 'Принтеры не добавлены';
  Subtitle.Caption := 'Показания выбранного принтера';
  for I := 0 to 3 do CardValues[I].Caption := '—';
  CardValues[1].Caption := 'Нет данных'; CardTitles[1].Caption := 'Окончание';
  WarningBox.FillColor := clWhite; WarningIcon.Visible := False;
  FileLabel.Caption := 'Файл: —'; FileLabel.Hint := ''; ModeLabel.Caption := 'Режим: —'; AxesLabel.Caption := 'Координаты: —'; TimeLabel.Caption := 'Обновлено: —';
  ExtraLabel.Caption := ''; WarningTitle.Caption := 'Ожидание показателей'; WarningText.Caption := 'Добавьте принтер через «Управление».';
  Dot.Brush.Color := $009D958A; Badge.Caption := 'Нет подключения'; WarningTitle.Font.Color := Ink;
  if not Assigned(O) then MemoText(PrinterLog,'');
  if not Assigned(V) then MemoText(ConnectionLog,'');
  if Assigned(V) then begin
    WarningText.Caption := 'Ожидание данных от агента.'; Badge.Caption := 'Подключение...';
    if V.Connection='disconnected' then Badge.Caption := 'Нет связи';
    if V.Connection='connected' then begin
      if Stale then Badge.Caption := 'Ожидание показаний'
      else begin Badge.Caption := 'На связи'; Dot.Brush.Color := $003FA52B end;
    end;
    MemoText(ConnectionLog,V.Events.Text);
  end;
  if Assigned(O) then begin
    CardValues[0].Caption := OrDash(O.Get('printed',''))+' / '+OrDash(O.Get('total',''));
    Value := O.Get('finish',''); if Value<>'' then CardValues[1].Caption := StringReplace(Value,' ',LineEnding,[]);
    if O.Get('finishKind','')='ESTIMATE' then CardTitles[1].Caption := 'Расчётное окончание'
    else if O.Get('finishKind','')='FINISHED' then CardTitles[1].Caption := 'Фактическое окончание';
    CardValues[2].Caption := OrDash(Extra('temperature')); CardValues[3].Caption := OrDash(Extra('humidity'));
    FileLabel.Caption := UTF8String('Файл: ')+OrDash(Extra('file')); FileLabel.Hint := Extra('file');
    ModeLabel.Caption := UTF8String('Режим: ')+OrDash(Extra('modes'));
    AxesLabel.Caption := UTF8String('Координаты: ')+OrDash(Extra('axes'));
    TimeLabel.Caption := UTF8String('Обновлено: ')+O.Get('receivedDisplay','');
    ExtraLabel.Caption := UTF8String('Секунд на слой: ')+OrDash(Extra('layerSeconds'))+UTF8String('  ·  Среднее: ')+OrDash(Extra('layerAverage'))+UTF8String('  ·  Длительность: ')+OrDash(O.Get('duration',''));
    Alarm := Extra('alarm'); State := O.Get('state','');
    if Alarm<>'' then begin WarningBox.FillColor := $00E7F3FF; WarningIcon.Visible := True; WarningTitle.Caption := 'Предупреждение FHZL'; WarningTitle.Font.Color := $002B65A5; WarningText.Caption := Alarm end
    else begin WarningTitle.Caption := 'Сообщение FHZL'; WarningText.Caption := 'Текст верхнего сообщения не получен.' end;
    if State<>'ok' then begin
      WarningIcon.Visible := True; WarningBox.FillColor := $00E7F3FF; WarningTitle.Caption := 'Показатели печати недоступны';
      S := O.Get('detail','');
      if Pos('WINDOW_NOT_FOUND',S)>0 then S := 'Окно FHZL не найдено'
      else if Pos('TEXT_NOT_FOUND',S)>0 then S := 'Блок показателей печати не найден'
      else if Pos('READ_FAILED',S)>0 then S := 'Ошибка чтения окна FHZL';
      if Alarm<>'' then S := S+UTF8String(' · ')+Alarm; WarningText.Caption := S;
    end;
    S := Extra('logTail');
    if (Extra('logState')<>'tail') then S := S+LineEnding+UTF8String('Конец журнала недоступен: ')+OrDash(Extra('logState'));
    MemoText(PrinterLog,S);
    if Stale then begin WarningTitle.Caption := 'Нет свежих данных'; WarningTitle.Font.Color := $003530B0; WarningText.Caption := 'Показаны последние известные значения. Ожидание связи с агентом.' end;
  end;
  if GlobalError<>'' then begin WarningTitle.Caption := 'Ошибка монитора'; WarningText.Caption := GlobalError; WarningTitle.Font.Color := $003530B0 end;
end;
procedure TMonitorWindow.Poll(Sender: TObject);
var B: array[0..4095] of Byte; N,P: Integer; Part,Line: string;
begin
  if Assigned(Worker) then begin
    N := Worker.Output.NumBytesAvailable; if N>SizeOf(B) then N := SizeOf(B);
    if N>0 then begin
      N := Worker.Output.Read(B[0],N);
      if N>0 then begin SetLength(Part,N); Move(B[0],Part[1],N); Pending := Pending+Part end;
      P := Pos(#10,Pending);
      while P>0 do begin
        Line := Trim(Copy(Pending,1,P-1)); Delete(Pending,1,P); if Line<>'' then HandleLine(Line); P := Pos(#10,Pending);
      end;
      if Length(Pending)>65536 then begin Pending := ''; GlobalError := 'Ответ считывателя слишком длинный' end;
    end;
    if not Worker.Running and (Worker.Output.NumBytesAvailable=0) then begin
      FreeAndNil(Worker); GlobalError := 'Считыватель остановлен. Проверьте скрипт и настройки.';
    end;
  end;
  Render;
end;
destructor TMonitorWindow.Destroy;
var I: Integer;
begin
  if Assigned(Timer) then Timer.Enabled := False;
  if Assigned(Worker) then begin if Worker.Running then Worker.Terminate(0); Worker.Free end;
  if Assigned(States) then begin for I := 0 to States.Count-1 do TPrinterView(States[I]).Free; States.Free end;
  Config.Free; Password.Free; inherited Destroy;
end;
end.
