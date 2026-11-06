using System.IO;
using System.Windows;
using System.Windows.Controls;
using Microsoft.Win32;
using UopWork.Core;
namespace UopWork.Desktop.Views;
public sealed class AudioSettingsWindow : Window
{
    private readonly AlarmAudio preview=new();
    public AudioSettingsWindow(SettingsStore settings,Action changed)
    {
        Title="Звуковые оповещения";Width=700;SizeToContent=SizeToContent.Height;
        WindowStyle=WindowStyle.None;ResizeMode=ResizeMode.NoResize;ShowInTaskbar=false;
        WindowStartupLocation=WindowStartupLocation.CenterOwner;SetResourceReference(StyleProperty,typeof(Window));
        var panel=new StackPanel{Margin=new Thickness(24)};Content=panel;
        panel.Children.Add(new TextBlock{Text="Звуковые оповещения",FontSize=23,FontWeight=FontWeights.Bold});
        var category=new ComboBox{Margin=new Thickness(0,12,0,8),ItemsSource=new[]{"Ошибка принтера","Печать остановилась (60 секунд)"},SelectedIndex=0};panel.Children.Add(category);
        panel.Children.Add(new TextBlock{Text="Для выбранного события: запись WAV до 20 МБ. Без записи используется русский женский голос Windows, если он установлен; иначе — звуковой сигнал.",Margin=new Thickness(0,16,0,12)});
        var saved=settings.Load();string alarmFile=saved.AlarmSoundFile,stopFile=saved.StopSoundFile;bool selectedStop=false;
        var path=new TextBox{Text=alarmFile,IsReadOnly=true};panel.Children.Add(path);
        void Remember(){if(selectedStop)stopFile=path.Text;else alarmFile=path.Text;}
        category.SelectionChanged+=(_,_)=>{Remember();selectedStop=category.SelectedIndex==1;path.Text=selectedStop?stopFile:alarmFile;};
        var message=new TextBlock{Margin=new Thickness(0,8,0,12)};panel.Children.Add(message);
        var buttons=new WrapPanel();panel.Children.Add(buttons);
        Button Add(string text,RoutedEventHandler click){var b=new Button{Content=text};b.Click+=click;buttons.Children.Add(b);return b;}
        Add("Выбрать WAV",(_,_)=>
        {
            var dialog=new OpenFileDialog{Filter="WAV (*.wav)|*.wav"};
            if(dialog.ShowDialog(this)==true)path.Text=dialog.FileName;
        });
        Add("Голос Windows / сигнал",(_,_)=>path.Text="");
        Add("Проверить звук",(_,_)=>{preview.Test(path.Text,selectedStop);message.Text=preview.Status;});
        Add("Остановить проверку",(_,_)=>preview.Stop());
        Add("Сохранить",(_,_)=>
        {
            try{Remember();settings.Save(settings.Load() with{AlarmSoundFile=alarmFile,StopSoundFile=stopFile});changed();message.Text="Настройки сохранены";}
            catch(Exception ex) when(ex is IOException or ArgumentException or UnauthorizedAccessException){message.Text=ex.Message;}
        });
        var close=Add("Закрыть",(_,_)=>Close());close.IsCancel=true;
        panel.Children.Add(new TextBlock{Text="Повтор — каждые 10 секунд до подтверждения или достоверного снятия аварии. Убедитесь, что динамики включены. Файл записи должен оставаться по выбранному пути.",Margin=new Thickness(0,16,0,0)});
        Closed+=(_,_)=>preview.Dispose();
    }
}
