param(
    [string]$BinDir = (Join-Path $PSScriptRoot '../Bin/x64/Release')
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$bin = (Resolve-Path $BinDir).Path
if (-not (Test-Path (Join-Path $bin 'TrafficMonitor.exe'))) {
    throw "Release x64 executable not found in $bin"
}
if (Get-Process TrafficMonitor -ErrorAction SilentlyContinue) {
    throw 'Run the regression on a clean Windows desktop without another TrafficMonitor instance'
}

# Outside TEMP: the host deliberately disables portable configuration there.
$stage = Join-Path $root ('.hot-reload-test-' + [guid]::NewGuid().ToString('N'))
$trace = Join-Path $stage 'probe-events.txt'
$previousTrace = $env:TM_HOT_RELOAD_TRACE
$process = $null

function Assert-Running {
    $process.Refresh()
    if ($process.HasExited) {
        throw "TrafficMonitor exited unexpectedly (exit code $($process.ExitCode))"
    }
}

function Wait-Generation([int]$generation) {
    $deadline = [DateTime]::UtcNow.AddSeconds(90)
    do {
        Assert-Running
        $events = @()
        if (Test-Path -LiteralPath $trace) {
            $events = @(Get-Content -LiteralPath $trace)
        }
        if ($events -match 'duplicate-init') {
            throw 'Plugin initialization repeated without unloading the DLL'
        }
        $complete = $true
        for ($i = 0; $i -le $generation; $i++) {
            $expected = $generation - $i + 1
            foreach ($event in @('load', 'settings', 'draw')) {
                $actual = @($events | Where-Object { $_ -ceq "$i $event" }).Count
                if ($actual -gt $expected) {
                    throw "Unexpected extra callback: probe $i $event ($actual > $expected)"
                }
                if ($actual -lt $expected) { $complete = $false }
            }
        }
        if ($complete) {
            Start-Sleep -Seconds 2
            Assert-Running
            if (-not $process.Responding) { throw 'TrafficMonitor UI is unresponsive' }
            Write-Host "Generation $generation verified: $($generation + 1) plugins initialized, configured and drawn"
            return
        }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Timed out waiting for generation $generation (load/settings/taskbar draw)"
}

function Install-Probe([int]$index) {
    $source = Join-Path $fixtures "probe-$index.dll"
    $pending = Join-Path $plugins "probe-$index.pending"
    Copy-Item -LiteralPath $source -Destination $pending
    # Publish a complete DLL atomically, not while the timer might be scanning.
    Move-Item -LiteralPath $pending -Destination (Join-Path $plugins "probe-$index.dll")
}

try {
    Copy-Item -LiteralPath $bin -Destination $stage -Recurse
    $plugins = Join-Path $stage 'plugins'
    if (Test-Path -LiteralPath $plugins) { Remove-Item -LiteralPath $plugins -Recurse -Force }
    New-Item -ItemType Directory -Path $plugins | Out-Null
    $fixtures = Join-Path $stage 'fixtures'
    New-Item -ItemType Directory -Path $fixtures | Out-Null

    # Build distinct native modules against the repository's actual plugin SDK.
    Push-Location $fixtures
    try {
        for ($i = 0; $i -lt 4; $i++) {
            & cl.exe /nologo /LD /MT /EHsc /utf-8 "/DPROBE_INDEX=$i" "/I$root/include" (Join-Path $PSScriptRoot 'hot-reload-probe.cpp') "/Foprobe-$i.obj" "/Feprobe-$i.dll" /link user32.lib
            if ($LASTEXITCODE -ne 0) { throw "Probe $i compilation failed: $LASTEXITCODE" }
        }
    } finally { Pop-Location }

    @'
[config]
portable_mode=true
'@ | Set-Content -LiteralPath (Join-Path $stage 'global_cfg.ini') -Encoding ascii

    @'
[general]
check_update_when_start=false
hardware_monitor_item=0
[config]
show_task_bar_wnd=true
hide_main_window=false
[task_bar]
plugin_display_item=hotreload_probe_0,hotreload_probe_1,hotreload_probe_2,hotreload_probe_3
disable_d2d=true
'@ | Set-Content -LiteralPath (Join-Path $stage 'config.ini') -Encoding ascii

    Install-Probe 0
    $env:TM_HOT_RELOAD_TRACE = $trace
    $process = Start-Process -FilePath (Join-Path $stage 'TrafficMonitor.exe') -WorkingDirectory $stage -PassThru
    Wait-Generation 0

    # Exercise the real MAIN_TIMER -> CheckAndReloadPlugins -> CalculateWindowSize
    # path three times, in the same process. Adding a visible ID ensures a stale
    # item-order cache fails even if the loader reuses the original DLL address.
    for ($i = 1; $i -lt 4; $i++) {
        Install-Probe $i
        Wait-Generation $i
    }
    Write-Host 'Hot-reload runtime regression passed (3 reloads)'
} finally {
    $env:TM_HOT_RELOAD_TRACE = $previousTrace
    if ($null -ne $process) {
        $process.Refresh()
        if (-not $process.HasExited) {
            Stop-Process -Id $process.Id -Force
            $process.WaitForExit()
        }
        $process.Dispose()
    }
    if (Test-Path -LiteralPath $trace) {
        Write-Host 'Probe callback trace:'
        Get-Content -LiteralPath $trace | ForEach-Object { Write-Host $_ }
    }
    $log = Join-Path $stage 'error.log'
    if (Test-Path -LiteralPath $log) {
        Write-Host 'TrafficMonitor log:'
        Get-Content -LiteralPath $log -Tail 100 | ForEach-Object { Write-Host $_ }
    }
    if (Test-Path -LiteralPath $stage) {
        Remove-Item -LiteralPath $stage -Recurse -Force
    }
}
