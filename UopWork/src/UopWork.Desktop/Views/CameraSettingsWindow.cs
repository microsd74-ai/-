using System.IO;
using System.Security.Cryptography;
using System.Windows;
using System.Windows.Controls;
using UopWork.Core;
namespace UopWork.Desktop.Views;
public sealed class CameraSettingsWindow : Window
{
    public CameraSettingsWindow(SettingsStore store,PrinterConfig printer,Action changed)
    {
        Title="Камеры · "+printer.Name;Width=720;SizeToContent=SizeToContent.Height;WindowStyle=WindowStyle.None;
        ResizeMode=ResizeMode.NoResize;WindowStartupLocation=WindowStartupLocation.CenterOwner;ShowInTaskbar=false;
        SetResourceReference(StyleProperty,typeof(Window));
        MaxHeight=Math.Max(400,SystemParameters.WorkArea.Height-24);
        var panel=new StackPanel{Margin=new Thickness(24)};Content=new ScrollViewer{Content=panel,VerticalScrollBarVisibility=ScrollBarVisibility.Auto};
        panel.Children.Add(new TextBlock{Text=Title,FontSize=23,FontWeight=FontWeights.Bold});
        panel.Children.Add(new TextBlock{Text="Hikvision · две камеры зоны печати. Подключение напрямую к регистратору по RTSP.",Margin=new Thickness(0,12,0,12)});
        var original=printer.Cameras??new RecorderSettings();
        var enabled=new CheckBox{Content="Показывать камеры этого принтера",IsChecked=original.Enabled,Margin=new Thickness(0,4,0,12)};enabled.SetResourceReference(Control.ForegroundProperty,"TextBrush");panel.Children.Add(enabled);
        TextBox Field(Panel parent,string label,string value){parent.Children.Add(new TextBlock{Text=label});var field=new TextBox{Text=value};parent.Children.Add(field);return field;}
        var addressRow=new Grid();addressRow.ColumnDefinitions.Add(new());addressRow.ColumnDefinitions.Add(new(){Width=new GridLength(120)});panel.Children.Add(addressRow);
        var left=new StackPanel{Margin=new Thickness(0,0,12,0)};var right=new StackPanel();addressRow.Children.Add(left);Grid.SetColumn(right,1);addressRow.Children.Add(right);
        var host=Field(left,"IP регистратора",original.Host);var port=Field(right,"RTSP-порт",original.Port.ToString());
        var username=Field(panel,"Пользователь регистратора",original.Username);
        panel.Children.Add(new TextBlock{Text=string.IsNullOrEmpty(original.ProtectedPassword)?"Пароль регистратора":"Новый пароль (пусто — сохранить прежний)"});
        var password=new PasswordBox();panel.Children.Add(password);
        var channelRow=new Grid();channelRow.ColumnDefinitions.Add(new());channelRow.ColumnDefinitions.Add(new());panel.Children.Add(channelRow);
        var chLeft=new StackPanel{Margin=new Thickness(0,0,12,0)};var chRight=new StackPanel();channelRow.Children.Add(chLeft);Grid.SetColumn(chRight,1);channelRow.Children.Add(chRight);
        var channel1=Field(chLeft,"Камера 1 — канал регистратора",original.Channel1.ToString());
        var channel2=Field(chRight,"Камера 2 — канал регистратора",original.Channel2.ToString());
        var low=new CheckBox{Content="Дополнительный поток (меньше нагрузка на сеть)",IsChecked=original.Substream,Margin=new Thickness(0,2,0,12)};low.SetResourceReference(Control.ForegroundProperty,"TextBrush");panel.Children.Add(low);
        var error=new TextBlock{MinHeight=32,Margin=new Thickness(0,4,0,8)};error.SetResourceReference(TextBlock.ForegroundProperty,"MutedBrush");panel.Children.Add(error);
        RecorderSettings Read()
        {
            if(!int.TryParse(port.Text,out var p)||!int.TryParse(channel1.Text,out var c1)||!int.TryParse(channel2.Text,out var c2))throw new ArgumentException("Порт и каналы должны быть числами.");
            if(password.Password.Length>1024)throw new ArgumentException("Пароль слишком длинный.");
            return new RecorderSettings{Enabled=enabled.IsChecked==true,Host=host.Text.Trim(),Port=p,Channel1=c1,Channel2=c2,Substream=low.IsChecked==true,Username=username.Text.Trim(),ProtectedPassword=string.IsNullOrEmpty(password.Password)?original.ProtectedPassword:CameraSecrets.Protect(password.Password)}.Validate();
        }
        void Try(Action action){try{action();}catch(Exception ex) when(ex is IOException or UnauthorizedAccessException or ArgumentException or CryptographicException or System.Text.Json.JsonException){error.Text="Не удалось применить настройки. Проверьте адрес, порт, каналы и доступ к файлу настроек.";}}
        var buttons=new WrapPanel();panel.Children.Add(buttons);
        var test=new Button{Content="Проверить камеры"};test.Click+=(_,_)=>Try(()=>
        {
            var config=Read();if(!config.Enabled)throw new ArgumentException("Включите камеры для проверки.");
            new CameraPreviewWindow(printer.Name,config){Owner=this}.ShowDialog();
        });buttons.Children.Add(test);
        var save=new Button{Content="Сохранить"};save.Click+=(_,_)=>Try(()=>
        {
            var config=Read();var current=store.Load();
            if(current.Printers.All(p=>p.Id!=printer.Id))throw new ArgumentException("Принтер удалён.");
            store.Save(current with{Printers=current.Printers.Select(p=>p.Id==printer.Id?p with{Cameras=config}:p).ToList()});
            original=config;password.Clear();changed();error.Text="Настройки камер сохранены";
        });buttons.Children.Add(save);
        var close=new Button{Content="Закрыть",IsCancel=true};close.Click+=(_,_)=>Close();buttons.Children.Add(close);
        panel.Children.Add(new TextBlock{Text="Пароль шифруется для текущей учётной записи Windows. После переноса настроек на другой компьютер введите его заново. Видео и звук принтера работают независимо.",FontSize=11,Margin=new Thickness(0,12,0,0)});
        Closed+=(_,_)=>password.Clear();
    }
}
