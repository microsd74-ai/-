using System.Windows;
namespace UopWork.Desktop;
public partial class App : Application
{
    private readonly bool manualStartup;
    public App() { }
    internal App(bool manualStartup)=>this.manualStartup=manualStartup;
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        if(manualStartup)return;
        var demo=e.Args.Contains("--demo");
        var window=new MainWindow(demo);MainWindow=window;window.Show();
    }
    public static void SetTheme(string name)
    {
        if(name is not ("Light" or "Dark" or "Terminal"))throw new ArgumentException("Неизвестная тема");
        Current.Resources.MergedDictionaries[0]=new ResourceDictionary{Source=new Uri($"pack://application:,,,/UopWork;component/Themes/{name}.xaml",UriKind.Absolute)};
    }
}
