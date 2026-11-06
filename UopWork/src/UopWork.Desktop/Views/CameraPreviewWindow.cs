using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using UopWork.Core;
using UopWork.Desktop.Video;
namespace UopWork.Desktop.Views;
public sealed class CameraPreviewWindow : Window
{
    public CameraPreviewWindow(string printer,RecorderSettings? settings,bool demo=false,int? camera=null)
    {
        Title="Камеры · "+printer;WindowStyle=WindowStyle.None;ResizeMode=ResizeMode.NoResize;ShowInTaskbar=false;
        WindowStartupLocation=WindowStartupLocation.CenterOwner;Width=camera.HasValue?SystemParameters.PrimaryScreenWidth:1100;Height=camera.HasValue?SystemParameters.PrimaryScreenHeight:650;
        SetResourceReference(StyleProperty,typeof(Window));
        var dock=new DockPanel{Margin=new Thickness(16)};Content=dock;
        var bar=new DockPanel{Margin=new Thickness(0,0,0,12)};
        var close=new Button{Content="Закрыть · Esc",IsCancel=true};close.Click+=(_,_)=>Close();DockPanel.SetDock(close,Dock.Right);bar.Children.Add(close);
        bar.Children.Add(new TextBlock{Text=Title,FontSize=23,VerticalAlignment=VerticalAlignment.Center});DockPanel.SetDock(bar,Dock.Top);dock.Children.Add(bar);
        var grid=new System.Windows.Controls.Primitives.UniformGrid{Columns=camera.HasValue?1:2};dock.Children.Add(grid);
        var panes=new List<CameraPane>();
        foreach(int slot in camera.HasValue?new[]{camera.Value}:new[]{1,2})
        {
            var pane=new CameraPane{CanExpand=false,Margin=new Thickness(6)};pane.Configure(settings,slot,demo);grid.Children.Add(pane);panes.Add(pane);
        }
        PreviewKeyDown+=(_,e)=>{if(e.Key==Key.Escape){Close();e.Handled=true;}};
        Closed+=(_,_)=>{foreach(var pane in panes)pane.Dispose();};
    }
}
