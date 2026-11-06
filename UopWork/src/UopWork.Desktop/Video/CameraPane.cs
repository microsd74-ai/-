using System.Diagnostics;
using System.Security.Cryptography;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;
using LibVLCSharp.Shared;
using MediaPlayer=LibVLCSharp.Shared.MediaPlayer;
using LibVLCSharp.WPF;
using UopWork.Core;
namespace UopWork.Desktop.Video;

public sealed class CameraPane : UserControl, IDisposable
{
    private readonly VideoView video=new(){Visibility=Visibility.Collapsed};
    private readonly TextBlock status=new(){Text="Камера не настроена",VerticalAlignment=VerticalAlignment.Center,HorizontalAlignment=HorizontalAlignment.Center,Margin=new Thickness(12),TextAlignment=TextAlignment.Center};
    private readonly TextBlock heading=new(){FontWeight=FontWeights.SemiBold,VerticalAlignment=VerticalAlignment.Center};
    private readonly Button expand=new(){Content="Развернуть",Padding=new Thickness(8,4,8,4),MinHeight=28,FontSize=11};
    private readonly SemaphoreSlim gate=new(1);
    private readonly DispatcherTimer timer;
    private MediaPlayer? player;
    private Media? media;
    private RecorderSettings? desired;
    private int camera=1,generation,lastFrames;
    private long frameAt;
    private DateTimeOffset retryAt;
    private bool disposed,opening,demo;
    public string StatusText=>status.Text;
    public event Action? ExpandRequested;
    public bool CanExpand {set=>expand.Visibility=value?Visibility.Visible:Visibility.Collapsed;}
    public CameraPane()
    {
        var panel=new DockPanel();
        var bar=new DockPanel{Margin=new Thickness(0,0,0,6)};
        expand.Click+=(_,_)=>ExpandRequested?.Invoke();DockPanel.SetDock(expand,Dock.Right);bar.Children.Add(expand);
        var reconnect=new Button{Content="↻",ToolTip="Переподключить камеру",Padding=new Thickness(8,4,8,4),MinHeight=28,FontSize=12};
        reconnect.Click+=(_,_)=>RequestOpen();DockPanel.SetDock(reconnect,Dock.Right);bar.Children.Add(reconnect);bar.Children.Add(heading);
        DockPanel.SetDock(bar,Dock.Top);panel.Children.Add(bar);
        status.FontSize=11;status.SetResourceReference(TextBlock.ForegroundProperty,"MutedBrush");DockPanel.SetDock(status,Dock.Bottom);panel.Children.Add(status);
        var picture=new Grid{Background=Brushes.Black,ClipToBounds=true};picture.Children.Add(video);
        panel.Children.Add(picture);Content=panel;MinWidth=0;
        timer=new DispatcherTimer(TimeSpan.FromSeconds(1),DispatcherPriority.Background,(_,_)=>CheckFrames(),Dispatcher);
        timer.Stop();Loaded+=(_,_)=>{if(!disposed){timer.Start();RequestOpen();}};
        Unloaded+=(_,_)=>Dispose();
    }
    public void Configure(RecorderSettings? recorder,int number,bool demonstration=false)
    {
        if(disposed)return;
        heading.Text=$"Камера {number} · зона печати";
        if(Equals(desired,recorder)&&camera==number&&demo==demonstration)return;
        desired=recorder;camera=number;demo=demonstration;
        heading.Text=$"Камера {camera} · зона печати";
        RequestOpen();
    }
    private void RequestOpen()
    {
        if(disposed)return;
        generation++;video.MediaPlayer=null;video.Visibility=Visibility.Collapsed;
        status.Text=demo?"Демонстрация · видео не подключается":desired?.Enabled==true?"Подключение к камере…":"Камера не настроена";
        if(IsLoaded)_=OpenAsync(generation);
    }
    private async Task OpenAsync(int request)
    {
        await gate.WaitAsync();
        try
        {
            if(request!=generation)return;
            opening=true;await StopCurrentAsync();
            if(disposed||request!=generation||demo||desired?.Enabled!=true)return;
            var config=desired;
            Uri address;
            try{address=config.BuildUri(camera,CameraSecrets.Unprotect(config.ProtectedPassword));}
            catch(Exception e) when(e is ArgumentException or CryptographicException or FormatException or InvalidOperationException)
            {status.Text="Не удалось открыть настройки камеры. Повторно сохраните пароль в управлении.";retryAt=DateTimeOffset.UtcNow.AddSeconds(15);return;}
            var engine=await CameraRuntime.GetAsync();
            if(disposed||request!=generation)return;
            var candidate=await Task.Run(()=>
            {
                var source=new Media(engine,address);source.AddOption(":rtsp-tcp");source.AddOption(":network-caching=500");source.AddOption(":ipv4-timeout=5000");
                try{return (Media:source,Player:new MediaPlayer(engine){Media=source,EnableHardwareDecoding=false,Mute=true});}
                catch{source.Dispose();throw;}
            });
            if(disposed||request!=generation){await ReleaseAsync(candidate.Player,candidate.Media);return;}
            player=candidate.Player;media=candidate.Media;lastFrames=0;frameAt=Stopwatch.GetTimestamp();
            video.MediaPlayer=player;video.Visibility=Visibility.Visible;
            if(!await Task.Run(candidate.Player.Play))
            {
                if(request==generation){await StopCurrentAsync();status.Text="Нет видео · проверьте адрес, пароль и каналы";retryAt=DateTimeOffset.UtcNow.AddSeconds(10);}
            }
        }
        catch(Exception)
        {
            // VLC/RTSP exception messages can contain the complete credential URI.
            // Do not expose them in UI, history or log files.
            if(request==generation&&!disposed){await StopCurrentAsync();status.Text="Не удалось запустить видео · проверьте настройки регистратора";retryAt=DateTimeOffset.UtcNow.AddSeconds(10);}
        }
        finally{opening=false;gate.Release();}
    }
    private async Task StopCurrentAsync()
    {
        var old=player;var source=media;player=null;media=null;
        if(!disposed){video.MediaPlayer=null;video.Visibility=Visibility.Collapsed;}
        if(old is not null)await ReleaseAsync(old,source);
        else source?.Dispose();
    }
    private static Task ReleaseAsync(MediaPlayer old,Media? source)=>Task.Run(()=>
    {try{old.Stop();}finally{old.Dispose();source?.Dispose();}});
    private void CheckFrames()
    {
        if(disposed||opening||demo||desired?.Enabled!=true)return;
        if(player is null){if(DateTimeOffset.UtcNow>=retryAt)RequestOpen();return;}
        try
        {
            var frames=media?.Statistics.DecodedVideo??0;
            if(frames>lastFrames){lastFrames=frames;frameAt=Stopwatch.GetTimestamp();status.Text="Видео поступает";}
            if(Stopwatch.GetElapsedTime(frameAt)>TimeSpan.FromSeconds(12))
            {status.Text="Видео недоступно · повторное подключение";RequestOpen();}
        }
        catch(ObjectDisposedException){}
    }
    public void Dispose()
    {
        if(disposed)return;disposed=true;generation++;timer.Stop();
        video.MediaPlayer=null;video.Dispose();
        _=CloseAsync();
    }
    private async Task CloseAsync()
    {await gate.WaitAsync();try{await StopCurrentAsync();}catch(Exception){}finally{gate.Release();}}
}
