using LibVLCSharp.Shared;
namespace UopWork.Desktop.Video;
public static class CameraRuntime
{
    private static readonly Lazy<Task<LibVLC>> engine=new(()=>Task.Run(()=>
    {
        LibVLCSharp.Shared.Core.Initialize();
        return new LibVLC("--quiet","--no-audio","--no-video-title-show","--no-snapshot-preview");
    }));
    public static Task<LibVLC> GetAsync()=>engine.Value;
}
