param(
    [string]$GodotExe = "C:\Users\18136\Desktop\GODOT\Godot_v4.5.1-stable_win64_console.exe",
    [string]$ProjectPath = "J:\BoomerShooter\boomer-shooter",
    [int]$Port = 7010,
    [int]$TimeoutSec = 60
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $GodotExe)) {
    throw "Godot executable not found: $GodotExe"
}

if (-not (Test-Path $ProjectPath)) {
    throw "Project path not found: $ProjectPath"
}

$runId = Get-Date -Format "yyyyMMdd_HHmmss"
$verifyDir = Join-Path $ProjectPath ".tmp\mp_verify_$runId"
$null = New-Item -ItemType Directory -Force -Path $verifyDir

$hostLog = Join-Path $verifyDir "host.log"
$hostErr = Join-Path $verifyDir "host.err.log"
$clientLog = Join-Path $verifyDir "client.log"
$clientErr = Join-Path $verifyDir "client.err.log"
$launcherLog = Join-Path $verifyDir "launcher.log"

$engineArgs = @(
    "--headless",
    "--path", $ProjectPath
)

$commonUserArgs = @(
    "--net-port", "$Port",
    "--net-auto-start", "1",
    "--verify-shared-chest", "1",
    "--verify-dir", $verifyDir,
    "--verify-timeout", "$TimeoutSec"
)

$hostArgs = $engineArgs + @(
    "--"
) + @(
    "--net-role", "host",
    "--verify-role", "host"
) + $commonUserArgs

$clientArgs = $engineArgs + @(
    "--"
) + @(
    "--net-role", "client",
    "--net-host", "127.0.0.1",
    "--verify-role", "client"
) + $commonUserArgs

try {
    "Launching host verifier..." | Set-Content -Path $launcherLog
    $hostProcess = Start-Process -FilePath $GodotExe -ArgumentList $hostArgs -PassThru -RedirectStandardOutput $hostLog -RedirectStandardError $hostErr
    "Host PID: $($hostProcess.Id)" | Add-Content -Path $launcherLog
    Start-Sleep -Seconds 2
    "Launching client verifier..." | Add-Content -Path $launcherLog
    $clientProcess = Start-Process -FilePath $GodotExe -ArgumentList $clientArgs -PassThru -RedirectStandardOutput $clientLog -RedirectStandardError $clientErr
    "Client PID: $($clientProcess.Id)" | Add-Content -Path $launcherLog
}
catch {
    "Launcher error: $($_.Exception.Message)" | Add-Content -Path $launcherLog
    throw
}

$deadline = (Get-Date).AddSeconds($TimeoutSec)
while ((-not $hostProcess.HasExited -or -not $clientProcess.HasExited) -and (Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 500
}

if (-not $hostProcess.HasExited) {
    $hostProcess.Kill()
    throw "Host did not exit before timeout. Logs: $hostLog , $hostErr"
}

if (-not $clientProcess.HasExited) {
    $clientProcess.Kill()
    throw "Client did not exit before timeout. Logs: $clientLog , $clientErr"
}

if ($hostProcess.ExitCode -ne 0) {
    "Host exit code: $($hostProcess.ExitCode)" | Add-Content -Path $launcherLog
    throw "Host verifier failed with exit code $($hostProcess.ExitCode). Logs: $hostLog , $hostErr"
}

if ($clientProcess.ExitCode -ne 0) {
    "Client exit code: $($clientProcess.ExitCode)" | Add-Content -Path $launcherLog
    throw "Client verifier failed with exit code $($clientProcess.ExitCode). Logs: $clientLog , $clientErr"
}

$hostInitialPath = Join-Path $verifyDir "host_initial.json"
$clientInitialPath = Join-Path $verifyDir "client_initial.json"
$hostAfterPath = Join-Path $verifyDir "host_after.json"
$clientAfterPath = Join-Path $verifyDir "client_after.json"

foreach ($path in @($hostInitialPath, $clientInitialPath, $hostAfterPath, $clientAfterPath)) {
    if (-not (Test-Path $path)) {
        throw "Expected verifier output missing: $path"
    }
}

$hostInitial = Get-Content $hostInitialPath -Raw | ConvertFrom-Json
$clientInitial = Get-Content $clientInitialPath -Raw | ConvertFrom-Json
$hostAfter = Get-Content $hostAfterPath -Raw | ConvertFrom-Json
$clientAfter = Get-Content $clientAfterPath -Raw | ConvertFrom-Json

$hostInitialItems = @($hostInitial.items)
$clientInitialItems = @($clientInitial.items)
$hostAfterItems = @($hostAfter.items)
$clientAfterItems = @($clientAfter.items)

if (($hostInitialItems -join "|") -ne ($clientInitialItems -join "|")) {
    throw "Initial chest contents differ between host and client. Output dir: $verifyDir"
}

if (($hostAfterItems -join "|") -ne ($clientAfterItems -join "|")) {
    throw "Post-loot chest contents differ between host and client. Output dir: $verifyDir"
}

if (($hostInitialItems -join "|") -eq ($hostAfterItems -join "|")) {
    throw "Host chest contents did not change after transfer. Output dir: $verifyDir"
}

Write-Host "Multiplayer chest verification PASS"
Write-Host "Output dir: $verifyDir"
"PASS" | Add-Content -Path $launcherLog
