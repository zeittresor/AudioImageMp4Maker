using System.Diagnostics;
using System.Drawing;
using System.Globalization;

namespace AudioImageMp4Maker;

public sealed class MainForm : Form
{
    // GitHub currently allows video attachments up to 10 MB for repositories on a free plan.
    // We deliberately target below that limit so the generated MP4 remains suitable for README attachment use.
    private const long GitHubHardLimitBytes = 10_000_000;
    private const long GitHubTargetBytes = 8_800_000;
    private const long GitHubSafeBytes = 9_500_000;
    private const int MaxAudioBitrateKbps = 128;
    private const int MinAudioBitrateKbps = 16;

    private readonly TextBox _audioPath = new() { ReadOnly = true };
    private readonly TextBox _imagePath = new() { ReadOnly = true };
    private readonly TextBox _outputPath = new() { ReadOnly = true };
    private readonly NumericUpDown _width = new() { Minimum = 64, Maximum = 7680, Value = 640, Increment = 2, Width = 90 };
    private readonly NumericUpDown _height = new() { Minimum = 64, Maximum = 4320, Value = 480, Increment = 2, Width = 90 };
    private readonly NumericUpDown _fps = new() { Minimum = 1, Maximum = 60, Value = 1, Width = 70 };
    private readonly Button _generateButton = new() { Text = "Generate MP4", AutoSize = true, Height = 34 };
    private readonly ProgressBar _progress = new() { Style = ProgressBarStyle.Marquee, MarqueeAnimationSpeed = 25, Visible = false };
    private readonly Label _status = new() { Text = "Ready.", AutoSize = true };

    public MainForm()
    {
        Text = "Audio Image MP4 Maker";
        StartPosition = FormStartPosition.CenterScreen;

        // Use DPI scaling explicitly. The old layout relied on tightly packed AutoSize/FlowLayout
        // controls, which could push the right-hand buttons and help text outside the client area
        // at common Windows scaling factors.
        AutoScaleMode = AutoScaleMode.Dpi;
        MinimumSize = new Size(900, 500);
        ClientSize = new Size(940, 500);
        Font = new Font("Segoe UI", 9F);

        var appIcon = System.Drawing.Icon.ExtractAssociatedIcon(Application.ExecutablePath);
        if (appIcon is not null) Icon = appIcon;

        BuildLayout();
        _generateButton.Click += async (_, _) => await GenerateVideoAsync();
    }

