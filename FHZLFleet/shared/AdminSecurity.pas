unit AdminSecurity;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses Classes, SysUtils;
type
  TAdminPassword = class
  private
    FPath: string;
    procedure SavePassword(const Password: string; ReplaceExisting: Boolean);
  public
    constructor Create(const Path: string);
    function IsConfigured: Boolean;
    function Verify(const Password: string): Boolean;
    procedure Initialize(const Password: string);
    procedure Change(const OldPassword, NewPassword: string);
  end;
implementation
uses fpjson,jsonparser,FleetStorage;
const Iterations = 210000;
type TSalt = array[0..15] of Byte; TKey = array[0..31] of Byte;
{$IFDEF MSWINDOWS}
function BCryptGenRandom(Algorithm: Pointer; Buffer: PByte; Count,Flags: LongWord): LongInt; stdcall; external 'bcrypt.dll';
function BCryptOpenAlgorithmProvider(out Algorithm: Pointer; ID,ProviderImplementation: PWideChar; Flags: LongWord): LongInt; stdcall; external 'bcrypt.dll';
function BCryptDeriveKeyPBKDF2(Algorithm: Pointer; Password: PByte; PasswordLength: LongWord; Salt: PByte; SaltLength: LongWord; Count: QWord; Key: PByte; KeyLength,Flags: LongWord): LongInt; stdcall; external 'bcrypt.dll';
function BCryptCloseAlgorithmProvider(Algorithm: Pointer; Flags: LongWord): LongInt; stdcall; external 'bcrypt.dll';
{$ELSE}
function RAND_bytes(Buffer: PByte; Count: Integer): Integer; cdecl; external 'crypto';
function EVP_sha256: Pointer; cdecl; external 'crypto';
function PKCS5_PBKDF2_HMAC(Password: PChar; PasswordLength: Integer; Salt: PByte; SaltLength,Count: Integer; Digest: Pointer; KeyLength: Integer; Key: PByte): Integer; cdecl; external 'crypto';
{$ENDIF}
procedure RandomSalt(out Salt: TSalt);
begin
  {$IFDEF MSWINDOWS}
  if BCryptGenRandom(nil,@Salt[0],SizeOf(Salt),2)<0 then
  {$ELSE}
  if RAND_bytes(@Salt[0],SizeOf(Salt))<>1 then
  {$ENDIF}
    raise Exception.Create('Не удалось получить случайные данные для пароля');
end;
procedure Derive(const Password: string; const Salt: TSalt; Count: Integer; out Key: TKey);
{$IFDEF MSWINDOWS}var Algorithm: Pointer; ID: UnicodeString;{$ENDIF}
begin
  {$IFDEF MSWINDOWS}
  ID := 'SHA256'; Algorithm := nil;
  if BCryptOpenAlgorithmProvider(Algorithm,PWideChar(ID),nil,8)<0 then raise Exception.Create('Не удалось открыть SHA-256');
  try
    if BCryptDeriveKeyPBKDF2(Algorithm,PByte(PChar(Password)),Length(Password),@Salt[0],SizeOf(Salt),Count,@Key[0],SizeOf(Key),0)<0 then
      raise Exception.Create('Не удалось проверить пароль');
  finally BCryptCloseAlgorithmProvider(Algorithm,0) end;
  {$ELSE}
  if PKCS5_PBKDF2_HMAC(PChar(Password),Length(Password),@Salt[0],SizeOf(Salt),Count,EVP_sha256,SizeOf(Key),@Key[0])<>1 then
    raise Exception.Create('Не удалось проверить пароль');
  {$ENDIF}
end;
function Hex(const Buffer; Count: Integer): string;
var I: Integer; P: PByte;
begin Result := ''; P := @Buffer; for I := 0 to Count-1 do Result := Result+LowerCase(IntToHex(P[I],2)) end;
procedure Decode(const S: string; var Buffer; Count: Integer);
var I,N: Integer; P: PByte;
begin
  if Length(S)<>Count*2 then raise Exception.Create('Повреждён файл пароля');
  P := @Buffer;
  for I := 0 to Count-1 do begin
    if not TryStrToInt('$'+Copy(S,I*2+1,2),N) then raise Exception.Create('Повреждён файл пароля');
    P[I] := N;
  end;
end;
constructor TAdminPassword.Create(const Path: string);
begin inherited Create; FPath := Path end;
function TAdminPassword.IsConfigured: Boolean;
begin Result := FileExists(FPath) end;
procedure TAdminPassword.SavePassword(const Password: string; ReplaceExisting: Boolean);
var Salt: TSalt; Key: TKey; O: TJSONObject;
begin
  if (Length(UTF8Decode(Password))<8) or (Trim(Password)='') then raise Exception.Create('Пароль должен содержать не менее 8 символов');
  RandomSalt(Salt); Derive(Password,Salt,Iterations,Key);
  O := TJSONObject.Create;
  try
    O.Add('version',1); O.Add('algorithm','PBKDF2-HMAC-SHA256'); O.Add('iterations',Iterations);
    O.Add('salt',Hex(Salt,SizeOf(Salt))); O.Add('hash',Hex(Key,SizeOf(Key)));
    WriteAtomic(FPath,O.AsJSON,ReplaceExisting);
  finally FillChar(Key,SizeOf(Key),0); O.Free end;
end;
procedure TAdminPassword.Initialize(const Password: string);
begin
  if IsConfigured then raise Exception.Create('Пароль уже создан');
  SavePassword(Password,False);
end;
function TAdminPassword.Verify(const Password: string): Boolean;
var D: TJSONData; O: TJSONObject; Salt: TSalt; Expected,Actual: TKey; Count,I,Diff: Integer;
begin
  Result := False;
  if not IsConfigured then Exit;
  D := GetJSON(ReadText(FPath));
  try
    if not (D is TJSONObject) then raise Exception.Create('Повреждён файл пароля');
    O := TJSONObject(D);
    if (O.Get('version',0)<>1) or (O.Get('algorithm','')<>'PBKDF2-HMAC-SHA256') then raise Exception.Create('Неподдерживаемый файл пароля');
    Count := O.Get('iterations',0);
    if (Count<210000) or (Count>2000000) then raise Exception.Create('Повреждены параметры пароля');
    Decode(O.Get('salt',''),Salt,SizeOf(Salt)); Decode(O.Get('hash',''),Expected,SizeOf(Expected));
    Derive(Password,Salt,Count,Actual); Diff := 0;
    for I := 0 to High(Actual) do Diff := Diff or (Actual[I] xor Expected[I]);
    Result := Diff=0;
    FillChar(Actual,SizeOf(Actual),0); FillChar(Expected,SizeOf(Expected),0);
  finally D.Free end;
end;
procedure TAdminPassword.Change(const OldPassword,NewPassword: string);
begin
  if not Verify(OldPassword) then raise Exception.Create('Текущий пароль неверен');
  SavePassword(NewPassword,True);
end;
end.
