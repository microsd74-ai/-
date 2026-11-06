using System.Collections.ObjectModel;
using System.IO;
using System.Windows;
using Microsoft.Win32;
using UopWork.Core;
namespace UopWork.Desktop.Views;
public partial class ManagementWindow : Window
{
    private readonly SettingsStore settings;
    private readonly PasswordStore password;
    private readonly Action changed;
    private readonly IEnumerable<PrinterItem> states;
    private ObservableCollection<PrinterConfig> rows=[];
    public bool ExitRequested {get;private set;}
    public ManagementWindow(SettingsStore settings,PasswordStore password,Action changed,IEnumerable<PrinterItem> states)
    {
        this.settings=settings;this.password=password;this.changed=changed;this.states=states;
        InitializeComponent();Reload();
    }
    private void Reload(){rows=new(settings.Load().Printers);PrinterTable.ItemsSource=rows;}
    private PrinterConfig Read(Guid? id=null)
    {
        if(!int.TryParse(Port.Text,out var port))throw new ArgumentException("Укажите числовой порт.");
        return new PrinterConfig(id??Guid.NewGuid(),PrinterName.Text,Host.Text,port).Validate();
    }
    private void Try(Action action)
    {
        try{action();Error.Text="";}
        catch(Exception ex) when(ex is IOException or ArgumentException or System.Text.Json.JsonException)
        {Error.Text=ex.Message;}
    }
    private void Commit(List<PrinterConfig> printers)
    {settings.Save(settings.Load() with{Printers=printers});Reload();changed();}
    private void SelectionChanged(object sender,System.Windows.Controls.SelectionChangedEventArgs e)
    {
        if(PrinterTable.SelectedItem is not PrinterConfig p)return;
        PrinterName.Text=p.Name;Host.Text=p.Host;Port.Text=p.Port.ToString();
    }
    private void Add(object sender,RoutedEventArgs e)=>Try(()=>Commit([..rows,Read()]));
    private void Save(object sender,RoutedEventArgs e)=>Try(()=>
    {
        if(PrinterTable.SelectedItem is not PrinterConfig p)throw new ArgumentException("Выберите принтер.");
        var updated=Read(p.Id);Commit(rows.Select(x=>x.Id==p.Id?updated:x).ToList());
    });
    private void Remove(object sender,RoutedEventArgs e)=>Try(()=>
    {
        if(PrinterTable.SelectedItem is not PrinterConfig p)return;
        if(MessageBox.Show(this,$"Удалить «{p.Name}» из наблюдения?","Удалить принтер",MessageBoxButton.YesNo)!=MessageBoxResult.Yes)return;
        Commit(rows.Where(x=>x.Id!=p.Id).ToList());
    });
    private void Import(object sender,RoutedEventArgs e)=>Try(()=>
    {
        var dialog=new OpenFileDialog{Filter="Список принтеров (*.json)|*.json",Title="Выберите Monitor.targets.json из Lazarus-версии"};
        if(dialog.ShowDialog(this)!=true)return;
        var imported=SettingsStore.ImportLazarus(dialog.FileName);
        if(MessageBox.Show(this,$"Заменить текущий список на {imported.Count} принтеров из файла?","Импорт",MessageBoxButton.YesNo)!=MessageBoxResult.Yes)return;
        Commit(imported.ToList());
    });
    private void ChangePassword(object sender,RoutedEventArgs e)=>new PasswordWindow(password,true){Owner=this}.ShowDialog();
    private void AudioSettings(object sender,RoutedEventArgs e)=>new AudioSettingsWindow(settings,changed){Owner=this}.ShowDialog();
    private void Events(object sender,RoutedEventArgs e)
    {
        var body=new System.Windows.Controls.TextBox{IsReadOnly=true,TextWrapping=TextWrapping.Wrap,VerticalScrollBarVisibility=System.Windows.Controls.ScrollBarVisibility.Auto,Text=string.Join("\n\n",states.Select(p=>p.Name+"\n"+string.Join("\n",p.Events)))};
        new Window{Owner=this,Title="Журнал событий подключений",Width=780,Height=560,Content=body,WindowStartupLocation=WindowStartupLocation.CenterOwner}.ShowDialog();
    }
    private void Exit(object sender,RoutedEventArgs e)
    {if(MessageBox.Show(this,"Завершить работу UOP WORK?","Выход",MessageBoxButton.YesNo)==MessageBoxResult.Yes){ExitRequested=true;Close();}}
}
