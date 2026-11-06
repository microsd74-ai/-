program CoreSmoke;
{$mode objfpc}{$H+}{$codepage utf8}
uses Classes,SysUtils,fpjson,jsonparser,FleetStorage,PrinterSettings,AdminSecurity;
procedure Check(B: Boolean; const S: string);
begin if not B then raise Exception.Create(S) end;
var C: TPrinterConfig; P,Q,R: TAdminPassword; Root,Before,Path,PassPath: string; Failed: Boolean;
begin
  { Match Lazarus/LCL's UTF-8 process convention for standalone CLI tests. }
  SetMultiByteConversionCodePage(CP_UTF8);
  if ParamCount<>1 then Halt(2); Root := IncludeTrailingPathDelimiter(ParamStr(1));
  ForceDirectories(Root); Path := Root+'targets.json'; PassPath := Root+'admin.json';
  WriteAtomic(Path,'{"targets":["192.168.1.101:5055"]}'); Before := ReadText(Path);
  C := TPrinterConfig.Create(Path);
  try
    C.Load; Check((C.Count=1) and (C.Items[0].Host='192.168.1.101'),'legacy config');
    Check(ReadText(Path)=Before,'read-only migration must preserve file');
    C.Edit(0,'FHZL PMMA','192.168.1.101',5055); C.Add('FHZL second','192.168.1.102',5056);
    C.Load; Check((C.Count=2) and (C.Items[0].Name='FHZL PMMA'),'names persist');
    Before := ReadText(Path); Failed := False;
    try C.Add('duplicate','192.168.1.101',5055) except Failed := True end;
    Check(Failed and (C.Count=2) and (ReadText(Path)=Before),'duplicate must not mutate settings');
    Failed := False; try C.Edit(0,'bad','256.0.0.1',5055) except Failed := True end;
    Check(Failed and (ReadText(Path)=Before),'invalid IPv4 must not mutate settings');
    Failed := False; try C.Add('FHZL PMMA','192.168.1.103',5055) except Failed := True end;
    Check(Failed and (ReadText(Path)=Before),'duplicate name rejected');
    C.Remove(1); C.Load; Check(C.Count=1,'remove persists'); C.Remove(0); C.Load; Check(C.Count=0,'empty list persists');
    C.Add('restored','127.0.0.1',5055); Before := ReadText(Path);
    WriteAtomic(Path,'{"printers":[{"name":"bad","host":"999.1.1.1","port":1}]}');
    Failed := False; try C.Load except Failed := True end;
    Check(Failed and (C.Count=1) and (C.Items[0].Name='restored'),'failed load preserves in-memory list');
    WriteAtomic(Path,Before);
    C.Add('Принтер тест','192.168.1.108',5055); C.Load; Check(UTF8Decode(C.Items[1].Name)='Принтер тест','UTF-8 names persist'); C.Remove(1);
    WriteLn('PASS: migration, names, duplicate rejection, invalid input, edit/delete, empty list and failed-load rollback');
  finally C.Free end;
  P := TAdminPassword.Create(PassPath); Q := TAdminPassword.Create(Root+'admin2.json'); R := TAdminPassword.Create(Root+'admin3.json');
  try
    Check(not P.Verify('anything'),'unconfigured must not authenticate');
    R.Initialize('Пароль-для-теста'); Check(R.Verify('Пароль-для-теста') and not R.Verify('Пароль-для-Теста'),'UTF-8 password');
    P.Initialize('FHZL-test-passphrase'); Q.Initialize('FHZL-test-passphrase');
    Check(P.Verify('FHZL-test-passphrase') and not P.Verify('wrong-password'),'password verification');
    Check(Pos('FHZL-test-passphrase',ReadText(PassPath))=0,'no plaintext password');
    Check(ReadText(PassPath)<>ReadText(Root+'admin2.json'),'random salts');
    Before := ReadText(PassPath); Failed := False;
    try P.Change('wrong-password','new-test-password') except Failed := True end;
    Check(Failed and (ReadText(PassPath)=Before),'bad old password preserves file');
    Failed := False; try P.Initialize('replacement-pass') except Failed := True end;
    Check(Failed and (ReadText(PassPath)=Before),'no reinitialize bypass');
    P.Change('FHZL-test-passphrase','new-test-password');
    Check(P.Verify('new-test-password') and not P.Verify('FHZL-test-passphrase'),'password change');
    WriteAtomic(PassPath,'{"version":1,"algorithm":"PBKDF2-HMAC-SHA256","iterations":0}');
    Failed := False; try P.Verify('anything') except Failed := True end;
    Check(Failed,'corrupt password file fails closed');
    WriteAtomic(PassPath,Before);
    WriteLn('PASS: salted PBKDF2, correct/wrong passwords, no plaintext, password change, no reinitialize, corrupt file rejection');
  finally P.Free; Q.Free; R.Free end;
end.
