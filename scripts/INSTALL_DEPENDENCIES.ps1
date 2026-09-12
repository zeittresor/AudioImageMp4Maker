$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Root = Split-Path -Parent $PSScriptRoot
$Parent = Split-Path -Parent $Root
$GrandParent = if ($Parent) { Split-Path -Parent $Parent } else { $null }
$SearchBase = if ($GrandParent -and (Test-Path $GrandParent)) { $GrandParent } elseif ($Parent -and (Test-Path $Parent)) { $Parent } else { $Root }

$ProjectTools = Join-Path $Root '.tools'
$ProjectDownloads = Join-Path $ProjectTools 'downloads'
$PathConfig = Join-Path $ProjectTools 'dependency-paths.ps1'
New-Item -ItemType Directory -Force -Path $ProjectTools | Out-Null

$TargetDirectoryNames = @(
    'download', 'downloads', 'temp', 'tmp', 'cache', '.cache',
    'tool', 'tools', '.tools', 'toolchain', 'toolchains',
    'sdk', 'sdks', 'ffmpeg', 'dependencies', 'dependency', 'deps',
    'package', 'packages', '.packages', 'artifacts'
)
$PrunedDirectoryNames = @(
    '.git', '.svn', '.hg', 'node_modules', 'bin', 'obj', 'dist',
    '.vs', '.idea', '__pycache__', 'site-packages', 'venv', '.venv'
)
$DiscoveryMaxDepth = 5

function Write-SetupProgress([int]$Percent, [string]$Text) {
    $p = [Math]::Max(0, [Math]::Min(100, $Percent))
    Write-Host ('[{0,3}%] {1}' -f $p, $Text) -ForegroundColor Cyan
}

function Format-Bytes([Int64]$Bytes) {
    if ($Bytes -ge 1GB) { return ('{0:N1} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N0} MB' -f ($Bytes / 1MB)) }
    return ('{0:N0} KB' -f ($Bytes / 1KB))
}

function Get-DriveForPath([string]$Path) {
    try {
        $full = [IO.Path]::GetFullPath($Path)
        $rootPath = [IO.Path]::GetPathRoot($full)
        if (-not $rootPath) { return $null }
        return [IO.DriveInfo]::new($rootPath)
    } catch {
        return $null
    }
}

function Test-DirectoryWritable([string]$Path) {
    try {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
        $testFile = Join-Path $Path ('.write-test-' + [Guid]::NewGuid().ToString('N') + '.tmp')
        [IO.File]::WriteAllText($testFile, 'ok')
        Remove-Item -Force $testFile
        return $true
    } catch {
        return $false
    }
}

function Show-YesNo([string]$Message, [string]$Title) {
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $result = [System.Windows.Forms.MessageBox]::Show(
            $Message,
            $Title,
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning,
            [System.Windows.Forms.MessageBoxDefaultButton]::Button1
        )
        return ($result -eq [System.Windows.Forms.DialogResult]::Yes)
    } catch {
        Write-Host ''
        Write-Host $Message -ForegroundColor Yellow
        $answer = Read-Host 'Use another drive automatically? [Y/N]'
        return ($answer -match '^(y|yes|j|ja)$')
    }
}

function Show-ErrorDialog([string]$Message, [string]$Title = 'Audio Image MP4 Maker') {
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        [void][System.Windows.Forms.MessageBox]::Show(
            $Message,
            $Title,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
    } catch {
        Write-Host $Message -ForegroundColor Red
    }
}

function Get-AutomaticFallbackRoot([Int64]$RequiredBytes, [string]$ExcludedDriveRoot) {
    $candidates = @()
    foreach ($drive in [IO.DriveInfo]::GetDrives()) {
        try {
            if (-not $drive.IsReady) { continue }
            if ($drive.DriveType -notin @([IO.DriveType]::Fixed, [IO.DriveType]::Removable)) { continue }
            if ($ExcludedDriveRoot -and $drive.RootDirectory.FullName -eq $ExcludedDriveRoot) { continue }
            if ($drive.AvailableFreeSpace -lt $RequiredBytes) { continue }
            $candidates += $drive
        } catch { }
    }

    foreach ($drive in ($candidates | Sort-Object AvailableFreeSpace -Descending)) {
        $candidateRoot = Join-Path $drive.RootDirectory.FullName 'AudioImageMp4Maker_Tools'
        if (Test-DirectoryWritable $candidateRoot) {
            return $candidateRoot
        }
    }
    return $null
}

