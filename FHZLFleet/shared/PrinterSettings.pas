unit PrinterSettings;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses Classes,SysUtils;
type
  TPrinterSetting = record Name: UTF8String; Host: string; Port: Integer end;
  TPrinterArray = array of TPrinterSetting;
  TPrinterConfig = class
  private
    FPath: string;
    FItems: TPrinterArray;
    function GetCount: Integer;
    function GetItem(Index: Integer): TPrinterSetting;
    procedure Validate(const Item: TPrinterSetting; ExceptIndex: Integer);
  public
    constructor Create(const Path: string);
    procedure Load;
    procedure Add(const Name,Host: string; Port: Integer);
    procedure Edit(Index: Integer; const Name,Host: string; Port: Integer);
    procedure Remove(Index: Integer);
    function FindEndpoint(const ID: string): Integer;
    property Count: Integer read GetCount;
    property Items[Index: Integer]: TPrinterSetting read GetItem;
  end;
function CanonicalIPv4(const Value: string): string;
function Endpoint(const Item: TPrinterSetting): string;
implementation
uses fpjson,jsonparser,FleetStorage;
function CanonicalIPv4(const Value: string): string;
var L: TStringList; I,N: Integer; C: Char; S: string;
begin
  S := Trim(Value); Result := ''; L := TStringList.Create;
  try
    for C in S do if not (C in ['0'..'9','.']) then raise Exception.Create('Введите IPv4, например 192.168.1.101');
    L.StrictDelimiter := True; L.Delimiter := '.'; L.DelimitedText := S;
    if L.Count<>4 then raise Exception.Create('IP должен состоять из четырёх чисел');
    for I := 0 to 3 do begin
      if not TryStrToInt(L[I],N) or (N<0) or (N>255) then raise Exception.Create('Числа IP должны быть от 0 до 255');
      if I>0 then Result := Result+'.'; Result := Result+IntToStr(N);
    end;
    if (Result='0.0.0.0') or (Result='255.255.255.255') then raise Exception.Create('Укажите адрес компьютера принтера');
  finally L.Free end;
end;
function Endpoint(const Item: TPrinterSetting): string;
begin Result := Item.Host+':'+IntToStr(Item.Port) end;
constructor TPrinterConfig.Create(const Path: string);
begin inherited Create; FPath := Path end;
function TPrinterConfig.GetCount: Integer;
begin Result := Length(FItems) end;
function TPrinterConfig.GetItem(Index: Integer): TPrinterSetting;
begin Result := FItems[Index] end;
function TPrinterConfig.FindEndpoint(const ID: string): Integer;
var I: Integer;
begin for I := 0 to Count-1 do if Endpoint(FItems[I])=ID then Exit(I); Result := -1 end;
procedure TPrinterConfig.Validate(const Item: TPrinterSetting; ExceptIndex: Integer);
var I: Integer;
begin
  if (Trim(Item.Name)='') or (Length(Item.Name)>120) then raise Exception.Create('Введите название принтера (до 120 символов)');
  if CanonicalIPv4(Item.Host)<>Item.Host then raise Exception.Create('Неверный формат IP');
  if (Item.Port<1) or (Item.Port>65535) then raise Exception.Create('Порт должен быть от 1 до 65535');
  for I := 0 to Count-1 do if I<>ExceptIndex then begin
    if Endpoint(FItems[I])=Endpoint(Item) then raise Exception.Create('Этот IP и порт уже добавлены');
    if UTF8Decode(FItems[I].Name)=UTF8Decode(Item.Name) then raise Exception.Create('Укажите другое название принтера');
  end;
