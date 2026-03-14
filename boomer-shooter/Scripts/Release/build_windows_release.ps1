param(
    [string]$GodotExe = "C:\Users\18136\Desktop\GODOT\Godot_v4.6-stable_win64_console.exe",
    [string]$ProjectPath = "J:\BoomerShooter\boomer-shooter",
    [string]$Preset = "Windows Desktop",
    [string]$OutputRoot = "",
    [switch]$SkipZip
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $GodotExe)) {
    throw "Godot executable not found: $GodotExe"
}

if (-not (Test-Path $ProjectPath)) {
    throw "Project path not found: $ProjectPath"
}

$projectFile = Join-Path $ProjectPath "project.godot"
if (-not (Test-Path $projectFile)) {
    throw "project.godot not found under: $ProjectPath"
}

$exportPresetPath = Join-Path $ProjectPath "export_presets.cfg"
if (-not (Test-Path $exportPresetPath)) {
    throw "export_presets.cfg not found under: $ProjectPath"
}

$godotVersion = (& $GodotExe --version | Select-Object -First 1).Trim()
$templateRoot = Join-Path $env:APPDATA "Godot\export_templates\4.6.stable"
$debugTemplate = Join-Path $templateRoot "windows_debug_x86_64.exe"
$releaseTemplate = Join-Path $templateRoot "windows_release_x86_64.exe"
if (-not (Test-Path $debugTemplate) -or -not (Test-Path $releaseTemplate)) {
    throw "Godot export templates for 4.6.stable are missing. Install the Windows export templates under '$templateRoot' before building. Godot reported version: $godotVersion"
}

$projectName = "BoomerShooter"
$version = "dev"
$versionMatch = Select-String -Path $projectFile -Pattern 'config/version="([^"]+)"' | Select-Object -First 1
if ($versionMatch -and $versionMatch.Matches.Count -gt 0) {
    $version = $versionMatch.Matches[0].Groups[1].Value
}

$safeVersion = ($version -replace '[^A-Za-z0-9._-]', '-')
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $ProjectPath "build\windows-release\$safeVersion"
}

$stagingDir = Join-Path $OutputRoot "staging"
$bundleDir = Join-Path $OutputRoot "$projectName-$safeVersion-win64"
$exportDir = Join-Path $stagingDir "export"
$zipPath = Join-Path $OutputRoot "$projectName-$safeVersion-win64.zip"
$exePath = Join-Path $exportDir "$projectName.exe"
$readmeSource = Join-Path $ProjectPath "release_README.txt"
$readmeTarget = Join-Path $bundleDir "README.txt"

New-Item -ItemType Directory -Force -Path $exportDir | Out-Null
New-Item -ItemType Directory -Force -Path $bundleDir | Out-Null

Write-Host "Importing project assets..."
& $GodotExe --headless --path $ProjectPath --import --quit
if ($LASTEXITCODE -ne 0) {
    throw "Godot import step failed with exit code $LASTEXITCODE."
}

Write-Host "Exporting preset '$Preset'..."
& $GodotExe --headless --path $ProjectPath --export-release $Preset $exePath
if ($LASTEXITCODE -ne 0) {
    throw "Godot export failed with exit code $LASTEXITCODE."
}

$bundleContents = @(
    "$projectName.exe",
    "$projectName.pck"
)

foreach ($name in $bundleContents) {
    $source = Join-Path $exportDir $name
    if (-not (Test-Path $source)) {
        throw "Expected exported file missing: $source"
    }
    Copy-Item -Force -Path $source -Destination (Join-Path $bundleDir $name)
}

if (Test-Path $readmeSource) {
    $readmeContent = Get-Content -Raw -Path $readmeSource
    $readmeContent = $readmeContent.Replace("{{VERSION}}", $version)
    Set-Content -Path $readmeTarget -Value $readmeContent -NoNewline
}

if (-not $SkipZip) {
    if (Test-Path $zipPath) {
        Remove-Item -Force $zipPath
    }
    Compress-Archive -Path (Join-Path $bundleDir "*") -DestinationPath $zipPath
}

Write-Host "Release bundle ready:"
Write-Host "  Folder: $bundleDir"
if (-not $SkipZip) {
    Write-Host "  Zip:    $zipPath"
}