    private void BuildLayout()
    {
        SuspendLayout();

        var root = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            Padding = new Padding(16),
            ColumnCount = 1,
            RowCount = 4,
            AutoSize = false
        };
        root.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));

        var title = new Label
        {
            Text = "Create an MP4 from one still image and one audio file",
            Font = new Font(Font, FontStyle.Bold),
            AutoSize = true,
            Anchor = AnchorStyles.Left,
            Margin = new Padding(0, 0, 0, 14)
        };
        root.Controls.Add(title, 0, 0);

        var files = new TableLayoutPanel
        {
            Dock = DockStyle.Top,
            ColumnCount = 3,
            RowCount = 3,
            AutoSize = true,
            GrowStyle = TableLayoutPanelGrowStyle.FixedSize,
            Margin = new Padding(0, 0, 0, 16)
        };
        files.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 70F));
        files.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
        files.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 100F));
        files.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        files.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        files.RowStyles.Add(new RowStyle(SizeType.AutoSize));

        AddFileRow(files, 0, "Audio:", _audioPath, "Browse...", SelectAudio);
        AddFileRow(files, 1, "Image:", _imagePath, "Browse...", SelectImage);
        AddFileRow(files, 2, "Output:", _outputPath, "Save as...", SelectOutput);
        root.Controls.Add(files, 0, 1);

        var settingsBox = new GroupBox
        {
            Text = "Video settings",
            Dock = DockStyle.Fill,
            Padding = new Padding(12),
            Margin = new Padding(0, 0, 0, 14)
        };

        var settings = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 6,
            RowCount = 4,
            AutoSize = false,
            Padding = new Padding(2, 4, 2, 4)
        };
        settings.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        settings.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 105F));
        settings.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        settings.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 105F));
        settings.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        settings.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
        settings.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        settings.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        settings.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        settings.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));

        var widthLabel = new Label
        {
            Text = "Width:",
            AutoSize = true,
            Anchor = AnchorStyles.Left,
            Margin = new Padding(0, 7, 6, 6)
        };
        var heightLabel = new Label
        {
            Text = "Height:",
            AutoSize = true,
            Anchor = AnchorStyles.Left,
            Margin = new Padding(16, 7, 6, 6)
        };
        var fpsLabel = new Label
        {
            Text = "FPS:",
            AutoSize = true,
            Anchor = AnchorStyles.Left,
            Margin = new Padding(16, 7, 6, 6)
        };

        _width.Anchor = AnchorStyles.Left;
        _height.Anchor = AnchorStyles.Left;
        _fps.Anchor = AnchorStyles.Left;
        _width.Margin = new Padding(0, 3, 0, 3);
        _height.Margin = new Padding(0, 3, 0, 3);
        _fps.Margin = new Padding(0, 3, 0, 3);

        settings.Controls.Add(widthLabel, 0, 0);
        settings.Controls.Add(_width, 1, 0);
        settings.Controls.Add(heightLabel, 2, 0);
        settings.Controls.Add(_height, 3, 0);
        settings.Controls.Add(fpsLabel, 4, 0);
        settings.Controls.Add(_fps, 5, 0);

        var fitInfo = new Label
        {
            Text = "The image keeps its aspect ratio and is fitted without stretching. Empty space is filled with black bars.",
            AutoSize = true,
            MaximumSize = new Size(0, 0),
            Anchor = AnchorStyles.Left,
            Margin = new Padding(0, 12, 0, 3)
        };
        settings.Controls.Add(fitInfo, 0, 1);
        settings.SetColumnSpan(fitInfo, 6);

        var githubInfo = new Label
        {
            Text = "GitHub README-safe output: H.264/AAC, yuv420p, avc1, faststart, target below 10 MB.",
            AutoSize = true,
            ForeColor = SystemColors.GrayText,
            Anchor = AnchorStyles.Left,
            Margin = new Padding(0, 5, 0, 0)
        };
        settings.Controls.Add(githubInfo, 0, 2);
        settings.SetColumnSpan(githubInfo, 6);

        settingsBox.Controls.Add(settings);
        root.Controls.Add(settingsBox, 0, 2);

        var footer = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 3,
            RowCount = 1,
            AutoSize = true,
            Margin = new Padding(0)
        };
        footer.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        footer.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
        footer.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        footer.RowStyles.Add(new RowStyle(SizeType.AutoSize));

        _generateButton.AutoSize = false;
        _generateButton.Size = new Size(120, 34);
        _generateButton.Anchor = AnchorStyles.Left | AnchorStyles.Bottom;
        _generateButton.Margin = new Padding(0, 0, 10, 0);
        footer.Controls.Add(_generateButton, 0, 0);

        var progressAndStatus = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 2,
            RowCount = 1,
            AutoSize = true,
            Margin = new Padding(0)
        };
        progressAndStatus.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 165F));
        progressAndStatus.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));

        _progress.Dock = DockStyle.Fill;
        _progress.Height = 23;
        _progress.Margin = new Padding(0, 5, 12, 3);
        progressAndStatus.Controls.Add(_progress, 0, 0);

        _status.AutoSize = false;
        _status.Dock = DockStyle.Fill;
        _status.TextAlign = ContentAlignment.MiddleLeft;
        _status.AutoEllipsis = true;
        _status.Margin = new Padding(0, 3, 8, 0);
        progressAndStatus.Controls.Add(_status, 1, 0);
        footer.Controls.Add(progressAndStatus, 1, 0);

        var githubLabel = new Label
        {
            Text = "github.com/zeittresor",
            AutoSize = true,
            ForeColor = SystemColors.GrayText,
            Anchor = AnchorStyles.Right | AnchorStyles.Bottom,
            Margin = new Padding(16, 9, 0, 0)
        };
        footer.Controls.Add(githubLabel, 2, 0);

        root.Controls.Add(footer, 0, 3);
        Controls.Add(root);

        ResumeLayout(true);
    }

    private static void AddFileRow(TableLayoutPanel table, int row, string labelText, TextBox box, string buttonText, EventHandler click)
    {
        var label = new Label
        {
            Text = labelText,
            AutoSize = true,
            Anchor = AnchorStyles.Left,
            Margin = new Padding(0, 8, 8, 8)
        };

        box.Dock = DockStyle.Fill;
        box.Margin = new Padding(0, 4, 10, 4);

        var button = new Button
        {
            Text = buttonText,
            Dock = DockStyle.Fill,
            MinimumSize = new Size(90, 28),
            Margin = new Padding(0, 3, 0, 3)
        };
        button.Click += click;

        table.Controls.Add(label, 0, row);
        table.Controls.Add(box, 1, row);
        table.Controls.Add(button, 2, row);
    }

    private void SelectAudio(object? sender, EventArgs e)
    {
        using var dialog = new OpenFileDialog
        {
            Title = "Select audio file",
            Filter = "Audio files (*.wav;*.mp3)|*.wav;*.mp3|WAV files (*.wav)|*.wav|MP3 files (*.mp3)|*.mp3|All files (*.*)|*.*"
        };
        if (dialog.ShowDialog(this) == DialogResult.OK)
            _audioPath.Text = dialog.FileName;
    }

    private void SelectImage(object? sender, EventArgs e)
    {
        using var dialog = new OpenFileDialog
        {
            Title = "Select image file",
            Filter = "Image files (*.png;*.jpg;*.jpeg;*.bmp;*.webp)|*.png;*.jpg;*.jpeg;*.bmp;*.webp|All files (*.*)|*.*"
        };
        if (dialog.ShowDialog(this) == DialogResult.OK)
            _imagePath.Text = dialog.FileName;
    }

    private void SelectOutput(object? sender, EventArgs e)
    {
        using var dialog = new SaveFileDialog
        {
            Title = "Save MP4 video",
            Filter = "MP4 video (*.mp4)|*.mp4",
            DefaultExt = "mp4",
            AddExtension = true,
            FileName = "output.mp4"
        };
        if (dialog.ShowDialog(this) == DialogResult.OK)
            _outputPath.Text = dialog.FileName;
    }

    private async Task GenerateVideoAsync()
    {
        if (!ValidateInputs(out var error))
        {
            MessageBox.Show(this, error, "Missing or invalid input", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        var ffmpeg = FindFfmpeg();
        var ffprobe = FindFfprobe();
        if (ffmpeg is null || ffprobe is null)
        {
            MessageBox.Show(this,
                "FFmpeg/FFprobe was not found. Run 01_INSTALL_DEPENDENCIES.cmd first, or place a current compatible ffmpeg.exe and ffprobe.exe next to this application.",
                "Media tools not found", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }

        var mediaCompatibility = await CheckMediaToolsAsync(ffmpeg, ffprobe);
        if (!mediaCompatibility.Compatible)
        {
            MessageBox.Show(this,
                "The detected FFmpeg/FFprobe pair is too old or incompatible with the MP4 settings this application requires.\r\n\r\n" +
                mediaCompatibility.Reason +
                "\r\n\r\nRun 01_INSTALL_DEPENDENCIES.cmd again. The installer will ignore outdated FFmpeg builds and obtain a compatible one.",
                "Incompatible media tools", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }

        var width = MakeEven((int)_width.Value);
        var height = MakeEven((int)_height.Value);
        var fps = (int)_fps.Value;

        if (width != (int)_width.Value) _width.Value = width;
        if (height != (int)_height.Value) _height.Value = height;

        ToggleBusy(true, "Checking audio…");
        try
        {
            var duration = await ProbeDurationAsync(ffprobe, _audioPath.Text);
            if (duration is null || duration <= 0)
            {
                ToggleBusy(false, "Failed.");
                MessageBox.Show(this,
                    "The audio duration could not be determined. GitHub-safe size targeting requires a readable duration.",
                    "Could not read audio", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            var audioBitrate = CalculateGitHubSafeAudioBitrate(duration.Value);
            if (audioBitrate < MinAudioBitrateKbps)
            {
                ToggleBusy(false, "Audio is too long.");
                MessageBox.Show(this,
                    $"This audio file is too long to guarantee an MP4 below GitHub's 10 MB free-tier video limit at the minimum supported AAC bitrate.\n\nDuration: {FormatDuration(duration.Value)}\n\nPlease shorten the audio file.",
                    "GitHub size limit", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            audioBitrate = Math.Clamp(audioBitrate, MinAudioBitrateKbps, MaxAudioBitrateKbps);
            ToggleBusy(true, $"Generating GitHub-safe MP4 ({audioBitrate} kbps audio)…");

            var result = await RunFfmpegAsync(ffmpeg, width, height, fps, audioBitrate, crf: 24);
            if (!result.Success)
            {
                ToggleBusy(false, "Failed.");
                MessageBox.Show(this, "Video generation failed.\n\n" + result.Error,
                    "Generation failed", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            var outputSize = new FileInfo(_outputPath.Text).Length;
            if (outputSize > GitHubSafeBytes)
            {
                // Retry once with additional margin. This keeps the output GitHub-safe instead of silently
                // producing a file that may be rejected by the 10 MB free-tier upload limit.
                var retryBitrate = Math.Max(MinAudioBitrateKbps,
                    (int)Math.Floor(audioBitrate * (GitHubTargetBytes / (double)outputSize) * 0.90));

                if (retryBitrate < audioBitrate)
                {
                    ToggleBusy(true, $"Optimizing for GitHub ({retryBitrate} kbps audio)…");
                    result = await RunFfmpegAsync(ffmpeg, width, height, fps, retryBitrate, crf: 28);
                    if (!result.Success)
                    {
                        ToggleBusy(false, "Failed.");
                        MessageBox.Show(this, "Video optimization failed.\n\n" + result.Error,
                            "Generation failed", MessageBoxButtons.OK, MessageBoxIcon.Error);
                        return;
                    }
                    outputSize = new FileInfo(_outputPath.Text).Length;
                }
            }

            if (outputSize >= GitHubHardLimitBytes)
            {
                try { File.Delete(_outputPath.Text); } catch { }
                ToggleBusy(false, "Too large for GitHub.");
                MessageBox.Show(this,
                    "The generated file would still be at or above 10 MB, so it was removed instead of leaving an MP4 that may be rejected by GitHub.\n\nPlease shorten the audio file or use a smaller output resolution.",
                    "GitHub size limit", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            ToggleBusy(false, "Finished - GitHub ready.");
            MessageBox.Show(this,
                $"MP4 video created successfully.\n\nGitHub-ready format: H.264 / AAC-LC / yuv420p / avc1 / faststart\nFile size: {FormatBytes(outputSize)}\n\nNote: GitHub or the browser may initially mute embedded README videos. That player mute state cannot be controlled by the MP4 file.",
                "Done", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
        catch (Exception ex)
        {
            ToggleBusy(false, "Failed.");
            MessageBox.Show(this, "Could not generate the video.\n\n" + ex.Message,
                "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private async Task<(bool Success, string Error)> RunFfmpegAsync(
        string ffmpeg, int width, int height, int fps, int audioBitrateKbps, int crf)
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = ffmpeg,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardError = true,
            RedirectStandardOutput = true
        };

        startInfo.ArgumentList.Add("-hide_banner");
        startInfo.ArgumentList.Add("-y");
        startInfo.ArgumentList.Add("-loop");
        startInfo.ArgumentList.Add("1");
        startInfo.ArgumentList.Add("-framerate");
        startInfo.ArgumentList.Add(fps.ToString(CultureInfo.InvariantCulture));
        startInfo.ArgumentList.Add("-i");
        startInfo.ArgumentList.Add(_imagePath.Text);
        startInfo.ArgumentList.Add("-i");
        startInfo.ArgumentList.Add(_audioPath.Text);
        startInfo.ArgumentList.Add("-map");
        startInfo.ArgumentList.Add("0:v:0");
        startInfo.ArgumentList.Add("-map");
        startInfo.ArgumentList.Add("1:a:0");
        startInfo.ArgumentList.Add("-vf");
        startInfo.ArgumentList.Add($"scale={width}:{height}:force_original_aspect_ratio=decrease,pad={width}:{height}:(ow-iw)/2:(oh-ih)/2:color=black,setsar=1");
        startInfo.ArgumentList.Add("-c:v");
        startInfo.ArgumentList.Add("libx264");
        startInfo.ArgumentList.Add("-preset");
        startInfo.ArgumentList.Add("medium");
        startInfo.ArgumentList.Add("-tune");
        startInfo.ArgumentList.Add("stillimage");
        startInfo.ArgumentList.Add("-crf");
        startInfo.ArgumentList.Add(crf.ToString(CultureInfo.InvariantCulture));
        startInfo.ArgumentList.Add("-r");
        startInfo.ArgumentList.Add(fps.ToString(CultureInfo.InvariantCulture));
        startInfo.ArgumentList.Add("-pix_fmt");
        startInfo.ArgumentList.Add("yuv420p");
        startInfo.ArgumentList.Add("-tag:v");
        startInfo.ArgumentList.Add("avc1");
        startInfo.ArgumentList.Add("-c:a");
        startInfo.ArgumentList.Add("aac");
        startInfo.ArgumentList.Add("-profile:a");
        startInfo.ArgumentList.Add("aac_low");
        startInfo.ArgumentList.Add("-b:a");
        startInfo.ArgumentList.Add($"{audioBitrateKbps}k");
        startInfo.ArgumentList.Add("-ar");
        startInfo.ArgumentList.Add("48000");
        startInfo.ArgumentList.Add("-ac");
        startInfo.ArgumentList.Add("2");
        startInfo.ArgumentList.Add("-shortest");
        startInfo.ArgumentList.Add("-movflags");
        startInfo.ArgumentList.Add("+faststart");
        startInfo.ArgumentList.Add("-f");
        startInfo.ArgumentList.Add("mp4");
        startInfo.ArgumentList.Add(_outputPath.Text);

        using var process = new Process { StartInfo = startInfo };
        process.Start();
        var stderrTask = process.StandardError.ReadToEndAsync();
        var stdoutTask = process.StandardOutput.ReadToEndAsync();
        await process.WaitForExitAsync();
        var stderr = await stderrTask;
        _ = await stdoutTask;

        if (process.ExitCode == 0)
            return (true, string.Empty);

        var details = string.IsNullOrWhiteSpace(stderr) ? "FFmpeg returned an unknown error." : LastLines(stderr, 16);
        return (false, details);
    }

    private static async Task<(bool Compatible, string Reason)> CheckMediaToolsAsync(string ffmpeg, string ffprobe)
    {
        static async Task<(int ExitCode, string Output)> RunToolAsync(string fileName, params string[] args)
        {
            var psi = new ProcessStartInfo
            {
                FileName = fileName,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardError = true,
                RedirectStandardOutput = true
            };
            foreach (var arg in args) psi.ArgumentList.Add(arg);

            using var process = new Process { StartInfo = psi };
            process.Start();
            var stdoutTask = process.StandardOutput.ReadToEndAsync();
            var stderrTask = process.StandardError.ReadToEndAsync();
            await process.WaitForExitAsync();
            return (process.ExitCode, (await stdoutTask) + Environment.NewLine + (await stderrTask));
        }

        try
        {
            var version = await RunToolAsync(ffmpeg, "-version");
            if (version.ExitCode != 0)
                return (false, "ffmpeg -version failed.");

            var match = System.Text.RegularExpressions.Regex.Match(version.Output,
                @"(?im)^ffmpeg version\s+n?(\d+)\.");
            if (!match.Success)
                return (false, "The FFmpeg version could not be recognized as a modern stable build. Version 5.x or newer is required.");
            if (!int.TryParse(match.Groups[1].Value, out var major) || major < 5)
                return (false, $"FFmpeg {match.Groups[1].Value}.x is too old. Version 5.x or newer is required.");

            var probeVersion = await RunToolAsync(ffprobe, "-version");
            if (probeVersion.ExitCode != 0)
                return (false, "ffprobe -version failed.");

            var encoders = await RunToolAsync(ffmpeg, "-hide_banner", "-encoders");
            if (encoders.ExitCode != 0)
                return (false, "This FFmpeg build does not support the required command-line options.");
            if (!System.Text.RegularExpressions.Regex.IsMatch(encoders.Output, @"(?im)^\s*V\S*\s+libx264\s"))
                return (false, "This FFmpeg build does not contain the required libx264 H.264 encoder.");
            if (!System.Text.RegularExpressions.Regex.IsMatch(encoders.Output, @"(?im)^\s*A\S*\s+aac\s"))
                return (false, "This FFmpeg build does not contain the required AAC encoder.");

            var scale = await RunToolAsync(ffmpeg, "-hide_banner", "-h", "filter=scale");
            if (scale.ExitCode != 0 || !scale.Output.Contains("force_original_aspect_ratio", StringComparison.OrdinalIgnoreCase))
                return (false, "This FFmpeg build has an outdated scale filter and cannot preserve the image aspect ratio as required.");

            return (true, string.Empty);
        }
        catch (Exception ex)
        {
            return (false, ex.Message);
        }
    }

    private static async Task<double?> ProbeDurationAsync(string ffprobe, string audioPath)
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = ffprobe,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardError = true,
            RedirectStandardOutput = true
        };
        startInfo.ArgumentList.Add("-v");
        startInfo.ArgumentList.Add("error");
        startInfo.ArgumentList.Add("-show_entries");
        startInfo.ArgumentList.Add("format=duration");
        startInfo.ArgumentList.Add("-of");
        startInfo.ArgumentList.Add("default=noprint_wrappers=1:nokey=1");
        startInfo.ArgumentList.Add(audioPath);

        using var process = new Process { StartInfo = startInfo };
        process.Start();
        var outputTask = process.StandardOutput.ReadToEndAsync();
        var errorTask = process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync();
        var output = (await outputTask).Trim();
        _ = await errorTask;

        if (process.ExitCode != 0)
            return null;

        return double.TryParse(output, NumberStyles.Float, CultureInfo.InvariantCulture, out var duration) && duration > 0
            ? duration
            : null;
    }

    private static int CalculateGitHubSafeAudioBitrate(double durationSeconds)
    {
        // Reserve 750 kB for the MP4 container plus the static H.264 stream.
        // Static imagery is extremely compressible, but the reserve keeps the estimate conservative.
        const long reserveBytes = 750_000;
        var usableBits = Math.Max(0, GitHubTargetBytes - reserveBytes) * 8.0;
        var totalKbps = usableBits / durationSeconds / 1000.0;
        const double estimatedVideoKbps = 4.0;
        return (int)Math.Floor(totalKbps - estimatedVideoKbps);
    }

    private static string FormatDuration(double seconds)
    {
        var span = TimeSpan.FromSeconds(seconds);
        return span.TotalHours >= 1
            ? $"{(int)span.TotalHours}:{span.Minutes:00}:{span.Seconds:00}"
            : $"{span.Minutes}:{span.Seconds:00}";
    }

    private static string FormatBytes(long bytes)
        => $"{bytes / 1024d / 1024d:0.00} MiB";

    private bool ValidateInputs(out string error)
    {
        if (string.IsNullOrWhiteSpace(_audioPath.Text) || !File.Exists(_audioPath.Text))
        {
            error = "Please select an existing WAV or MP3 audio file.";
            return false;
        }
        if (string.IsNullOrWhiteSpace(_imagePath.Text) || !File.Exists(_imagePath.Text))
        {
            error = "Please select an existing image file.";
            return false;
        }
        if (string.IsNullOrWhiteSpace(_outputPath.Text))
        {
            error = "Please select an output MP4 file.";
            return false;
        }

        var outputDir = Path.GetDirectoryName(_outputPath.Text);
        if (string.IsNullOrWhiteSpace(outputDir) || !Directory.Exists(outputDir))
        {
            error = "The selected output folder does not exist.";
            return false;
        }

        error = string.Empty;
        return true;
    }

    private static int MakeEven(int value) => value % 2 == 0 ? value : value + 1;

    private void ToggleBusy(bool busy, string text)
    {
        _generateButton.Enabled = !busy;
        _progress.Visible = busy;
        _status.Text = text;
        UseWaitCursor = busy;
    }

    private static string? FindFfmpeg()
    {
        var candidates = new[]
        {
            Path.Combine(AppContext.BaseDirectory, "ffmpeg.exe"),
            Path.Combine(AppContext.BaseDirectory, "tools", "ffmpeg", "ffmpeg.exe"),
            Path.Combine(AppContext.BaseDirectory, ".tools", "ffmpeg", "ffmpeg.exe"),
            Path.Combine(Environment.CurrentDirectory, ".tools", "ffmpeg", "ffmpeg.exe")
        };

        foreach (var candidate in candidates)
            if (File.Exists(candidate)) return candidate;

        var path = Environment.GetEnvironmentVariable("PATH") ?? string.Empty;
        foreach (var folder in path.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
        {
            try
            {
                var candidate = Path.Combine(folder.Trim(), "ffmpeg.exe");
                if (File.Exists(candidate)) return candidate;
            }
            catch
            {
                // Ignore malformed PATH entries and continue searching.
            }
        }

        return null;
    }


    private static string? FindFfprobe()
    {
        var ffmpeg = FindFfmpeg();
        if (ffmpeg is not null)
        {
            var sibling = Path.Combine(Path.GetDirectoryName(ffmpeg) ?? string.Empty, "ffprobe.exe");
            if (File.Exists(sibling)) return sibling;
        }

        var candidates = new[]
        {
            Path.Combine(AppContext.BaseDirectory, "ffprobe.exe"),
            Path.Combine(AppContext.BaseDirectory, "tools", "ffmpeg", "ffprobe.exe"),
            Path.Combine(AppContext.BaseDirectory, ".tools", "ffmpeg", "ffprobe.exe"),
            Path.Combine(Environment.CurrentDirectory, ".tools", "ffmpeg", "ffprobe.exe")
        };

        foreach (var candidate in candidates)
            if (File.Exists(candidate)) return candidate;

        var path = Environment.GetEnvironmentVariable("PATH") ?? string.Empty;
        foreach (var folder in path.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
        {
            try
            {
                var candidate = Path.Combine(folder.Trim(), "ffprobe.exe");
                if (File.Exists(candidate)) return candidate;
            }
            catch
            {
                // Ignore malformed PATH entries and continue searching.
            }
        }

        return null;
    }
    private static string LastLines(string text, int count)
    {
        var lines = text.Replace("\r", string.Empty).Split('\n', StringSplitOptions.RemoveEmptyEntries);
        return string.Join(Environment.NewLine, lines.TakeLast(count));
    }
}