end;
procedure SaveItems(const Path: string; const Items: TPrinterArray);
var O,P: TJSONObject; A,T: TJSONArray; I: Integer;
begin
  O := TJSONObject.Create;
  try
    A := TJSONArray.Create; T := TJSONArray.Create; O.Add('printers',A); O.Add('targets',T); O.Add('version',2);
    for I := 0 to High(Items) do begin
      P := TJSONObject.Create; P.Add('name',Items[I].Name); P.Add('host',Items[I].Host); P.Add('port',Items[I].Port); A.Add(P);
      T.Add(Endpoint(Items[I]));
    end;
    WriteAtomic(Path,O.AsJSON);
  finally O.Free end;
end;
procedure TPrinterConfig.Load;
var D: TJSONData; O,P: TJSONObject; A: TJSONArray; I,J,N: Integer; S: string; NewItems,Old: TPrinterArray;
begin
  if not FileExists(FPath) then begin SetLength(FItems,0); Exit end;
  D := GetJSON(ReadText(FPath)); Old := FItems;
  try
  try
    if not (D is TJSONObject) then raise Exception.Create('Повреждён список принтеров'); O := TJSONObject(D);
    if O.Find('printers') is TJSONArray then A := TJSONArray(O.Find('printers'))
    else if O.Find('targets') is TJSONArray then A := TJSONArray(O.Find('targets'))
    else raise Exception.Create('Не найден список принтеров');
    if A.Count>128 then raise Exception.Create('Поддерживается до 128 принтеров');
    SetLength(NewItems,A.Count);
    for I := 0 to A.Count-1 do begin
      if A[I] is TJSONObject then begin
        P := TJSONObject(A[I]); NewItems[I].Name := P.Get('name',UTF8String('')); NewItems[I].Host := CanonicalIPv4(P.Get('host','')); NewItems[I].Port := P.Get('port',0);
      end else if A[I].JSONType=jtString then begin
        S := A.Strings[I]; J := Pos(':',S);
        if (J<2) or not TryStrToInt(Copy(S,J+1,Length(S)),N) then raise Exception.Create('Повреждён адрес принтера');
        NewItems[I].Host := CanonicalIPv4(Copy(S,1,J-1)); NewItems[I].Port := N; NewItems[I].Name := Endpoint(NewItems[I]);
      end else raise Exception.Create('Повреждена запись принтера');
    end;
    FItems := NewItems;
    for I := 0 to Count-1 do Validate(FItems[I],I);
  except FItems := Old; raise end;
  finally D.Free end;
end;
procedure TPrinterConfig.Add(const Name,Host: string; Port: Integer);
var Item: TPrinterSetting; NewItems: TPrinterArray;
begin
  if Count>=128 then raise Exception.Create('Поддерживается до 128 принтеров');
  Item.Name := Trim(Name); Item.Host := CanonicalIPv4(Host); Item.Port := Port; Validate(Item,-1);
  NewItems := Copy(FItems,0,Count); SetLength(NewItems,Count+1); NewItems[High(NewItems)] := Item;
  SaveItems(FPath,NewItems); FItems := NewItems;
end;
procedure TPrinterConfig.Edit(Index: Integer; const Name,Host: string; Port: Integer);
var Item: TPrinterSetting; NewItems: TPrinterArray;
begin
  if (Index<0) or (Index>=Count) then raise Exception.Create('Выберите принтер');
  Item.Name := Trim(Name); Item.Host := CanonicalIPv4(Host); Item.Port := Port; Validate(Item,Index);
  NewItems := Copy(FItems,0,Count); NewItems[Index] := Item; SaveItems(FPath,NewItems); FItems := NewItems;
end;
procedure TPrinterConfig.Remove(Index: Integer);
var NewItems: TPrinterArray; I: Integer;
begin
  if (Index<0) or (Index>=Count) then raise Exception.Create('Выберите принтер');
  SetLength(NewItems,Count-1);
  for I := 0 to Index-1 do NewItems[I] := FItems[I];
  for I := Index+1 to Count-1 do NewItems[I-1] := FItems[I];
  SaveItems(FPath,NewItems); FItems := NewItems;
end;
end.