function Get-StorageRoot([string]$Purpose, [string]$PreferredRoot, [Int64]$RequiredBytes) {
    $drive = Get-DriveForPath $PreferredRoot
    if ($drive -and $drive.IsReady -and $drive.AvailableFreeSpace -ge $RequiredBytes -and (Test-DirectoryWritable $PreferredRoot)) {
        return $PreferredRoot
    }

    $driveName = if ($drive) { $drive.RootDirectory.FullName } else { $PreferredRoot }
    $freeText = if ($drive -and $drive.IsReady) { Format-Bytes $drive.AvailableFreeSpace } else { 'unknown' }
    $neededText = Format-Bytes $RequiredBytes
    $message = @"
Oops - there is not enough free disk space for $Purpose.

Location: $driveName
Free space: $freeText
Recommended free space: at least $neededText

Should I try to use another drive automatically?

No files will be deleted. If you choose No, setup will stop so you can free disk space manually.
"@

    if (-not (Show-YesNo $message 'Audio Image MP4 Maker - Disk space')) {
        throw "Not enough free disk space for $Purpose."
    }

    $excluded = if ($drive) { $drive.RootDirectory.FullName } else { $null }
    $fallback = Get-AutomaticFallbackRoot $RequiredBytes $excluded
    if (-not $fallback) {
        $errorMessage = "I could not find another writable drive with at least $neededText free. Please free some disk space or connect/select a drive with more space, then run setup again."
        Show-ErrorDialog $errorMessage 'Audio Image MP4 Maker - No suitable drive found'
        throw $errorMessage
    }

    Write-Host "Using fallback storage for ${Purpose}: $fallback" -ForegroundColor Yellow
    return $fallback
}

