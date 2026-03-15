param(
    [string]$Scenario = "spawn-floor-stability",
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

$scenarioKey = $Scenario.Trim().ToLowerInvariant()
$runId = Get-Date -Format "yyyyMMdd_HHmmss"
$verifyDir = Join-Path $ProjectPath ".tmp\mp_verify_$($scenarioKey.Replace('-', '_'))_$runId"
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
    "--verify-scenario", $scenarioKey,
    "--verify-dir", $verifyDir,
    "--verify-timeout", "$TimeoutSec"
)

$hostArgs = $engineArgs + @("--") + @(
    "--net-role", "host",
    "--verify-role", "host"
) + $commonUserArgs

$clientArgs = $engineArgs + @("--") + @(
    "--net-role", "client",
    "--net-host", "127.0.0.1",
    "--verify-role", "client"
) + $commonUserArgs

try {
    "Launching host verifier for scenario '$scenarioKey'..." | Set-Content -Path $launcherLog
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

$hostTimedOut = -not $hostProcess.HasExited
$clientTimedOut = -not $clientProcess.HasExited

if (-not $hostTimedOut -and $hostProcess.ExitCode -ne 0) {
    "Host exit code: $($hostProcess.ExitCode)" | Add-Content -Path $launcherLog
    throw "Host verifier failed with exit code $($hostProcess.ExitCode). Logs: $hostLog , $hostErr"
}

if (-not $clientTimedOut -and $clientProcess.ExitCode -ne 0) {
    "Client exit code: $($clientProcess.ExitCode)" | Add-Content -Path $launcherLog
    throw "Client verifier failed with exit code $($clientProcess.ExitCode). Logs: $clientLog , $clientErr"
}

switch ($scenarioKey) {
    "shared-chest" {
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
    }
    "spawn-floor-stability" {
        $hostResultPath = Join-Path $verifyDir "host_spawn_floor.json"
        $clientResultPath = Join-Path $verifyDir "client_spawn_floor.json"
        foreach ($path in @($hostResultPath, $clientResultPath)) {
            if (-not (Test-Path $path)) {
                throw "Expected verifier output missing: $path"
            }
        }

        $hostResult = Get-Content $hostResultPath -Raw | ConvertFrom-Json
        $clientResult = Get-Content $clientResultPath -Raw | ConvertFrom-Json

        if (-not $hostResult.passed) {
            throw "Host spawn/floor stability verification failed. Output dir: $verifyDir"
        }

        if (-not $clientResult.passed) {
            throw "Client spawn/floor stability verification failed. Output dir: $verifyDir"
        }
    }
    "player-replication" {
        $hostRosterPath = Join-Path $verifyDir "host_player_roster.json"
        $clientRosterPath = Join-Path $verifyDir "client_player_roster.json"
        $hostClientPath = Join-Path $verifyDir "host_client_replication.json"
        $clientHostPath = Join-Path $verifyDir "client_host_replication.json"

        foreach ($path in @($hostRosterPath, $clientRosterPath, $hostClientPath, $clientHostPath)) {
            if (-not (Test-Path $path)) {
                throw "Expected verifier output missing: $path"
            }
        }

        $hostRoster = Get-Content $hostRosterPath -Raw | ConvertFrom-Json
        $clientRoster = Get-Content $clientRosterPath -Raw | ConvertFrom-Json
        $hostClient = Get-Content $hostClientPath -Raw | ConvertFrom-Json
        $clientHost = Get-Content $clientHostPath -Raw | ConvertFrom-Json

        if (@($hostRoster.players).Count -lt 2) {
            throw "Host roster did not contain both players. Output dir: $verifyDir"
        }

        if (@($clientRoster.players).Count -lt 2) {
            throw "Client roster did not contain both players. Output dir: $verifyDir"
        }

        if (-not $hostClient.passed) {
            throw "Host did not observe replicated client movement. Output dir: $verifyDir"
        }

        if (-not $clientHost.passed) {
            throw "Client did not observe replicated host movement. Output dir: $verifyDir"
        }
    }
    "player-health-replication" {
        $hostHealthPath = Join-Path $verifyDir "host_player_health.json"
        $clientHealthPath = Join-Path $verifyDir "client_player_health.json"
        foreach ($path in @($hostHealthPath, $clientHealthPath)) {
            if (-not (Test-Path $path)) {
                throw "Expected verifier output missing: $path"
            }
        }

        $hostHealth = Get-Content $hostHealthPath -Raw | ConvertFrom-Json
        $clientHealth = Get-Content $clientHealthPath -Raw | ConvertFrom-Json

        if (-not $hostHealth.passed) {
            throw "Host did not observe authoritative player health damage. Output dir: $verifyDir"
        }
        if (-not $clientHealth.passed) {
            throw "Client did not converge on replicated player health. Output dir: $verifyDir"
        }
    }
    "client-disconnect" {
        $hostDisconnectPath = Join-Path $verifyDir "host_client_disconnect.json"
        $clientDisconnectPath = Join-Path $verifyDir "client_client_disconnect.json"
        foreach ($path in @($hostDisconnectPath, $clientDisconnectPath)) {
            if (-not (Test-Path $path)) {
                throw "Expected verifier output missing: $path"
            }
        }

        $hostDisconnect = Get-Content $hostDisconnectPath -Raw | ConvertFrom-Json
        $clientDisconnect = Get-Content $clientDisconnectPath -Raw | ConvertFrom-Json

        if (-not $clientDisconnect.requested) {
            throw "Client did not request disconnect. Output dir: $verifyDir"
        }
        if (-not $hostDisconnect.passed) {
            throw "Host did not observe roster cleanup after client disconnect. Output dir: $verifyDir"
        }
    }
    "door-replication" {
        $hostDoorPath = Join-Path $verifyDir "host_door_replication.json"
        $clientDoorPath = Join-Path $verifyDir "client_door_replication.json"
        foreach ($path in @($hostDoorPath, $clientDoorPath)) {
            if (-not (Test-Path $path)) {
                throw "Expected verifier output missing: $path"
            }
        }

        $hostDoor = Get-Content $hostDoorPath -Raw | ConvertFrom-Json
        $clientDoor = Get-Content $clientDoorPath -Raw | ConvertFrom-Json

        if (-not $hostDoor.passed) {
            throw "Host did not observe the replicated door open. Output dir: $verifyDir"
        }

        if (-not $clientDoor.passed) {
            throw "Client did not observe the replicated door open. Output dir: $verifyDir"
        }
    }
    "weapon-state-sync" {
        $hostFirePath = Join-Path $verifyDir "host_weapon_after_fire.json"
        $clientFirePath = Join-Path $verifyDir "client_weapon_after_fire.json"
        $hostReloadPath = Join-Path $verifyDir "host_weapon_after_reload.json"
        $clientReloadPath = Join-Path $verifyDir "client_weapon_after_reload.json"

        foreach ($path in @($hostFirePath, $clientFirePath, $hostReloadPath, $clientReloadPath)) {
            if (-not (Test-Path $path)) {
                throw "Expected verifier output missing: $path"
            }
        }

        $hostFire = Get-Content $hostFirePath -Raw | ConvertFrom-Json
        $clientFire = Get-Content $clientFirePath -Raw | ConvertFrom-Json
        $hostReload = Get-Content $hostReloadPath -Raw | ConvertFrom-Json
        $clientReload = Get-Content $clientReloadPath -Raw | ConvertFrom-Json

        if (-not $hostFire.passed) {
            throw "Host did not observe authoritative weapon fire state. Output dir: $verifyDir"
        }
        if (-not $clientFire.passed) {
            throw "Client did not converge on authoritative weapon fire state. Output dir: $verifyDir"
        }
        if (-not $hostReload.passed) {
            throw "Host did not observe authoritative weapon reload state. Output dir: $verifyDir"
        }
        if (-not $clientReload.passed) {
            throw "Client did not converge on authoritative weapon reload state. Output dir: $verifyDir"
        }
    }
    "weapon-visual-replication" {
        $clientVisualPath = Join-Path $verifyDir "client_weapon_visuals.json"
        if (-not (Test-Path $clientVisualPath)) {
            throw "Expected verifier output missing: $clientVisualPath"
        }
        $clientVisual = Get-Content $clientVisualPath -Raw | ConvertFrom-Json
        if (-not $clientVisual.passed) {
            throw "Client did not observe both replicated weapon visuals. Output dir: $verifyDir"
        }
    }
    "enemy-damage-replication" {
        $hostEnemyPath = Join-Path $verifyDir "host_enemy_damage.json"
        $clientEnemyPath = Join-Path $verifyDir "client_enemy_damage.json"
        foreach ($path in @($hostEnemyPath, $clientEnemyPath)) {
            if (-not (Test-Path $path)) {
                throw "Expected verifier output missing: $path"
            }
        }

        $hostEnemy = Get-Content $hostEnemyPath -Raw | ConvertFrom-Json
        $clientEnemy = Get-Content $clientEnemyPath -Raw | ConvertFrom-Json

        if (-not $hostEnemy.passed) {
            throw "Host did not observe authoritative enemy damage. Output dir: $verifyDir"
        }
        if (-not $clientEnemy.passed) {
            throw "Client did not converge on replicated enemy damage. Output dir: $verifyDir"
        }
    }
    "enemy-death-replication" {
        $hostEnemyDeathPath = Join-Path $verifyDir "host_enemy_death.json"
        $clientEnemyDeathPath = Join-Path $verifyDir "client_enemy_death.json"
        foreach ($path in @($hostEnemyDeathPath, $clientEnemyDeathPath)) {
            if (-not (Test-Path $path)) {
                throw "Expected verifier output missing: $path"
            }
        }

        $hostEnemyDeath = Get-Content $hostEnemyDeathPath -Raw | ConvertFrom-Json
        $clientEnemyDeath = Get-Content $clientEnemyDeathPath -Raw | ConvertFrom-Json

        if (-not $hostEnemyDeath.passed) {
            throw "Host did not observe authoritative enemy death/despawn. Output dir: $verifyDir"
        }
        if (-not $clientEnemyDeath.passed) {
            throw "Client did not observe replicated enemy death/despawn. Output dir: $verifyDir"
        }
    }
    default {
        throw "Unsupported scenario: $scenarioKey"
    }
}

if ($hostTimedOut -or $clientTimedOut) {
    if ($scenarioKey -in @("weapon-state-sync", "client-disconnect")) {
        if ($hostTimedOut) {
            $hostProcess.Kill()
            "Host process was still running after successful validation; killed after artifact verification." | Add-Content -Path $launcherLog
        }
        if ($clientTimedOut) {
            $clientProcess.Kill()
            "Client process was still running after successful validation; killed after artifact verification." | Add-Content -Path $launcherLog
        }
    }
    else {
        if ($hostTimedOut) {
            $hostProcess.Kill()
            throw "Host did not exit before timeout. Logs: $hostLog , $hostErr"
        }
        if ($clientTimedOut) {
            $clientProcess.Kill()
            throw "Client did not exit before timeout. Logs: $clientLog , $clientErr"
        }
    }
}

$label = switch ($scenarioKey) {
    "shared-chest" { "Multiplayer shared chest verification PASS" }
    "spawn-floor-stability" { "Multiplayer spawn/floor stability verification PASS" }
    "player-replication" { "Multiplayer player replication verification PASS" }
    "player-health-replication" { "Multiplayer player health replication verification PASS" }
    "client-disconnect" { "Multiplayer client disconnect verification PASS" }
    "door-replication" { "Multiplayer door replication verification PASS" }
    "weapon-state-sync" { "Multiplayer weapon state sync verification PASS" }
    "weapon-visual-replication" { "Multiplayer weapon visual replication verification PASS" }
    "enemy-damage-replication" { "Multiplayer enemy damage replication verification PASS" }
    "enemy-death-replication" { "Multiplayer enemy death replication verification PASS" }
    default { "Multiplayer verification PASS" }
}

Write-Host $label
Write-Host "Scenario: $scenarioKey"
Write-Host "Output dir: $verifyDir"
"PASS" | Add-Content -Path $launcherLog
