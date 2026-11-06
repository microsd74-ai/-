# Video components

UOP WORK v0.3.0 dynamically links the following unmodified VideoLAN packages:

- LibVLCSharp / LibVLCSharp.WPF 3.10.2 — LGPL-2.1-or-later. Source: https://code.videolan.org/videolan/LibVLCSharp , package source commit 3082c09ca955131c705fc4767fde03e9c4a14999 . Packages: https://www.nuget.org/packages/LibVLCSharp.WPF/3.10.2 .
- VideoLAN.LibVLC.Windows 3.0.24 — package license LGPL-2.1-or-later. Package/source build project: https://code.videolan.org/videolan/libvlc-nuget . VLC source: https://code.videolan.org/videolan/vlc , release sources: https://download.videolan.org/pub/videolan/vlc/3.0.24/ . Package: https://www.nuget.org/packages/VideoLAN.LibVLC.Windows/3.0.24 .

The LGPL 2.1 text is included in licenses/LGPL-2.1.txt. The libraries remain separate DLLs, with no technical prohibition on replacing them with compatible builds. The UOP WORK source and build instructions are available at https://github.com/microsd74-ai/- . Keep the native libraries and plugins together with the distributed notices. Individual VLC modules and dependencies retain their own copyrights and applicable licenses as provided by their upstream source distributions.

The test video tests/fixtures/camera-test.mp4 was generated using FFmpeg's synthetic testsrc2 source (320x180, 12 fps, 3 seconds, H.264). It contains no camera footage or user data and is only included in the source/test project, not the operator application.
