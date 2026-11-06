using System.Collections.ObjectModel;
using System.Windows;
using System.Windows.Controls;
using UopWork.Core;
namespace UopWork.Desktop.Views;
public sealed class AlarmHistoryWindow : Window
{
    public AlarmHistoryWindow(ObservableCollection<AlarmHistoryEntry> history)
    {
        Title="История аварий";Width=900;Height=600;WindowStyle=WindowStyle.None;ResizeMode=ResizeMode.NoResize;
        WindowStartupLocation=WindowStartupLocation.CenterOwner;ShowInTaskbar=false;
        SetResourceReference(StyleProperty,typeof(Window));
        var panel=new DockPanel{Margin=new Thickness(24)};
        var heading=new TextBlock{Text="История аварий · последние 2000 событий",FontSize=22,FontWeight=FontWeights.Bold,Margin=new Thickness(0,0,0,16)};
        DockPanel.SetDock(heading,Dock.Top);panel.Children.Add(heading);
        var close=new Button{Content="Закрыть",IsCancel=true,HorizontalAlignment=HorizontalAlignment.Right};
        close.Click+=(_,_)=>Close();DockPanel.SetDock(close,Dock.Bottom);panel.Children.Add(close);
        var list=new ListBox{ItemsSource=history};
        var template=new DataTemplate(typeof(AlarmHistoryEntry));
        var text=new FrameworkElementFactory(typeof(TextBlock));text.SetBinding(TextBlock.TextProperty,new System.Windows.Data.Binding(nameof(AlarmHistoryEntry.Display)));
        template.VisualTree=text;list.ItemTemplate=template;panel.Children.Add(list);Content=panel;
    }
}
