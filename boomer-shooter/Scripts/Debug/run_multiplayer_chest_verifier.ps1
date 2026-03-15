param(
    [string]$GodotExe = "C:\Users\18136\Desktop\GODOT\Godot_v4.5.1-stable_win64_console.exe",
    [string]$ProjectPath = "J:\BoomerShooter\boomer-shooter",
    [int]$Port = 7010,
    [int]$TimeoutSec = 60
)

$runnerPath = Join-Path $PSScriptRoot "run_multiplayer_verifier.ps1"
& $runnerPath -Scenario "shared-chest" -GodotExe $GodotExe -ProjectPath $ProjectPath -Port $Port -TimeoutSec $TimeoutSec
