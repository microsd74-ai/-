using System.IO;
using System.Media;
using System.Runtime.InteropServices;
namespace UopWork.Desktop;

// All methods run on the WPF STA thread. No network or external process is used.
public sealed class AlarmAudio : IDisposable
{
    private SoundPlayer? player;
    private MemoryStream? tone;
    private object? speaker;
    private string configuredFile="", signature="";
    private DateTimeOffset nextPlay;
    private bool initialized;
    public string Status {get;private set;}="Звук готовится";
    private bool preferStop;
    public void Update(IEnumerable<Guid> pending, string file, IEnumerable<Guid>? stopped=null, string stopFile="")
    {
        var errors=pending.Order().ToArray();var stops=(stopped??[]).Order().ToArray();
        var current="E:"+string.Join(";",errors)+"|S:"+string.Join(";",stops);
        if(!initialized || (errors.Length+stops.Length==0&&file!=configuredFile))Configure(file);
        if(current!=signature){Stop();signature=current;nextPlay=DateTimeOffset.MinValue;preferStop=stops.Length>0;}
        if(errors.Length+stops.Length==0 || DateTimeOffset.UtcNow<nextPlay)return;
        bool isStop=stops.Length>0&&(errors.Length==0||preferStop);
        var chosen=isStop?stopFile:file;
        if(chosen!=configuredFile)Configure(chosen);
        Play(isStop);preferStop=!isStop;nextPlay=DateTimeOffset.UtcNow.AddSeconds(10);
    }
    public void Test(string file,bool isStop=false)
    {if(!initialized || file!=configuredFile)Configure(file);Play(isStop);}
    private void Configure(string file)
    {
        Stop();player?.Dispose();tone?.Dispose();player=null;tone=null;
        if(speaker is not null){Marshal.FinalReleaseComObject(speaker);speaker=null;}
        initialized=true;configuredFile=file;nextPlay=DateTimeOffset.MinValue;
        string warning="";
        if(!string.IsNullOrWhiteSpace(file))
        {
            try
            {
                if(new FileInfo(file).Length>20*1024*1024)throw new IOException("Запись больше 20 МБ");
                using var stream=File.OpenRead(file);using var reader=new BinaryReader(stream);
                if(new string(reader.ReadChars(4))!="RIFF")throw new IOException("Ожидается WAV RIFF");
                stream.Position=8;if(new string(reader.ReadChars(4))!="WAVE")throw new IOException("Ожидается WAV WAVE");
                player=new SoundPlayer(file);player.Load();Status="Звук: выбранная запись WAV";return;
            }
            catch(Exception e) when(e is IOException or ArgumentException or InvalidOperationException or UnauthorizedAccessException or TimeoutException or System.ComponentModel.Win32Exception)
            {player?.Dispose();player=null;warning="Запись недоступна; ";}
        }
        try
        {
            var type=Type.GetTypeFromProgID("SAPI.SpVoice");
            if(type is not null)
            {
                speaker=Activator.CreateInstance(type);
                dynamic voice=speaker!;
                object tokens=voice.GetVoices("Language=419;Gender=Female", "");
                try
                {
                    dynamic list=tokens;
                    if(list.Count>0)
                    {
                        object token=list.Item(0);
                        try{voice.Voice=token;voice.Rate=-1;voice.Volume=90;}
                        finally{Marshal.FinalReleaseComObject(token);}
                        Status=warning+"Звук: русский женский голос Windows";return;
                    }
                }
                finally{Marshal.FinalReleaseComObject(tokens);}
                Marshal.FinalReleaseComObject(speaker!);speaker=null;
            }
        }
        catch(Exception e) when(e is COMException or InvalidOperationException or Microsoft.CSharp.RuntimeBinder.RuntimeBinderException)
        {if(speaker is not null){Marshal.FinalReleaseComObject(speaker);speaker=null;}}
        tone=CreateTone();player=new SoundPlayer(tone);player.Load();
        Status=warning+"Звук: сигнал · русская женская озвучка не установлена";
    }
    private void Play(bool isStop)
    {
        try
        {
            if(speaker is not null)((dynamic)speaker).Speak(isStop?"Внимание! Печать остановилась!":"Внимание! Ошибка в работе принтера!",3);
            else player?.Play();
        }
        catch(Exception e) when(e is COMException or InvalidOperationException or IOException or TimeoutException or System.ComponentModel.Win32Exception)
        {Status="Не удалось воспроизвести звук. Проверьте аудиоустройство.";}
    }
    public void Stop()
    {
        player?.Stop();
        if(speaker is not null)
        {try{((dynamic)speaker).Speak("",3);}catch(COMException){}}
    }
    private static MemoryStream CreateTone()
    {
        const int rate=22050,samples=rate;
        var stream=new MemoryStream();
        using(var writer=new BinaryWriter(stream,System.Text.Encoding.ASCII,true))
        {
            writer.Write("RIFF"u8);writer.Write(36+samples*2);writer.Write("WAVEfmt "u8);
            writer.Write(16);writer.Write((short)1);writer.Write((short)1);writer.Write(rate);writer.Write(rate*2);
            writer.Write((short)2);writer.Write((short)16);writer.Write("data"u8);writer.Write(samples*2);
            for(int i=0;i<samples;i++)
            {
                double t=(double)i/rate,phase=t%0.33,frequency=t<0.33?660:t<0.66?784:880;
                double envelope=phase<0.24?Math.Sin(Math.PI*phase/0.24):0;
                writer.Write((short)(Math.Sin(2*Math.PI*frequency*t)*envelope*8000));
            }
        }
        stream.Position=0;return stream;
    }
    public void Dispose(){Stop();player?.Dispose();tone?.Dispose();if(speaker is not null){Marshal.FinalReleaseComObject(speaker);speaker=null;}}
}
