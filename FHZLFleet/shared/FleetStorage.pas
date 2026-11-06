unit FleetStorage;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses Classes, SysUtils;
procedure WriteAtomic(const Path, Data: string; ReplaceExisting: Boolean = True);
function ReadText(const Path: string): UTF8String;
implementation
uses {$IFDEF MSWINDOWS}Windows{$ELSE}BaseUnix{$ENDIF};
function ReadText(const Path: string): UTF8String;
var F: TFileStream;
begin
  F := TFileStream.Create(Path,fmOpenRead or fmShareDenyNone);
  try
    if F.Size>1024*1024 then raise EInOutError.Create('Файл настроек слишком большой');
    SetLength(Result,F.Size); if F.Size>0 then F.ReadBuffer(Result[1],Length(Result));
    if Copy(Result,1,3)=#$EF#$BB#$BF then Delete(Result,1,3);
  finally F.Free end;
end;
procedure WriteAtomic(const Path, Data: string; ReplaceExisting: Boolean);
var Temp: string; G: TGUID; F: TFileStream;
{$IFDEF MSWINDOWS} Flags: DWORD; WTemp,WPath: UnicodeString; {$ENDIF}
begin
  CreateGUID(G); Temp := Path + '.' + GUIDToString(G) + '.tmp';
  try
    F := TFileStream.Create(Temp,fmCreate);
    try
      if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data));
      if not FileFlush(F.Handle) then raise EInOutError.Create('Не удалось записать настройки на диск');
    finally F.Free end;
    {$IFDEF MSWINDOWS}
    Flags := $00000008; { MOVEFILE_WRITE_THROUGH }
    if ReplaceExisting then Flags := Flags or $00000001; { MOVEFILE_REPLACE_EXISTING }
    WTemp := UTF8Decode(Temp); WPath := UTF8Decode(Path);
    if not MoveFileExW(PWideChar(WTemp),PWideChar(WPath),Flags) then
      raise EInOutError.Create(UTF8String('Не удалось сохранить настройки: ')+SysErrorMessage(GetLastOSError));
    {$ELSE}
    if ReplaceExisting then begin
      if not RenameFile(Temp,Path) then raise EInOutError.Create('Не удалось заменить настройки');
    end else begin
      if fpLink(PChar(Temp),PChar(Path))<>0 then raise EInOutError.Create('Файл уже существует или недоступен для записи');
      SysUtils.DeleteFile(Temp);
    end;
    {$ENDIF}
  finally if FileExists(Temp) then SysUtils.DeleteFile(Temp) end;
end;
end.
