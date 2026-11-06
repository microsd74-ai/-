using System.Net;
using System.Net.Sockets;
using System.Text;
using UopWork.Core;

static void Check(bool ok,string message){if(!ok)throw new Exception(message);}
static void Reject(Action action,string message){try{action();}catch(Exception e) when(e is ArgumentException or IOException or InvalidOperationException or FormatException){return;}throw new Exception(message);}
var root=Path.Combine(Path.GetTempPath(),"uop-checks-"+Guid.NewGuid());Directory.CreateDirectory(root);
try
{
    var store=new SettingsStore(Path.Combine(root,"settings.json"));
    var config=new PrinterConfig(Guid.NewGuid(),"Принтер PMMA","192.168.1.101");
    store.Save(new("Terminal",[config]));var read=store.Load();
    Check(read.Theme=="Terminal" && read.Printers[0].Name==config.Name,"settings roundtrip");
    var before=File.ReadAllText(store.Path);
    Reject(()=>store.Save(new("Dark",[config,config with{Id=Guid.NewGuid()}])),"duplicate accepted");
    Reject(()=>store.Save(new("Dark",[config with{Host="300.0.0.1"}])),"invalid IP accepted");
    Check(File.ReadAllText(store.Path)==before,"invalid save changed file");
    var legacy=Path.Combine(root,"legacy.json");File.WriteAllText(legacy,"{\"printers\":[{\"name\":\"FHZL PMMA\",\"host\":\"192.168.1.101\",\"port\":5055}]}");
    Check(SettingsStore.ImportLazarus(legacy).Single().Name=="FHZL PMMA","legacy import failed");
    Console.WriteLine("PASS settings: UTF-8, themes, validation, duplicate rejection, file preservation, Lazarus import");
    var password=new PasswordStore(Path.Combine(root,"admin.json"));
    Check(!password.Verify("anything"),"unconfigured bypass");Reject(()=>password.Initialize("short"),"short password accepted");
    password.Initialize("Тестовый-пароль-123");Check(password.Verify("Тестовый-пароль-123")&&!password.Verify("wrong"),"password verification");
    Check(!File.ReadAllText(Path.Combine(root,"admin.json")).Contains("Тестовый"),"plaintext password stored");
    Reject(()=>password.Initialize("replacement-password"),"reinitialize bypass");
    Reject(()=>password.Change("wrong","new-password-123"),"bad old password accepted");
    password.Change("Тестовый-пароль-123","new-password-123");Check(password.Verify("new-password-123")&&!password.Verify("Тестовый-пароль-123"),"password change");
    File.WriteAllText(Path.Combine(root,"admin.json"),"{\"Version\":1,\"Algorithm\":\"PBKDF2-HMAC-SHA256\",\"Iterations\":1}");
    Reject(()=>password.Verify("anything"),"corrupt password bypass");Console.WriteLine("PASS password: PBKDF2, Unicode, wrong password, first-run protection, change, corruption");
    var now=DateTimeOffset.Now;
    byte[] Message(string extra)=>Encoding.UTF8.GetBytes("{\"type\":\"telemetry\",\"version\":1,\"name\":\"Принтер Ж\",\"state\":\"ok\",\"printed\":\"420\",\"total\":\"2113\",\"extra\":"+extra+"}");
    var unknown=Telemetry.Parse(Message("{\"alarm\":\"\"}"),now);
    Check(!unknown.ErrorsKnownEmpty,"legacy empty error incorrectly considered healthy");
    var clear=Telemetry.Parse(Message("{\"alarm\":\"\",\"alarmRead\":true}"),now);Check(clear.ErrorsKnownEmpty,"confirmed empty list lost");
    var error=Telemetry.Parse(Message("{\"alarm\":\"E4.2: Alarm\"}"),now);Check(error.Alarm!=""&&error.Printed==420&&error.Progress>0.19,"telemetry parse");
    Reject(()=>Telemetry.Parse(Encoding.UTF8.GetBytes("{\"type\":\"telemetry\",\"version\":\"bad\"}"),now),"bad version accepted");
    Console.WriteLine("PASS telemetry: actual legacy schema, Unicode, confirmed/unknown error states, progress, malformed version");
    var listener=new TcpListener(IPAddress.Loopback,0);listener.Start();
    int port=((IPEndPoint)listener.LocalEndpoint).Port;
    using var stop=new CancellationTokenSource(TimeSpan.FromSeconds(12));
    var delivered=new TaskCompletionSource<Telemetry>(TaskCreationOptions.RunContinuationsAsynchronously);
    var observed=AgentConnection.ObserveAsync(config with{Host="127.0.0.1",Port=port},t=>delivered.TrySetResult(t),_=>{},stop.Token);
    using(var client=await listener.AcceptTcpClientAsync(stop.Token))
    {
        var payload=Message("{\"alarm\":\"\"}");var marker=Encoding.UTF8.GetBytes("Ж");int split=payload.AsSpan().IndexOf(marker)+1;
        Check(split>0,"fixture marker missing");
        await client.GetStream().WriteAsync(payload.AsMemory(0,split),stop.Token);
        await Task.Delay(30,stop.Token);
        await client.GetStream().WriteAsync(payload.AsMemory(split),stop.Token);
        await client.GetStream().WriteAsync(new byte[]{10},stop.Token);
        var actual=await delivered.Task.WaitAsync(stop.Token);Check(actual.Name=="Принтер Ж","fragmented UTF8 damaged");
    }
    stop.Cancel();await observed;listener.Stop();
    Console.WriteLine("PASS network: real loopback TCP stream, fragmented UTF-8, cancellation");
}
finally{Directory.Delete(root,true);}
