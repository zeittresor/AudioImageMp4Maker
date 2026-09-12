# Third-party notices

## FFmpeg

This application uses the external `ffmpeg.exe` and `ffprobe.exe` command-line programs to create and inspect MP4 files.

- Project: FFmpeg
- Website: https://ffmpeg.org/
- Windows build sources used by the dependency script: Gyan FFmpeg builds (direct and GitHub mirror), with BtbN FFmpeg-Builds as a download fallback.
- FFmpeg licensing information: https://ffmpeg.org/legal.html

FFmpeg is **not** covered by this project's MIT License. The compatible Windows builds selected by setup are distributed under their stated FFmpeg/GPL licensing terms. If you redistribute a compiled package that includes `ffmpeg.exe` and/or `ffprobe.exe`, you are responsible for complying with the applicable FFmpeg license obligations.

## .NET

The build scripts use Microsoft's .NET SDK. The SDK is downloaded locally by Microsoft's official `dotnet-install.ps1` script and is not included in this source archive.

- .NET: https://dotnet.microsoft.com/
