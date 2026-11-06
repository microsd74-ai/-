using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using UopWork.Core;
using UopWork.Desktop;
using UopWork.Desktop.Views;
internal static class Program
{
    private sealed class BindingLog : TraceListener
    {
        public List<string> Errors {get;}=[];
        public override void Write(string? message){if(!string.IsNullOrWhiteSpace(message))Errors.Add(message);}
        public override void WriteLine(string? message)=>Write(message);
    }
    [STAThread]
    private static int Main(string[] args)
    {
        int code=Run(args);
        // Test process only: do not leave a WPF dispatcher waiting after checks.
        Environment.Exit(code);
        return code;
    }
    private static int Run(string[] args)
    {
        var root=Path.Combine(Path.GetTempPath(),"uop-ui-checks-"+Guid.NewGuid());Directory.CreateDirectory(root);
        try
        {
            var screenshots=Path.GetFullPath(args.FirstOrDefault()??"artifacts/screenshots");Directory.CreateDirectory(screenshots);
            var log=new BindingLog();PresentationTraceSources.DataBindingSource.Switch.Level=SourceLevels.Error;
            PresentationTraceSources.DataBindingSource.Listeners.Add(log);
            var app=new App(manualStartup:true);app.InitializeComponent();
            var window=new MainWindow(true);app.MainWindow=window;window.Show();Pump();
            var dashboard=(Dashboard)window.DataContext;
            Check(dashboard.Demo && dashboard.Printers.Count==7,"explicit demo data");
            foreach(var theme in new[]{"Light","Dark","Terminal"})
            {
                ((ComboBox)window.FindName("ThemePicker")).SelectedIndex=theme=="Light"?0:theme=="Dark"?1:2;window.Width=1920;window.Height=1080;Pump();window.UpdateLayout();
                var list=(ListBox)window.FindName("PrintersList");Check(list.Items.Count==7,"printer list");
                dashboard.Selected=dashboard.Printers[1];Pump();Check(dashboard.Selected.HasAlarm,"selected alarm");
                var alarmPrinter=dashboard.Selected;var original=alarmPrinter.Data!;
                alarmPrinter.Acknowledge();Check(alarmPrinter.AckText=="Подтверждено","acknowledgement");
                alarmPrinter.Apply(original with{Alarm="",AlarmRead=null});Check(alarmPrinter.HasAlarm,"unknown read must not clear error");
                alarmPrinter.Apply(original with{Alarm="",AlarmRead=true});Check(!alarmPrinter.HasAlarm,"confirmed clear");
                alarmPrinter.Apply(original);
                dashboard.Selected=dashboard.Printers[0];Pump();
                CheckLayout(window);
                Capture(window,Path.Combine(screenshots,theme+"-1920.png"));
                window.Width=1366;window.Height=768;Pump();window.UpdateLayout();
                CheckLayout(window);
                Capture(window,Path.Combine(screenshots,theme+"-1366.png"));
            }
            Check(dashboard.ModeLabel.Contains("v0.3.0"),"visible build version");
            var testClock=new UiClock();var stopped=new PrinterItem(new(Guid.NewGuid(),"Контроль слоя","127.0.0.8"),testClock);
            var sample=dashboard.Printers[0].Data! with{Printed=100,Total=200,FinishKind="ESTIMATE",Alarm="1/1:E4.2: Test",AlarmRead=true};
            stopped.Apply(sample);
            for(int i=0;i<60;i++){testClock.Advance();stopped.Apply(sample);}
            Check(stopped.StopAlarms.NeedsAttention&&stopped.Alarms.NeedsAttention,"stop and printer alarms independent");
            var stopId=stopped.StopAlarms.Active.Single().Id;
            stopped.AlarmCards.Single(c=>c.IsLayerStop).Acknowledge();
            Check(!stopped.StopAlarms.NeedsAttention&&stopped.Alarms.NeedsAttention,"stop acknowledgement silenced printer alarm");
            stopped.Apply(sample with{Alarm=""});Check(stopped.StopAlarms.Active.Count==1,"empty FHZL alarm cleared layer stop");
            stopped.Apply(sample with{Printed=101,Alarm=""});Check(stopped.StopAlarms.Active.Count==0,"advance did not clear UI stop");
            for(int i=0;i<60;i++){testClock.Advance();stopped.Apply(sample with{Printed=101,Alarm=""});}
            Check(stopped.StopAlarms.NeedsAttention&&stopped.StopAlarms.Active.Single().Id!=stopId,"second stop did not rearm UI");
            dashboard.Printers.Add(stopped);dashboard.Selected=stopped;dashboard.Tick();Pump();
            Capture(window,Path.Combine(screenshots,"layer-stopped.png"));
            var settings=new SettingsStore(Path.Combine(root,"settings.json"));
            settings.Save(new("Dark",[new(Guid.NewGuid(),"Тестовый принтер","127.0.0.1")]));
            var password=new PasswordStore(Path.Combine(root,"admin.json"));
            var login=new PasswordWindow(password,false);login.Show();Pump();Check(login.WindowStyle==WindowStyle.None,"borderless password window");Capture(login,Path.Combine(screenshots,"password-setup.png"));login.Close();
            var admin=new ManagementWindow(settings,password,()=>{},dashboard.Printers);admin.Show();Pump();Check(admin.WindowStyle==WindowStyle.None,"borderless management window");Capture(admin,Path.Combine(screenshots,"management.png"));admin.Close();
            var audioWindow=new AudioSettingsWindow(settings,()=>{});audioWindow.Show();Pump();
            Check(audioWindow.WindowStyle==WindowStyle.None,"borderless audio window");Capture(audioWindow,Path.Combine(screenshots,"audio-settings.png"));audioWindow.Close();
            var history=new System.Collections.ObjectModel.ObservableCollection<AlarmHistoryEntry>{new(Guid.NewGuid(),"Принтер Ж",new(DateTimeOffset.Now,"Появление",Guid.NewGuid(),"Тестовая ошибка"))};
            var historyWindow=new AlarmHistoryWindow(history);historyWindow.Show();Pump();Capture(historyWindow,Path.Combine(screenshots,"alarm-history.png"));historyWindow.Close();
            using(var audio=new AlarmAudio()){audio.Update([],"");Check(audio.Status.Length>0,"audio fallback initialization");audio.Update([],"Z:\\missing-uop-recording.wav");Check(audio.Status.Contains("Запись недоступна"),"missing recording fallback");}
            var cameraPassword="Тест камеры:@/#%";
            var protectedPassword=CameraSecrets.Protect(cameraPassword);
            Check(!protectedPassword.Contains(cameraPassword)&&CameraSecrets.Unprotect(protectedPassword)==cameraPassword,"camera DPAPI roundtrip");
            var cameraSettings=new CameraSettingsWindow(settings,settings.Load().Printers.Single(),()=>{});cameraSettings.Show();Pump();
            Check(cameraSettings.WindowStyle==WindowStyle.None,"borderless camera settings");Capture(cameraSettings,Path.Combine(screenshots,"camera-settings.png"));cameraSettings.Close();
            var cameraPreview=new CameraPreviewWindow("Тест камер",null,true);cameraPreview.Show();Pump();Capture(cameraPreview,Path.Combine(screenshots,"camera-preview.png"));cameraPreview.Close();
            var vlc=UopWork.Desktop.Video.CameraRuntime.GetAsync().GetAwaiter().GetResult();
            using(var clip=new LibVLCSharp.Shared.Media(vlc,new Uri(Path.Combine(AppContext.BaseDirectory,"camera-test.mp4"))))
            using(var decoder=new LibVLCSharp.Shared.MediaPlayer(vlc))
            {
                clip.AddOption(":vout=dummy");clip.AddOption(":no-audio");
                Check(decoder.Play(clip),"native video decoder start");
                var deadline=DateTime.UtcNow.AddSeconds(12);
                while(clip.Statistics.DecodedVideo==0&&DateTime.UtcNow<deadline){Pump();Thread.Sleep(50);}
                Check(clip.Statistics.DecodedVideo>0,"native H264 frames decoded");decoder.Stop();
            }
            Console.WriteLine("PASS cameras: native VLC loading, local H264 decoding, protected credentials, settings/preview windows");
            Check(log.Errors.Count==0,"WPF binding errors: "+string.Join("\n",log.Errors));
            window.Hide();Console.WriteLine("PASS Windows WPF: resources, three themes, printer selection, alarm binding, admin/password windows, 1920/1366 screenshots");
            return 0;
        }
        catch(Exception ex){Console.Error.WriteLine(ex);Console.Error.WriteLine("::error title=Windows WPF check::"+ex.ToString().Replace("%","%25").Replace("\r","%0D").Replace("\n","%0A"));return 1;}
        finally{Directory.Delete(root,true);}
    }
    private static void CheckLayout(Window window)
    {
        var expected=(SolidColorBrush)window.FindResource("BackgroundBrush");
        Check(window.Background is SolidColorBrush actual && actual.Color==expected.Color,"window theme background");
        Check(window.FontSize==14,"window typography");
        foreach(var name in new[]{"RestartButton","ShutdownButton","UploadButton"})
        {
            var button=(Button)window.FindName(name);
            var label=new FormattedText((string)button.Content,System.Globalization.CultureInfo.CurrentUICulture,FlowDirection.LeftToRight,
                new Typeface(button.FontFamily,button.FontStyle,button.FontWeight,button.FontStretch),button.FontSize,button.Foreground,VisualTreeHelper.GetDpi(button).PixelsPerDip);
            Check(button.ActualHeight>=label.Height+button.Padding.Top+button.Padding.Bottom+2,"unclipped footer label: "+name);
            Check(button.ActualWidth>=label.Width+button.Padding.Left+button.Padding.Right+2,"footer label width: "+name);
        }
    }
    private static void Check(bool ok,string text){if(!ok)throw new Exception(text);}
    private static void Pump()
    {
        var frame=new DispatcherFrame();Dispatcher.CurrentDispatcher.BeginInvoke(DispatcherPriority.ApplicationIdle,new Action(()=>frame.Continue=false));Dispatcher.PushFrame(frame);
    }
    private static void Capture(Window window,string file)
    {
        window.UpdateLayout();
        var bitmap=new RenderTargetBitmap((int)Math.Ceiling(window.ActualWidth),(int)Math.Ceiling(window.ActualHeight),96,96,PixelFormats.Pbgra32);
        bitmap.Render(window);var encoder=new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(bitmap));using var output=File.Create(file);encoder.Save(output);
    }
}

sealed class UiClock : TimeProvider
{
    private long seconds;
    public override long TimestampFrequency=>1;
    public override long GetTimestamp()=>seconds;
    public void Advance()=>seconds++;
}
