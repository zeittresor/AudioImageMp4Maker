$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
$Project = Join-Path $Root 'src\AudioImageMp4Maker\AudioImageMp4Maker.csproj'
$Tools = Join-Path $Root '.tools'
$PathConfig = Join-Path $Tools 'dependency-paths.ps1'
$Dist = Join-Path $Root 'dist'
$Publish = Join-Path $Dist 'AudioImageMp4Maker-win-x64'
$Zip = Join-Path $Dist 'AudioImageMp4Maker-win-x64.zip'

function Write-BuildProgress([int]$Percent, [string]$Text) {
    Write-Host ('[{0,3}%] {1}' -f $Percent, $Text) -ForegroundColor Cyan
}

function Test-CompatibleMediaTools([string]$FfmpegExe, [string]$FfprobeExe) {
    if (-not $FfmpegExe -or -not $FfprobeExe) { return $false }
    if (-not (Test-Path $FfmpegExe -PathType Leaf) -or -not (Test-Path $FfprobeExe -PathType Leaf)) { return $false }
    try {
        $version = (& $FfmpegExe -version 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0 -or $version -notmatch '(?im)^ffmpeg version\s+n?(\d+)\.') { return $false }
        if ([int]$Matches[1] -lt 5) { return $false }
        $encoders = (& $FfmpegExe -hide_banner -encoders 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0 -or $encoders -notmatch '(?im)^\s*V\S*\s+libx264\s' -or $encoders -notmatch '(?im)^\s*A\S*\s+aac\s') { return $false }
        $scaleHelp = (& $FfmpegExe -hide_banner -h 'filter=scale' 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0 -or $scaleHelp -notmatch 'force_original_aspect_ratio') { return $false }
        & $FfprobeExe -version *> $null
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    }
}

function Load-DependencyPaths {
    if (Test-Path $PathConfig) {
        . $PathConfig
        if ($script:DotNetExePath -and $script:FfmpegExePath -and $script:FfprobeExePath) {
            return @($script:DotNetExePath, $script:FfmpegExePath, $script:FfprobeExePath)
        }
        # Dot-sourced variables may land in local scope depending on invocation context.
        if ($DotNetExePath -and $FfmpegExePath -and $FfprobeExePath) {
            return @($DotNetExePath, $FfmpegExePath, $FfprobeExePath)
        }
    }
    return $null
}

Write-Host ''
Write-Host 'Audio Image MP4 Maker - release build' -ForegroundColor Cyan
Write-BuildProgress 5 'Loading dependency paths...'
$paths = Load-DependencyPaths
if (-not $paths -or -not (Test-Path $paths[0]) -or -not (Test-CompatibleMediaTools $paths[1] $paths[2])) {
    Write-Host 'Build dependencies are missing, outdated, or incompatible. Running setup first...' -ForegroundColor Yellow
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'INSTALL_DEPENDENCIES.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Dependency setup failed.' }
    $paths = Load-DependencyPaths
}

if (-not $paths) { throw 'Dependency path configuration is missing after setup.' }
$DotNet = $paths[0]
$Ffmpeg = $paths[1]
$Ffprobe = $paths[2]

if (-not (Test-Path $DotNet) -or -not (Test-CompatibleMediaTools $Ffmpeg $Ffprobe)) {
    throw 'One or more configured dependencies are missing or incompatible. Run 01_INSTALL_DEPENDENCIES.cmd again.'
}

Write-BuildProgress 15 'Preparing clean release output folder...'
if (Test-Path $Publish) { Remove-Item -Recurse -Force $Publish }
New-Item -ItemType Directory -Force -Path $Publish | Out-Null

Write-BuildProgress 25 'Publishing self-contained Windows x64 application (dotnet output follows)...'
Write-Host "Using .NET: $DotNet" -ForegroundColor DarkGray
& $DotNet publish $Project `
    -c Release `
    -r win-x64 `
    --self-contained true `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -p:EnableCompressionInSingleFile=true `
    -p:PublishReadyToRun=false `
    -o $Publish
if ($LASTEXITCODE -ne 0) { throw 'dotnet publish failed.' }

Write-BuildProgress 75 'Adding FFmpeg, FFprobe, README and license files...'
Copy-Item $Ffmpeg (Join-Path $Publish 'ffmpeg.exe') -Force
Copy-Item $Ffprobe (Join-Path $Publish 'ffprobe.exe') -Force
Copy-Item (Join-Path $Root 'README.md') $Publish -Force
Copy-Item (Join-Path $Root 'LICENSE') $Publish -Force
Copy-Item (Join-Path $Root 'THIRD_PARTY_NOTICES.md') $Publish -Force

Write-BuildProgress 85 'Creating release ZIP package...'
if (Test-Path $Zip) { Remove-Item -Force $Zip }
Compress-Archive -Path (Join-Path $Publish '*') -DestinationPath $Zip -CompressionLevel Optimal

Write-BuildProgress 100 'Release build completed successfully.'
Write-Host ''
Write-Host 'Build completed successfully.' -ForegroundColor Green
Write-Host "Application folder: $Publish"
Write-Host "ZIP package:        $Zip"
