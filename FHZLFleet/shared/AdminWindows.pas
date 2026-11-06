unit AdminWindows;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses Classes,SysUtils,Forms,Controls,StdCtrls,ExtCtrls,Grids,Graphics,
  Dialogs,AdminSecurity,PrinterSettings,FleetTheme,LCLType;
function RequestAdminAccess(Store: TAdminPassword; ChangePassword: Boolean=False): Boolean;
procedure OpenPrinterManagement(const SettingsPath: string; Store: TAdminPassword; OnChanged: TNotifyEvent);
implementation
type
  TPasswordWindow = class(TForm)
  private
    Store: TAdminPassword;
    Mode: Integer;
    OldEdit,NewEdit,ConfirmEdit: TEdit;
    ErrorLabel: TLabel;
    procedure Submit(Sender: TObject);
    procedure DialogKey(Sender:TObject;var Key:Word;Shift:TShiftState);
  public
    constructor Build(AStore: TAdminPassword; AChange: Boolean);
  end;
  TManagementWindow = class(TForm)
  private
    Config: TPrinterConfig;
    Store: TAdminPassword;
    FChanged: TNotifyEvent;
    Table: TStringGrid;
    NameEdit,HostEdit,PortEdit: TEdit;
    MessageLabel: TLabel;
    procedure RefreshTable(Index: Integer);
    procedure SelectPrinter(Sender: TObject);
    procedure DialogKey(Sender:TObject;var Key:Word;Shift:TShiftState);
    procedure TableKey(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure AddPrinter(Sender: TObject);
    procedure SavePrinter(Sender: TObject);
    procedure DeletePrinter(Sender: TObject);
    procedure ChangePassword(Sender: TObject);
    procedure DidChange(Index: Integer);
    function Port: Integer;
  public
    constructor Build(const Path: string; AStore: TAdminPassword; OnChanged: TNotifyEvent);
    destructor Destroy; override;
  end;
function LabelAt(Owner: TComponent; Parent: TWinControl; const Text: string; X,Y,W: Integer): TLabel;
begin
  Result := TLabel.Create(Owner); Result.Parent := Parent; Result.SetBounds(X,Y,W,24);
  Result.AutoSize := False; Result.Caption := Text; Result.Font.Color := $004A4036;
end;
function ButtonAt(Owner: TComponent; Parent: TWinControl; const Text: string; X,Y,W: Integer; Click: TNotifyEvent): TThemeButton;
begin
  Result := TThemeButton.Create(Owner); Result.Parent := Parent; Result.SetBounds(X,Y,W,36); Result.Caption := Text; Result.OnClick := Click;
  Result.Primary := (Text=UTF8String('Сохранить')) or (Text=UTF8String('Войти'));
  if Text=UTF8String('Сменить пароль') then Result.Icon := fiLock;
end;
constructor TPasswordWindow.Build(AStore: TAdminPassword; AChange: Boolean);
var Y: Integer; B: TThemeButton;
  function PasswordEdit(const Title: string): TEdit;
  begin
    LabelAt(Self,Self,Title,28,Y,385); Inc(Y,26);
    Result := TEdit.Create(Self); Result.Parent := Self; Result.SetBounds(28,Y,385,32);
    Result.PasswordChar := '*'; Inc(Y,48);
  end;
begin
  inherited CreateNew(nil); Store := AStore;
  Position := poOwnerFormCenter; BorderStyle := bsDialog; Color := clWhite;
  Font.Name := 'Segoe UI'; Font.Size := 10; ClientWidth := 440;
  KeyPreview:=True;OnKeyDown:=@DialogKey;
  Caption := 'Вход в управление'; Mode := 0;
  if AChange then begin Mode := 2; Caption := 'Сменить пароль' end
  else if not Store.IsConfigured then begin Mode := 1; Caption := 'Создать пароль управления' end;
  with TFleetIcon.Create(Self) do begin Parent:=Self;SetBounds(28,16,28,28);Kind:=fiLock end;
  LabelAt(Self,Self,'Управление списком принтеров',72,20,340).Font.Style := [fsBold];
  Y := 58;
  if Mode<>1 then OldEdit := PasswordEdit('Пароль администратора');
  if Mode<>0 then begin
    NewEdit := PasswordEdit('Новый пароль (не менее 8 символов)');
    ConfirmEdit := PasswordEdit('Повторите новый пароль');
  end;
  ErrorLabel := LabelAt(Self,Self,'',28,Y,385); ErrorLabel.Font.Color := $003530C0;
  ErrorLabel.Height := 48; ErrorLabel.WordWrap := True; Inc(Y,58);
  B := ButtonAt(Self,Self,'Отмена',164,Y,120,nil); B.ModalResult := mrCancel; B.Cancel := True;
  if Mode=0 then B := ButtonAt(Self,Self,'Войти',294,Y,120,@Submit)
  else B := ButtonAt(Self,Self,'Сохранить',294,Y,120,@Submit);
  B.Default := True; ClientHeight := Y+58;
  if Mode=1 then ActiveControl := NewEdit else ActiveControl := OldEdit;
end;
procedure TPasswordWindow.DialogKey(Sender:TObject;var Key:Word;Shift:TShiftState);
begin
  if Key=VK_ESCAPE then begin ModalResult:=mrCancel;Key:=0 end
  else if (Key=VK_RETURN) and not (ActiveControl is TThemeButton) then begin Key:=0;Submit(Self) end;
end;
procedure TPasswordWindow.Submit(Sender: TObject);
begin
  try
    if Mode=0 then begin
      if not Store.Verify(OldEdit.Text) then begin
        ErrorLabel.Caption := 'Неверный пароль'; OldEdit.Clear; OldEdit.SetFocus; Exit;
      end;
    end else begin
      if NewEdit.Text<>ConfirmEdit.Text then begin ErrorLabel.Caption := 'Новые пароли не совпадают'; Exit end;
      if Mode=1 then Store.Initialize(NewEdit.Text) else Store.Change(OldEdit.Text,NewEdit.Text);
    end;
    if Assigned(OldEdit) then OldEdit.Clear;
    if Assigned(NewEdit) then NewEdit.Clear;
    if Assigned(ConfirmEdit) then ConfirmEdit.Clear;
    ModalResult := mrOK;
  except on E: Exception do ErrorLabel.Caption := E.Message end;
end;
function RequestAdminAccess(Store: TAdminPassword; ChangePassword: Boolean): Boolean;
var F: TPasswordWindow;
begin
  F := TPasswordWindow.Build(Store,ChangePassword);
  try Result := F.ShowModal=mrOK finally F.Free end;
end;
constructor TManagementWindow.Build(const Path: string; AStore: TAdminPassword; OnChanged: TNotifyEvent);
var B: TThemeButton;
begin
  inherited CreateNew(nil); Store := AStore; FChanged := OnChanged;
  KeyPreview:=True;OnKeyDown:=@DialogKey;
  Caption := 'Управление принтерами'; Position := poOwnerFormCenter; BorderStyle := bsDialog;
  Color := clWhite; Font.Name := 'Segoe UI'; Font.Size := 10; ClientWidth := 650; ClientHeight := 568;
  Config := TPrinterConfig.Create(Path); Config.Load;
  LabelAt(Self,Self,'Принтеры локальной сети',24,16,590).Font.Style := [fsBold];
  Table := TStringGrid.Create(Self); Table.Parent := Self; Table.SetBounds(24,48,602,210);
  Table.ColCount := 3; Table.RowCount := 2; Table.FixedRows := 1; Table.FixedCols := 0;
  Table.Options := Table.Options + [goRowSelect] - [goEditing];
  Table.ColWidths[0] := 270; Table.ColWidths[1] := 210; Table.ColWidths[2] := 94;
  Table.Cells[0,0] := 'Название'; Table.Cells[1,0] := 'IP-адрес'; Table.Cells[2,0] := 'Порт';
  Table.DefaultRowHeight:=30;Table.FixedColor:=$00F4EFE9;
  Table.OnClick := @SelectPrinter; Table.OnKeyUp := @TableKey;
  LabelAt(Self,Self,'Название',24,284,130); NameEdit := TEdit.Create(Self); NameEdit.Parent := Self; NameEdit.SetBounds(170,280,456,32);
  LabelAt(Self,Self,'IP-адрес',24,330,130); HostEdit := TEdit.Create(Self); HostEdit.Parent := Self; HostEdit.SetBounds(170,326,456,32);
  LabelAt(Self,Self,'Порт',24,376,130); PortEdit := TEdit.Create(Self); PortEdit.Parent := Self; PortEdit.SetBounds(170,372,456,32); PortEdit.Text := '5055';
  ButtonAt(Self,Self,'Добавить',24,426,170,@AddPrinter);
  ButtonAt(Self,Self,'Сохранить',218,426,184,@SavePrinter);
  ButtonAt(Self,Self,'Удалить',426,426,200,@DeletePrinter);
  MessageLabel := LabelAt(Self,Self,'',24,472,602); MessageLabel.Font.Color := $003530C0;
  ButtonAt(Self,Self,'Сменить пароль',24,516,210,@ChangePassword);
  B := ButtonAt(Self,Self,'Закрыть',486,516,140,nil); B.ModalResult := mrClose; B.Cancel := True;
  RefreshTable(0);
end;
procedure TManagementWindow.DialogKey(Sender:TObject;var Key:Word;Shift:TShiftState);
begin if Key=VK_ESCAPE then begin ModalResult:=mrClose;Key:=0 end end;
procedure TManagementWindow.RefreshTable(Index: Integer);
var I: Integer;
begin
  Table.RowCount := Config.Count+1; if Table.RowCount<2 then Table.RowCount := 2;
  for I := 1 to Table.RowCount-1 do Table.Rows[I].Clear;
  for I := 0 to Config.Count-1 do begin
    Table.Cells[0,I+1] := Config.Items[I].Name; Table.Cells[1,I+1] := Config.Items[I].Host;
    Table.Cells[2,I+1] := IntToStr(Config.Items[I].Port);
  end;
  if Config.Count>0 then begin
    if Index>=Config.Count then Index := Config.Count-1; if Index<0 then Index := 0;
    Table.Row := Index+1;
  end;
  SelectPrinter(Self);
end;
procedure TManagementWindow.SelectPrinter(Sender: TObject);
var I: Integer;
begin
  I := Table.Row-1;
  if (I<0) or (I>=Config.Count) then begin NameEdit.Clear; HostEdit.Clear; PortEdit.Text := '5055'; Exit end;
  NameEdit.Text := Config.Items[I].Name; HostEdit.Text := Config.Items[I].Host; PortEdit.Text := IntToStr(Config.Items[I].Port);
end;
procedure TManagementWindow.TableKey(Sender: TObject; var Key: Word; Shift: TShiftState);
begin SelectPrinter(Self) end;
function TManagementWindow.Port: Integer;
begin
  if not TryStrToInt(Trim(PortEdit.Text),Result) then raise Exception.Create('Введите числовой порт');
end;
procedure TManagementWindow.DidChange(Index: Integer);
begin
  RefreshTable(Index); MessageLabel.Font.Color := $00508520; MessageLabel.Caption := 'Настройки сохранены';
  if Assigned(FChanged) then FChanged(Self);
end;
procedure TManagementWindow.AddPrinter(Sender: TObject);
begin
  try Config.Add(NameEdit.Text,HostEdit.Text,Port); DidChange(Config.Count-1)
  except on E: Exception do begin MessageLabel.Font.Color := $003530C0; MessageLabel.Caption := E.Message end end;
end;
procedure TManagementWindow.SavePrinter(Sender: TObject);
begin
  try Config.Edit(Table.Row-1,NameEdit.Text,HostEdit.Text,Port); DidChange(Table.Row-1)
  except on E: Exception do begin MessageLabel.Font.Color := $003530C0; MessageLabel.Caption := E.Message end end;
end;
procedure TManagementWindow.DeletePrinter(Sender: TObject);
var I: Integer;
begin
  I := Table.Row-1; if (I<0) or (I>=Config.Count) then Exit;
  if MessageDlg('Удалить принтер',UTF8String('Удалить «')+Config.Items[I].Name+UTF8String('» из списка наблюдения?'),mtConfirmation,[mbYes,mbNo],0)<>mrYes then Exit;
  try Config.Remove(I); DidChange(I)
  except on E: Exception do begin MessageLabel.Font.Color := $003530C0; MessageLabel.Caption := E.Message end end;
end;
procedure TManagementWindow.ChangePassword(Sender: TObject);
begin
  if RequestAdminAccess(Store,True) then begin MessageLabel.Font.Color := $00508520; MessageLabel.Caption := 'Пароль изменён' end;
end;
destructor TManagementWindow.Destroy;
begin Config.Free; inherited Destroy end;
procedure OpenPrinterManagement(const SettingsPath: string; Store: TAdminPassword; OnChanged: TNotifyEvent);
var F: TManagementWindow;
begin
  if not RequestAdminAccess(Store) then Exit;
  F := TManagementWindow.Build(SettingsPath,Store,OnChanged);
  try F.ShowModal finally F.Free end;
end;
end.
