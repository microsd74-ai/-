using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Media;
using UopWork.Core;
namespace UopWork.Desktop;
public abstract class Bindable : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    protected void Changed([CallerMemberName] string? name=null)=>PropertyChanged?.Invoke(this,new(name));
    public void Refresh()=>Changed("");
}
public sealed class PrinterItem(PrinterConfig config) : Bindable
{
    public PrinterConfig Config {get;set;}=config;
    public string Name=>Config.Name;
    public Telemetry? Data {get;private set;}
    public string Connection {get;set;}="Нет связи";
    public string? DemoStatus {get;set;}
    public bool IsDemo {get;set;}
    private string acknowledged="",lastAlarm="";
    private int? lastLayer;
    private DateTimeOffset layerChanged=DateTimeOffset.Now;
    public ObservableCollection<string> Events {get;}=[];
    public bool Fresh=>Data is not null && DateTimeOffset.Now-Data.ReceivedAt<TimeSpan.FromSeconds(5) && Connection=="На связи";
    public string Status=>!Fresh?(Data is not null && Connection=="На связи"?"Нет свежих данных":Connection):!Data!.ReadSucceeded?"Ошибка чтения":DemoStatus??(HasAlarm?"Ошибка":Data.Printed==Data.Total && Data.Total>0 && Data.FinishKind=="FINISHED"?"Завершено":"Показания получены");
    public Brush StatusBrush=>HasAlarm?Brushes.Tomato:!Fresh?Brushes.SlateGray:!Data!.ReadSucceeded?Brushes.Orange:Brushes.MediumSeaGreen;
    public string Layers=>Data is null?"— / —":$"{Data.Printed?.ToString()??"—"} / {Data.Total?.ToString()??"—"}";
    public string Finish=>string.IsNullOrWhiteSpace(Data?.Finish)?"Нет данных":Data.Finish;
    public string FinishKind=>Data?.FinishKind=="ESTIMATE"?"Расчётное":Data?.FinishKind=="FINISHED"?"Фактическое":"";
    public string Temperature=>Empty(Data?.Temperature);
    public string Humidity=>Empty(Data?.Humidity);
    public double Progress=>(Data?.Progress??0)*100;
    public string ProgressText=>$"Прогресс задания · {Progress:0.0}%";
    public string LayerTime=>Data is null?"—":$"{Math.Max(0,(int)(DateTimeOffset.Now-layerChanged).TotalSeconds)} с";
    public string Freshness=>Data is null?"Показания ещё не получены":Fresh?$"Обновлено {(int)(DateTimeOffset.Now-Data.ReceivedAt).TotalSeconds} с назад":"Нет свежих показаний";
    public bool HasAlarm=>!string.IsNullOrWhiteSpace(lastAlarm);
    public string AlarmText=>lastAlarm;
    public string ErrorTitle=>!Fresh?"Состояние ошибок неизвестно":HasAlarm?"Ошибка принтера":Data!.ErrorsKnownEmpty?"Ошибок нет":"Состояние ошибок неизвестно";
    public string ErrorDetail=>!Fresh?"Ожидание свежих показаний от агента.":HasAlarm?AlarmText:Data!.ErrorsKnownEmpty?"В источнике подтверждён пустой список ошибок.":"Агент передаёт показания, но достоверность пустого списка ошибок пока не подтверждена.";
    public Brush AlarmBrush=>HasAlarm?new SolidColorBrush(Color.FromRgb(139,30,41)):Fresh && Data!.ErrorsKnownEmpty?new SolidColorBrush(Color.FromRgb(20,94,63)):new SolidColorBrush(Color.FromRgb(104,79,31));
    public string FileInfo=>$"Файл: {Empty(Data?.File)}   ·   Режим: {Empty(Data?.Mode)}";
    public string PrinterLog=>Data?.PrinterLog??"Ожидание записей журнала выбранного принтера.";
    public string AckText=>acknowledged==Normalize(AlarmText)?"Подтверждено":"Подтвердить";
    public void Acknowledge(){if(!HasAlarm)return;acknowledged=Normalize(AlarmText);AddEvent("Сообщение подтверждено оператором");Refresh();}
    public void AddEvent(string text){Events.Insert(0,$"{DateTime.Now:HH:mm:ss}  {text}");while(Events.Count>200)Events.RemoveAt(Events.Count-1);}
    public void Apply(Telemetry data)
    {
        if(data.Printed!=lastLayer){lastLayer=data.Printed;layerChanged=DateTimeOffset.Now;}
        if(!string.IsNullOrWhiteSpace(data.Alarm))
        {
            if(Normalize(data.Alarm)!=Normalize(AlarmText))acknowledged="";
            if(data.Alarm!=AlarmText)AddEvent("Получено сообщение об ошибке: "+data.Alarm);
            lastAlarm=data.Alarm;
        }
        else if(data.ErrorsKnownEmpty)
        {
            if(HasAlarm)AddEvent("Источник подтвердил снятие ошибок");
            lastAlarm="";acknowledged="";
        }
        Data=data;Connection="На связи";Refresh();
    }
    private static string Normalize(string text)=>System.Text.RegularExpressions.Regex.Replace(text,@"^\d+/\d+:","").Trim();
    private static string Empty(string? s)=>string.IsNullOrWhiteSpace(s)?"—":s;
}
public sealed class Dashboard : Bindable
{
    public ObservableCollection<PrinterItem> Printers {get;}=[];
    public IEnumerable<PrinterItem> ActiveAlarms=>Printers.Where(p=>p.HasAlarm);
    public string Attention=>$"Требуют внимания: {ActiveAlarms.Count()}";
    public string Summary=>$"Принтеров: {Printers.Count} · На связи: {Printers.Count(p=>p.Fresh)}";
    public bool Demo {get;}
    public string ModeLabel=>Demo?"ДЕМОНСТРАЦИЯ · искусственные данные":"РАБОЧИЙ РЕЖИМ · данные от принтеров";
    private PrinterItem? selected;
    public PrinterItem? Selected {get=>selected;set{selected=value;Changed();}}
    public string Message {get;set;}="Добавьте принтеры через «Управление».";
    public Dashboard(bool demo)=>Demo=demo;
    public void Tick(){foreach(var p in Printers)p.Refresh();Refresh();}
    public void LoadDemo(IReadOnlyList<PrinterConfig>? configured=null)
    {
        var names=new[]{"FHZL PMMA","FHZL Песок","FHZL №3","FHZL №4","FHZL №5","FHZL №6","FHZL №7"};
        var states=new[]{"Печатает","Ошибка","Остановка","Пауза","Завершено","Нет связи","Ошибка чтения"};
        var configs=configured??names.Select((name,i)=>new PrinterConfig(Guid.NewGuid(),name,$"127.0.0.{i+1}",5055)).ToArray();
        for(int i=0;i<configs.Count;i++)
        {
            int sample=i%states.Length;
            var p=new PrinterItem(configs[i]){IsDemo=true,DemoStatus=states[sample]};
            var alarm=sample==1?"E4.2: Cylinder Alarm":sample==2?"Пример: слой не меняется 67 секунд":"";
            p.Apply(new(configs[i].Name,sample!=6,"",sample==4?2113:420,2113,"20:35",sample==4?"FINISHED":"ESTIMATE","PMMA_0538_0.tif",states[sample],"X 0,00 · Y 0,00", "26,7","32,5",alarm,sample==6?null:true,"[ДЕМО] Пример журнала принтера",DateTimeOffset.Now));
            if(sample==5)p.Connection="Нет связи";
            Printers.Add(p);
        }
        Selected=Printers.FirstOrDefault();Message="Демо-режим: камеры, тревоги и состояния здесь являются примерами.";
    }
}
