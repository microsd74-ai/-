using System.ComponentModel;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
using UopWork.Core;
using UopWork.Desktop.Views;
namespace UopWork.Desktop;
public partial class MainWindow : Window
{
    private readonly Dashboard dashboard;
    private readonly SettingsStore settings;
    private readonly PasswordStore password;
    private readonly Dictionary<Guid,(PrinterItem Item,CancellationTokenSource Stop,Task Task)> connections=[];
    private readonly DispatcherTimer timer;
    private string theme="Dark";
    private bool ready,allowExit,managementOpen;
    public MainWindow(bool demo)
    {
        var root=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"UopWork");
        if(demo)root=Path.Combine(root,"Demo");
        settings=new(Path.Combine(root,"settings.json"));password=new(Path.Combine(root,"admin.json"));dashboard=new(demo);
        InitializeComponent();DataContext=dashboard;
        try
        {
            var saved=settings.Load();theme=saved.Theme;App.SetTheme(theme);
            ThemePicker.SelectedIndex=theme=="Light"?0:theme=="Terminal"?2:1;
            if(demo)
            {
                if(File.Exists(settings.Path))dashboard.LoadDemo(saved.Printers);
                else{dashboard.LoadDemo();settings.Save(new(theme,dashboard.Printers.Select(p=>p.Config).ToList()));}
            }
            else Configure(saved);
        }
        catch(Exception ex) when(ex is IOException or ArgumentException or System.Text.Json.JsonException)
        { dashboard.Message="Ошибка настроек: "+ex.Message; }
        ready=true;
        timer=new DispatcherTimer(TimeSpan.FromSeconds(1),DispatcherPriority.Background,(_,_)=>
        {
            if(dashboard.Demo)foreach(var p in dashboard.Printers.Where(p=>p.Connection!="Нет связи"))if(p.Data is {} data)p.Apply(data with{ReceivedAt=DateTimeOffset.Now});
            dashboard.Tick();
        },Dispatcher);timer.Start();
        Loaded+=(_,_)=>{Left=0;Top=0;Width=SystemParameters.PrimaryScreenWidth;Height=SystemParameters.PrimaryScreenHeight;};
        Closed+=(_,_)=>{timer.Stop();foreach(var c in connections.Values)c.Stop.Cancel();};
    }
    private void Configure(AppSettings saved)
    {
        var selectedId=dashboard.Selected?.Config.Id;
        foreach(var id in connections.Keys.Where(id=>saved.Printers.All(p=>p.Id!=id) || saved.Printers.First(p=>p.Id==id).Endpoint!=connections[id].Item.Config.Endpoint).ToArray())
        {connections[id].Stop.Cancel();connections.Remove(id);}
        var ordered=new List<PrinterItem>();
        foreach(var config in saved.Printers)
        {
            if(connections.TryGetValue(config.Id,out var existing)){existing.Item.Config=config;existing.Item.Refresh();ordered.Add(existing.Item);continue;}
            var item=new PrinterItem(config);var stop=new CancellationTokenSource();
            var task=AgentConnection.ObserveAsync(config,
                data=>Dispatcher.BeginInvoke(new Action(()=>{if(connections.TryGetValue(config.Id,out var current)&&ReferenceEquals(current.Item,item))item.Apply(data);})),
                status=>Dispatcher.BeginInvoke(new Action(()=>{item.Connection=status;item.AddEvent(status);item.Refresh();})),stop.Token);
            connections.Add(config.Id,(item,stop,task));ordered.Add(item);
        }
        dashboard.Printers.Clear();foreach(var item in ordered)dashboard.Printers.Add(item);
        dashboard.Selected=ordered.FirstOrDefault(p=>p.Config.Id==selectedId)??ordered.FirstOrDefault();
        dashboard.Message=ordered.Count==0?"Добавьте принтеры через «Управление». Можно импортировать список Lazarus.":"Подключение к агентам 0.3+ по локальной сети. Отсутствующие данные не подставляются.";
        dashboard.Refresh();
    }
    private void ThemeChanged(object sender,SelectionChangedEventArgs e)
    {
        if(!ready || ThemePicker.SelectedItem is not ComboBoxItem choice || choice.Tag is not string name)return;
        try{App.SetTheme(name);theme=name;settings.Save(settings.Load() with{Theme=name});}
        catch(Exception ex) when(ex is IOException or ArgumentException){MessageBox.Show(this,ex.Message,"Оформление");}
    }
    private void ManageClick(object sender,RoutedEventArgs e)=>OpenManagement();
    private void OpenManagement()
    {
        if(managementOpen)return;managementOpen=true;
        try
        {
            var auth=new PasswordWindow(password,false){Owner=this};if(auth.ShowDialog()!=true)return;
            var admin=new ManagementWindow(settings,password,()=>{if(!dashboard.Demo)Configure(settings.Load());else{dashboard.Printers.Clear();dashboard.LoadDemo(settings.Load().Printers);}},dashboard.Printers){Owner=this};
            admin.ShowDialog();if(admin.ExitRequested){allowExit=true;Close();}
        }
        catch(Exception ex) when(ex is IOException or ArgumentException or System.Text.Json.JsonException)
        {MessageBox.Show(this,ex.Message,"Управление");}
        finally{managementOpen=false;}
    }
    private void AcknowledgeClick(object sender,RoutedEventArgs e){if(sender is Button{Tag:PrinterItem item})item.Acknowledge();}
    private void WindowClosing(object? sender,CancelEventArgs e)
    {
        if(allowExit)return;e.Cancel=true;
        Dispatcher.BeginInvoke(new Action(OpenManagement));
    }
}
