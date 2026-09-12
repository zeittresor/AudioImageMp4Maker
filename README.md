# Audio Image MP4 Maker

A small Windows GUI utility that combines one still image with one WAV or MP3 audio file and writes the result as an MP4 video.

## Features

- Simple Windows Forms GUI written in C#.
- DPI-aware, resizable layout with a 900 × 500 minimum window size so file buttons, status text and video-setting notes remain visible on common Windows display scaling settings.
- Loads `.wav` and `.mp3` audio files.
- Loads common still-image formats: PNG, JPG/JPEG, BMP and WebP.
- Saves GitHub/browser-friendly H.264/AAC MP4 video (`yuv420p`, `avc1`, `faststart`).
- Default output resolution: **640 × 480**.
- Configurable width, height and frame rate.
- Default frame rate: **1 FPS**, which is sufficient for a single still image.
- The source image keeps its original aspect ratio and is never stretched.
- Empty areas are padded with black when the image aspect ratio does not match the video aspect ratio.
- Self-contained Windows x64 build: the generated application does not require a separately installed .NET runtime.

## Quick start for developers

1. Run `01_INSTALL_DEPENDENCIES.cmd`.
   - Before downloading anything, the installer performs a **targeted reuse search** instead of recursively scanning every file in a large development tree.
   - It looks in this project's `.tools` folders, common user Downloads/Temp/Cache locations, and dependency-oriented folders such as `Downloads`, `Temp`, `Cache`, `.cache`, `Tools`, `.tools`, `SDK`, `FFmpeg`, `Dependencies`, `Packages` and `Artifacts` discovered below the surrounding development folder. Directory discovery is limited to a sensible depth and skips trees such as `.git`, `node_modules`, `bin`, `obj`, `dist`, virtual environments and IDE caches.
   - It can reuse an existing compatible .NET 10 SDK, a `dotnet-sdk-10*-win-x64.zip` archive, an existing FFmpeg/FFprobe pair, an FFmpeg essentials ZIP, and an existing `dotnet-install.ps1`. FFmpeg reuse is capability-checked and requires a modern 5.x-or-newer build with the H.264/AAC/filter/muxer features used by this application; merely finding an `ffmpeg.exe` is not enough. The console distinguishes clearly between an actual SDK, an SDK archive, and the small Microsoft installer helper script.
   - Compatible installed tools are reused directly where possible, avoiding unnecessary duplicate copies. Reusable archives can also be extracted locally.
   - Only components that cannot be found locally are downloaded.
   - Setup and build phases show an overall percentage indicator so long operations are visibly progressing.
   - The installer does not blindly use Windows `%TEMP%` for large .NET downloads/extraction. It uses a controlled working directory instead.
   - Before large downloads/extractions, free disk space is checked. If the intended drive is too full, a popup asks whether setup should automatically try another writable drive with enough space.
   - If another drive is selected automatically, the dependency paths are saved in `.tools\dependency-paths.ps1`, and the build script uses those external tools directly.
   - Nothing is installed system-wide.
2. After successful setup, a visible **10-second countdown** starts and the release build begins automatically.
3. After a successful build, a second **10-second countdown** starts and the compiled application is launched automatically. If setup or compilation fails, the next automatic step is not started and the console remains open with the error.
4. You can also run `02_BUILD_RELEASE.cmd` directly; after a successful build it uses the same 10-second application-start countdown.
5. The ready-to-run package is created as:
   - `dist\AudioImageMp4Maker-win-x64\`
   - `dist\AudioImageMp4Maker-win-x64.zip`

The build script automatically runs the dependency installer if required files are missing or previously saved dependency paths are no longer valid. The same reuse-first and disk-space fallback logic therefore also applies when you start directly with the build script.


## Version 1.0.11

- Fixed a C# source-code syntax error in the FFmpeg compatibility warning that prevented v1.0.10 from compiling.
- The warning now uses explicit `\r\n` escape sequences instead of accidental physical line breaks inside a normal C# string literal.
- Added source sanity checks during packaging for illegal line breaks inside ordinary C# string literals.

## Version 1.0.10

- Faster FFmpeg setup: large downloads prefer the Gyan GitHub release mirror and use `curl.exe` on Windows 10/11.
- Large-download output now shows real transfer statistics instead of appearing to hang.
- Automatic slow-transfer watchdog: if a source stays below 128 KiB/s for 25 seconds, setup tries the next source.
- Download fallback order: Gyan GitHub mirror, direct gyan.dev build, then a compatible BtbN GitHub build.
- Incomplete `.part` downloads are never mistaken for reusable FFmpeg archives.
- Corrupt/incomplete reusable ZIP files are skipped instead of aborting setup.

## Version 1.0.9

- Fixed video generation failing when setup accidentally reused a very old FFmpeg build (for example 2013-era `N-xxxxx` builds from unrelated Python tool folders).
- Dependency reuse now requires FFmpeg 5.x or newer and verifies `libx264`, AAC, `force_original_aspect_ratio`, `faststart` and the modern command-line options used by the application.
- Outdated/incompatible FFmpeg installations are explicitly skipped with a reason instead of being treated as valid merely because `ffmpeg -version` runs.
- Reusable FFmpeg ZIP archives are validated too; an old archive is ignored and a current essentials build is downloaded automatically.
- The release build re-validates the saved FFmpeg pair before copying it into `dist`, preventing stale dependency-path files from reintroducing an old executable.
- The GUI performs a final compatibility check and shows a concise remediation message if an incompatible external FFmpeg is ever detected.

## Version 1.0.8

- Reworked the main window from tightly packed fixed/flow positioning to DPI-aware `TableLayoutPanel` layouts.
- Audio/Image/Output browse buttons remain visible when the window is resized or Windows display scaling is enabled.
- Video-setting explanation text now has its own rows instead of sharing the Width/Height/FPS line.
- The status area and `github.com/zeittresor` footer are anchored independently so neither can push the other outside the window.

## Usage

1. Click **Browse…** next to **Audio** and select a WAV or MP3 file.
2. Click **Browse…** next to **Image** and select a still image.
3. Click **Save as…** and select the output MP4 file.
4. Adjust width, height or FPS if required.
5. Click **Generate MP4**.

For broad playback compatibility, the generated video uses H.264 video, AAC audio and `yuv420p` pixel format.


## GitHub README compatibility

The default output is intentionally conservative for GitHub README video use:

- MP4 container.
- H.264 video, which GitHub currently recommends for broad browser compatibility.
- AAC-LC stereo audio at 48 kHz.
- `yuv420p` pixel format.
- `avc1` video tag.
- `faststart` enabled so MP4 metadata is placed at the beginning of the file for progressive playback.
- The application targets a final file size below 10 MB so it remains suitable for video attachments in repositories on GitHub Free. Paid GitHub plans currently allow larger video attachments, but the tool uses the stricter free-plan target by default.

GitHub or the user's browser may initially render an embedded README video as muted. That volume/mute state belongs to GitHub's player and browser autoplay/media policy; it is not stored as an MP4 setting and therefore cannot be forced on by this application. Once unmuted, the original source audio level is preserved.

## Why FFmpeg is separate

The application source code is licensed under the MIT License. FFmpeg is an independent third-party project with its own licensing terms. The setup script downloads FFmpeg separately and the build script copies `ffmpeg.exe` and `ffprobe.exe` into the release folder for convenience. See `THIRD_PARTY_NOTICES.md` before redistributing compiled packages.

## Project reference

https://github.com/zeittresor

## License

The C# application source code and project-specific scripts are released under the MIT License. See `LICENSE`.