function Add-SearchRoot([System.Collections.Generic.HashSet[string]]$Set, [string]$Path) {
    if (-not $Path) { return }
    try {
        if (Test-Path $Path -PathType Container) {
            [void]$Set.Add([IO.Path]::GetFullPath($Path).TrimEnd('\'))
        }
    } catch { }
}

function Get-TargetedSearchRoots {
    $roots = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    # Highest-priority locations: this project and common per-user caches/download locations.
    Add-SearchRoot $roots $ProjectTools
    Add-SearchRoot $roots $ProjectDownloads
    Add-SearchRoot $roots (Join-Path $env:USERPROFILE 'Downloads')
    Add-SearchRoot $roots $env:TEMP
    Add-SearchRoot $roots $env:TMP
    Add-SearchRoot $roots (Join-Path $env:LOCALAPPDATA 'Temp')
    Add-SearchRoot $roots (Join-Path $env:USERPROFILE '.cache')
    Add-SearchRoot $roots (Join-Path $env:USERPROFILE '.nuget\packages')

    if (-not (Test-Path $SearchBase -PathType Container)) { return @($roots | ForEach-Object { $_ }) }

    # Discover directory NAMES only, up to a modest depth. Once a dependency/cache directory
    # is found, it becomes a search root and its contents are not traversed during discovery.
    # This is dramatically cheaper than recursively inspecting every file under SearchBase.
    $queue = New-Object System.Collections.Queue
    $queue.Enqueue(@($SearchBase, 0))

    while ($queue.Count -gt 0) {
        $entry = $queue.Dequeue()
        $current = [string]$entry[0]
        $depth = [int]$entry[1]
        if ($depth -ge $DiscoveryMaxDepth) { continue }

        try {
            foreach ($dir in [IO.Directory]::EnumerateDirectories($current)) {
                $name = [IO.Path]::GetFileName($dir)
                if ($PrunedDirectoryNames -contains $name.ToLowerInvariant()) { continue }

                if ($TargetDirectoryNames -contains $name.ToLowerInvariant()) {
                    Add-SearchRoot $roots $dir
                    continue
                }

                $queue.Enqueue(@($dir, $depth + 1))
            }
        } catch { }
    }

    return @($roots | ForEach-Object { $_ })
}

function Test-DotNet10Sdk([string]$DotNetExe) {
    if (-not $DotNetExe -or -not (Test-Path $DotNetExe -PathType Leaf)) { return $false }
    try {
        $sdks = & $DotNetExe --list-sdks 2>$null
        return [bool]($sdks | Where-Object { $_ -match '^10\.' } | Select-Object -First 1)
    } catch {
        return $false
    }
}

function Get-FfmpegPairValidation([string]$FfmpegExe, [string]$FfprobeExe) {
    if (-not $FfmpegExe -or -not $FfprobeExe) {
        return [pscustomobject]@{ Compatible = $false; Reason = 'ffmpeg.exe or ffprobe.exe is missing.'; Version = $null }
    }
    if (-not (Test-Path $FfmpegExe -PathType Leaf) -or -not (Test-Path $FfprobeExe -PathType Leaf)) {
        return [pscustomobject]@{ Compatible = $false; Reason = 'ffmpeg.exe or ffprobe.exe does not exist.'; Version = $null }
    }

    try {
        $ffmpegVersionText = (& $FfmpegExe -version 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0) {
            return [pscustomobject]@{ Compatible = $false; Reason = 'ffmpeg -version failed.'; Version = $null }
        }

        # Reject ancient/development builds such as "N-55702-...".  The application relies on
        # modern scale-filter options, H.264/AAC encoders, MP4 faststart and -hide_banner.
        if ($ffmpegVersionText -notmatch '(?im)^ffmpeg version\s+n?(\d+)\.') {
            return [pscustomobject]@{ Compatible = $false; Reason = 'FFmpeg version could not be recognized as a modern stable build (5.x or newer required).'; Version = $null }
        }
        $major = [int]$Matches[1]
        if ($major -lt 5) {
            return [pscustomobject]@{ Compatible = $false; Reason = ("FFmpeg {0}.x is too old; version 5.x or newer is required." -f $major); Version = $major }
        }

        $probeVersionText = (& $FfprobeExe -version 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0 -or $probeVersionText -notmatch '(?im)^ffprobe version\s+n?(\d+)\.') {
            return [pscustomobject]@{ Compatible = $false; Reason = 'ffprobe is missing or its version could not be validated.'; Version = $major }
        }
        $probeMajor = [int]$Matches[1]
        if ($probeMajor -lt 5) {
            return [pscustomobject]@{ Compatible = $false; Reason = ("FFprobe {0}.x is too old; version 5.x or newer is required." -f $probeMajor); Version = $major }
        }

        $encoders = (& $FfmpegExe -hide_banner -encoders 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0) {
            return [pscustomobject]@{ Compatible = $false; Reason = 'FFmpeg does not support the required -hide_banner/encoder query.'; Version = $major }
        }
        if ($encoders -notmatch '(?im)^\s*V\S*\s+libx264\s') {
            return [pscustomobject]@{ Compatible = $false; Reason = 'Required H.264 encoder libx264 is not available.'; Version = $major }
        }
        if ($encoders -notmatch '(?im)^\s*A\S*\s+aac\s') {
            return [pscustomobject]@{ Compatible = $false; Reason = 'Required AAC encoder is not available.'; Version = $major }
        }

        $scaleHelp = (& $FfmpegExe -hide_banner -h 'filter=scale' 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0 -or $scaleHelp -notmatch 'force_original_aspect_ratio') {
            return [pscustomobject]@{ Compatible = $false; Reason = 'The scale filter is too old and lacks force_original_aspect_ratio.'; Version = $major }
        }

        $mp4Help = (& $FfmpegExe -hide_banner -h 'muxer=mp4' 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0 -or $mp4Help -notmatch 'faststart') {
            return [pscustomobject]@{ Compatible = $false; Reason = 'The MP4 muxer does not expose the required faststart option.'; Version = $major }
        }

        return [pscustomobject]@{ Compatible = $true; Reason = 'Compatible.'; Version = $major }
    } catch {
        return [pscustomobject]@{ Compatible = $false; Reason = $_.Exception.Message; Version = $null }
    }
}

function Test-FfmpegPair([string]$FfmpegExe, [string]$FfprobeExe) {
    return [bool](Get-FfmpegPairValidation $FfmpegExe $FfprobeExe).Compatible
}

function Get-ReusableFile([string]$Filter, [string[]]$ExcludePaths = @()) {
    foreach ($searchRoot in $script:SearchRoots) {
        try {
            $items = Get-ChildItem -Path $searchRoot -Filter $Filter -Recurse -File -ErrorAction SilentlyContinue
            foreach ($item in $items) {
                $excluded = $false
                foreach ($exclude in $ExcludePaths) {
                    if ($exclude -and $item.FullName.StartsWith($exclude, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $excluded = $true
                        break
                    }
                }
                if (-not $excluded) { return $item }
            }
        } catch { }
    }
    return $null
}

function Find-ReusableDotNet10 {
    # Prefer an already installed/available SDK because that needs no copy and no extra disk space.
    $command = Get-Command dotnet.exe -ErrorAction SilentlyContinue
    if ($command -and (Test-DotNet10Sdk $command.Source)) { return $command.Source }

    $common = @(
        (Join-Path $env:ProgramFiles 'dotnet\dotnet.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'dotnet\dotnet.exe')
    ) | Where-Object { $_ }
    foreach ($candidate in $common) {
        if (Test-DotNet10Sdk $candidate) { return $candidate }
    }

    foreach ($searchRoot in $script:SearchRoots) {
        try {
            $candidates = Get-ChildItem -Path $searchRoot -Filter 'dotnet.exe' -Recurse -File -ErrorAction SilentlyContinue
            foreach ($candidate in $candidates) {
                if (Test-DotNet10Sdk $candidate.FullName) { return $candidate.FullName }
            }
        } catch { }
    }
    return $null
}

function Find-ReusableFfmpegPair {
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    $ffmpegCommand = Get-Command ffmpeg.exe -ErrorAction SilentlyContinue
    if ($ffmpegCommand) {
        $probe = Join-Path (Split-Path -Parent $ffmpegCommand.Source) 'ffprobe.exe'
        [void]$seen.Add($ffmpegCommand.Source)
        $validation = Get-FfmpegPairValidation $ffmpegCommand.Source $probe
        if ($validation.Compatible) {
            return @($ffmpegCommand.Source, $probe)
        }
        Write-Host "Ignoring incompatible FFmpeg: $($ffmpegCommand.Source)" -ForegroundColor DarkYellow
        Write-Host "  Reason: $($validation.Reason)" -ForegroundColor DarkGray
    }

    foreach ($searchRoot in $script:SearchRoots) {
        try {
            $candidates = Get-ChildItem -Path $searchRoot -Filter 'ffmpeg.exe' -Recurse -File -ErrorAction SilentlyContinue
            foreach ($candidate in $candidates) {
                if (-not $seen.Add($candidate.FullName)) { continue }
                $probe = Join-Path (Split-Path -Parent $candidate.FullName) 'ffprobe.exe'
                $validation = Get-FfmpegPairValidation $candidate.FullName $probe
                if ($validation.Compatible) {
                    return @($candidate.FullName, $probe)
                }
                Write-Host "Ignoring incompatible FFmpeg: $($candidate.FullName)" -ForegroundColor DarkYellow
                Write-Host "  Reason: $($validation.Reason)" -ForegroundColor DarkGray
            }
        } catch { }
    }
    return $null
}

function Install-DotNetFromArchive([string]$ArchivePath, [string]$InstallDir) {
    Write-Host "Reusing .NET SDK archive: $ArchivePath" -ForegroundColor DarkCyan
    if (Test-Path $InstallDir) { Remove-Item -Recurse -Force $InstallDir }
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    Expand-Archive -Path $ArchivePath -DestinationPath $InstallDir -Force
    $exe = Join-Path $InstallDir 'dotnet.exe'
    if (Test-DotNet10Sdk $exe) { return $exe }
    return $null
}

function Install-FfmpegFromArchive([string]$ArchivePath, [string]$InstallDir, [string]$WorkDir) {
    Write-Host "Testing/extracting FFmpeg archive: $ArchivePath" -ForegroundColor DarkCyan
    $ExtractDir = Join-Path $WorkDir 'ffmpeg-extracted'
    try {
        if (Test-Path $ExtractDir) { Remove-Item -Recurse -Force $ExtractDir }
        New-Item -ItemType Directory -Force -Path $ExtractDir, $InstallDir | Out-Null
        Expand-Archive -Path $ArchivePath -DestinationPath $ExtractDir -Force -ErrorAction Stop
        $FoundFfmpeg = Get-ChildItem -Path $ExtractDir -Filter 'ffmpeg.exe' -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
        $FoundFfprobe = Get-ChildItem -Path $ExtractDir -Filter 'ffprobe.exe' -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $FoundFfmpeg -or -not $FoundFfprobe) { return $null }
        $destFfmpeg = Join-Path $InstallDir 'ffmpeg.exe'
        $destFfprobe = Join-Path $InstallDir 'ffprobe.exe'
        Copy-Item $FoundFfmpeg.FullName $destFfmpeg -Force
        Copy-Item $FoundFfprobe.FullName $destFfprobe -Force
        if (Test-FfmpegPair $destFfmpeg $destFfprobe) { return @($destFfmpeg, $destFfprobe) }
        return $null
    } catch {
        Write-Host "Archive cannot be reused: $($_.Exception.Message)" -ForegroundColor DarkYellow
        return $null
    } finally {
        if (Test-Path $ExtractDir) {
            try { Remove-Item -Recurse -Force $ExtractDir -ErrorAction SilentlyContinue } catch { }
        }
    }
}

function Get-LatestGyanGithubAssetUrl {
    # Gyan mirrors its release builds on GitHub.  GitHub's CDN is often much faster than
    # downloading the large ZIP directly from gyan.dev, especially from Europe.
    $tag = $null
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) {
        try {
            $effective = (& $curl.Source -L -sS --connect-timeout 10 --max-time 20 -o NUL -w '%{url_effective}' 'https://github.com/GyanD/codexffmpeg/releases/latest' 2>$null | Out-String).Trim()
            if ($LASTEXITCODE -eq 0 -and $effective -match '/tag/([^/?#]+)') {
                $tag = $Matches[1]
            }
        } catch { }
    }

    if (-not $tag) {
        try {
            $versionResponse = Invoke-WebRequest -UseBasicParsing -Uri 'https://www.gyan.dev/ffmpeg/builds/release-version' -TimeoutSec 15
            $candidate = ($versionResponse.Content | Out-String).Trim()
            if ($candidate -match '^\d+\.\d+(?:\.\d+)?$') { $tag = $candidate }
        } catch { }
    }

    if (-not $tag) { return $null }
    return "https://github.com/GyanD/codexffmpeg/releases/download/$tag/ffmpeg-$tag-essentials_build.zip"
}

function Invoke-LargeFileDownload([string[]]$Urls, [string]$Destination) {
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    $part = $Destination + '.part'
    $sourceNumber = 0

    foreach ($url in ($Urls | Where-Object { $_ } | Select-Object -Unique)) {
        $sourceNumber++
        if (Test-Path $part) { Remove-Item -Force $part -ErrorAction SilentlyContinue }
        Write-Host ''
        Write-Host ("Download source {0}: {1}" -f $sourceNumber, $url) -ForegroundColor Cyan

        if ($curl) {
            Write-Host 'Downloader: Windows curl.exe (live transfer statistics below).' -ForegroundColor DarkCyan
            Write-Host 'If transfer speed stays below 128 KiB/s for 25 seconds, setup switches source automatically.' -ForegroundColor DarkGray
            try {
                & $curl.Source --fail --location --connect-timeout 15 --retry 2 --retry-delay 2 --speed-limit 131072 --speed-time 25 --max-time 1200 --output $part $url
                $code = $LASTEXITCODE
                if ($code -eq 0 -and (Test-Path $part -PathType Leaf) -and (Get-Item $part).Length -gt 1MB) {
                    Move-Item -Force $part $Destination
                    return $true
                }
                Write-Host ("Source failed or was too slow (curl exit code {0}); trying the next source..." -f $code) -ForegroundColor Yellow
            } catch {
                Write-Host "Source failed: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        } else {
            Write-Host 'curl.exe is not available; using PowerShell web download fallback.' -ForegroundColor Yellow
            try {
                Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $part -TimeoutSec 1200
                if ((Test-Path $part -PathType Leaf) -and (Get-Item $part).Length -gt 1MB) {
                    Move-Item -Force $part $Destination
                    return $true
                }
            } catch {
                Write-Host "Source failed: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
    }

    if (Test-Path $part) { Remove-Item -Force $part -ErrorAction SilentlyContinue }
    return $false
}

function Save-DependencyPaths([string]$DotNetExe, [string]$FfmpegExe, [string]$FfprobeExe) {
    function Escape-Ps([string]$Value) { return $Value.Replace("'", "''") }
    $content = @(
        '# Auto-generated by INSTALL_DEPENDENCIES.ps1. Do not edit unless you know what you are doing.',
        ('$DotNetExePath = ''' + (Escape-Ps $DotNetExe) + ''''),
        ('$FfmpegExePath = ''' + (Escape-Ps $FfmpegExe) + ''''),
        ('$FfprobeExePath = ''' + (Escape-Ps $FfprobeExe) + '''')
    ) -join [Environment]::NewLine
    Set-Content -Path $PathConfig -Value $content -Encoding UTF8
}

Write-Host ''
Write-Host 'Audio Image MP4 Maker - dependency setup' -ForegroundColor Cyan
Write-Host 'Existing compatible tools are reused before anything is downloaded.'
Write-Host "Reuse discovery base: $SearchBase"
Write-Host 'Search mode: targeted dependency/cache folders only; no full file scan of the whole tree.'
Write-Host 'If the current disk is too full, setup can automatically use another drive.'
Write-Host ''

Write-SetupProgress 5 'Discovering likely Downloads/Temp/Cache/Tools/SDK/FFmpeg locations...'
$script:SearchRoots = Get-TargetedSearchRoots
Write-SetupProgress 10 ("Targeted reuse locations ready: {0} folder(s)." -f $script:SearchRoots.Count)

# Approximate conservative requirements. They include download + extraction headroom.
$DotNetRequiredSpace = 3GB
$FfmpegRequiredSpace = 1GB

# -----------------------------------------------------------------------------
# 1/2 - .NET 10 SDK
# -----------------------------------------------------------------------------
Write-SetupProgress 15 'Checking for an existing compatible .NET 10 SDK...'
$DotNetExe = Find-ReusableDotNet10
if ($DotNetExe) {
    Write-Host "Found compatible .NET 10 SDK: $DotNetExe" -ForegroundColor Green
    Write-Host 'SDK status: ready; no SDK download or duplicate copy is needed.' -ForegroundColor DarkGreen
    Write-SetupProgress 55 '.NET SDK ready.'
} else {
    Write-Host 'SDK status: no compatible .NET 10 SDK installation was found.' -ForegroundColor Yellow
    Write-SetupProgress 22 'Checking for a reusable .NET 10 SDK archive...'
    $SdkArchive = Get-ReusableFile 'dotnet-sdk-10*-win-x64.zip'

    Write-SetupProgress 26 'Checking for a reusable Microsoft dotnet-install helper script...'
    $ReusableInstallScript = Get-ReusableFile 'dotnet-install.ps1'
    if ($ReusableInstallScript) {
        Write-Host "Installer helper status: reusable dotnet-install.ps1 found at $($ReusableInstallScript.FullName)" -ForegroundColor DarkCyan
    } else {
        Write-Host 'Installer helper status: no reusable dotnet-install.ps1 found.' -ForegroundColor DarkGray
    }

    $DotNetStorageRoot = Get-StorageRoot '.NET 10 SDK installation and extraction' $ProjectTools $DotNetRequiredSpace
    $DotNetDir = Join-Path $DotNetStorageRoot 'dotnet'
    $DotNetDownloads = Join-Path $DotNetStorageRoot 'downloads'
    New-Item -ItemType Directory -Force -Path $DotNetDownloads | Out-Null

    if ($SdkArchive) {
        Write-Host "SDK package status: reusable archive found at $($SdkArchive.FullName)" -ForegroundColor Green
        Write-SetupProgress 35 'Extracting reusable .NET 10 SDK archive...'
        $DotNetExe = Install-DotNetFromArchive $SdkArchive.FullName $DotNetDir
        if (-not $DotNetExe) { throw 'The reused .NET SDK archive did not validate correctly.' }
        Write-Host 'SDK status: reusable .NET 10 archive installed successfully.' -ForegroundColor Green
    } else {
        Write-Host 'SDK package status: no reusable SDK archive found; the SDK itself must be downloaded.' -ForegroundColor Yellow
        $InstallScript = Join-Path $DotNetDownloads 'dotnet-install.ps1'
        if ($ReusableInstallScript) {
            $sourceHelper = [IO.Path]::GetFullPath($ReusableInstallScript.FullName)
            $targetHelper = [IO.Path]::GetFullPath($InstallScript)
            if (-not [string]::Equals($sourceHelper, $targetHelper, [System.StringComparison]::OrdinalIgnoreCase)) {
                Copy-Item $ReusableInstallScript.FullName $InstallScript -Force
            }
        } elseif (-not (Test-Path $InstallScript)) {
            Write-SetupProgress 31 'Downloading the small Microsoft dotnet-install helper script...'
            Invoke-WebRequest -Uri 'https://dot.net/v1/dotnet-install.ps1' -OutFile $InstallScript
        }

        if (Test-Path $DotNetDir) { Remove-Item -Recurse -Force $DotNetDir }
        New-Item -ItemType Directory -Force -Path $DotNetDir | Out-Null

        # dotnet-install normally uses %TEMP%. Force it onto the selected storage root so a full
        # system TEMP drive cannot break an otherwise valid installation.
        $PrivateTemp = Join-Path $DotNetStorageRoot 'temp'
        New-Item -ItemType Directory -Force -Path $PrivateTemp | Out-Null
        $OldTemp = $env:TEMP
        $OldTmp = $env:TMP
        try {
            $env:TEMP = $PrivateTemp
            $env:TMP = $PrivateTemp
            Write-SetupProgress 35 '.NET SDK download/install started (Microsoft installer output follows)...'
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $InstallScript -Channel '10.0' -InstallDir $DotNetDir -NoPath
            $installExitCode = $LASTEXITCODE
        } finally {
            $env:TEMP = $OldTemp
            $env:TMP = $OldTmp
        }

        $DotNetExe = Join-Path $DotNetDir 'dotnet.exe'
        if ($installExitCode -ne 0 -or -not (Test-DotNet10Sdk $DotNetExe)) {
            throw '.NET SDK installation failed.'
        }
        Write-Host 'SDK status: .NET 10 SDK downloaded and installed successfully.' -ForegroundColor Green
    }
    Write-SetupProgress 55 '.NET SDK ready.'
}

# -----------------------------------------------------------------------------
# 2/2 - FFmpeg + FFprobe
# -----------------------------------------------------------------------------
Write-SetupProgress 62 'Checking for an existing FFmpeg/FFprobe pair...'
$pair = Find-ReusableFfmpegPair
if ($pair) {
    $FfmpegExe = $pair[0]
    $FfprobeExe = $pair[1]
    Write-Host "FFmpeg status: reusable executable found at $FfmpegExe" -ForegroundColor Green
    Write-Host "FFprobe status: reusable executable found at $FfprobeExe" -ForegroundColor Green
    Write-Host 'Media tools status: ready; no download or duplicate copy is needed.' -ForegroundColor DarkGreen
    Write-SetupProgress 88 'FFmpeg/FFprobe ready.'
} else {
    Write-Host 'Media tools status: no compatible FFmpeg/FFprobe pair found.' -ForegroundColor Yellow
    Write-SetupProgress 68 'Checking for a reusable FFmpeg essentials archive...'
    $FfmpegZip = Get-ReusableFile 'ffmpeg-release-essentials.zip'
    if (-not $FfmpegZip) { $FfmpegZip = Get-ReusableFile '*ffmpeg*essentials*.zip' }

    $FfmpegStorageRoot = Get-StorageRoot 'FFmpeg download and extraction' $ProjectTools $FfmpegRequiredSpace
    $FfmpegDir = Join-Path $FfmpegStorageRoot 'ffmpeg'
    $FfmpegDownloads = Join-Path $FfmpegStorageRoot 'downloads'
    New-Item -ItemType Directory -Force -Path $FfmpegDownloads | Out-Null

    $installedPair = $null
    if ($FfmpegZip) {
        Write-Host "FFmpeg package status: reusable archive found at $($FfmpegZip.FullName)" -ForegroundColor Green
        Write-SetupProgress 75 'Testing/extracting reusable FFmpeg archive...'
        $installedPair = Install-FfmpegFromArchive $FfmpegZip.FullName $FfmpegDir $FfmpegDownloads
        if ($installedPair) {
            Write-Host 'Media tools status: reusable FFmpeg archive is modern and compatible.' -ForegroundColor Green
        } else {
            Write-Host 'FFmpeg package status: the reusable archive was too old or incompatible; it will not be used.' -ForegroundColor Yellow
        }
    } else {
        Write-Host 'FFmpeg package status: no reusable archive found.' -ForegroundColor DarkGray
    }

    if (-not $installedPair) {
        $DownloadedZip = Join-Path $FfmpegDownloads 'ffmpeg-release-essentials.zip'
        $GithubMirror = Get-LatestGyanGithubAssetUrl
        $DownloadSources = @(
            $GithubMirror,
            'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip',
            'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-n8.1-latest-win64-gpl-8.1.zip'
        ) | Where-Object { $_ }

        Write-Host 'FFmpeg package status: downloading a current compatible build.' -ForegroundColor Yellow
        if ($GithubMirror) {
            Write-Host 'Fast source preference: Gyan GitHub release mirror -> gyan.dev -> BtbN GitHub fallback.' -ForegroundColor DarkCyan
        } else {
            Write-Host 'Fast source preference: gyan.dev -> BtbN GitHub fallback.' -ForegroundColor DarkCyan
        }
        Write-SetupProgress 78 'Downloading current FFmpeg build with automatic speed fallback...'
        if (-not (Invoke-LargeFileDownload $DownloadSources $DownloadedZip)) {
            throw 'FFmpeg download failed from all configured sources.'
        }
        Write-SetupProgress 84 'Extracting and validating downloaded FFmpeg build...'
        $installedPair = Install-FfmpegFromArchive $DownloadedZip $FfmpegDir $FfmpegDownloads
        if (-not $installedPair) { throw 'The downloaded FFmpeg build failed compatibility validation.' }
    }

    $FfmpegExe = $installedPair[0]
    $FfprobeExe = $installedPair[1]
    Write-SetupProgress 88 'FFmpeg/FFprobe ready.'
}

Write-SetupProgress 92 'Validating dependency executables...'
if (-not (Test-DotNet10Sdk $DotNetExe)) { throw '.NET 10 SDK validation failed.' }
if (-not (Test-FfmpegPair $FfmpegExe $FfprobeExe)) { throw 'FFmpeg/FFprobe validation failed.' }

Write-SetupProgress 96 'Saving reusable dependency paths...'
Save-DependencyPaths $DotNetExe $FfmpegExe $FfprobeExe

Write-SetupProgress 100 'Dependency setup completed successfully.'
Write-Host ''
Write-Host 'Dependencies are ready.' -ForegroundColor Green
Write-Host "DotNet:       $DotNetExe"
Write-Host "FFmpeg:       $FfmpegExe"
Write-Host "FFprobe:      $FfprobeExe"
Write-Host "Path config:  $PathConfig"
Write-Host "Discovery:    targeted folders below $SearchBase (max depth $DiscoveryMaxDepth)"
