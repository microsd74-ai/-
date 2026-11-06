namespace UopWork.Core;

// Uses monotonic time, so changes of Windows clock cannot trigger an alarm.
// Pauses intentionally do not disable this timer (operator's requirement).
public sealed class LayerWatchdog(TimeProvider? timeProvider = null)
{
    private readonly TimeProvider clock=timeProvider??TimeProvider.System;
    private long lastSample,changedAt;
    private int? layer,total;
    private string file="";
    private bool tracking;
    public const int ThresholdSeconds=60;
    public bool IsTracking=>tracking;
    public int Seconds=>tracking?(int)Math.Max(0,clock.GetElapsedTime(changedAt).TotalSeconds):0;
    public bool IsStalled=>tracking&&Seconds>=ThresholdSeconds;
    public void Observe(Telemetry data)
    {
        bool eligible=data.ReadSucceeded&&data.Printed is >=0&&data.Total is >0&&data.Printed<data.Total&&data.FinishKind!="FINISHED";
        if(!eligible){Reset();return;}
        var now=clock.GetTimestamp();
        if(!tracking||clock.GetElapsedTime(lastSample,now)>TimeSpan.FromSeconds(5)||
            layer!=data.Printed||total!=data.Total||file!=data.File)
            changedAt=now;
        layer=data.Printed;total=data.Total;file=data.File;lastSample=now;tracking=true;
    }
    public void Tick(bool connected)
    {
        if(!connected||(tracking&&clock.GetElapsedTime(lastSample)>TimeSpan.FromSeconds(5)))Reset();
    }
    private void Reset(){tracking=false;layer=null;total=null;file="";}
}
