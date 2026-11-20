$ErrorActionPreference = 'Stop'
$fail = $false
function Fail($msg) { Write-Host "::error::$msg"; $script:fail = $true }

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$pm = Get-Content (Join-Path $root 'TrafficMonitor\PluginManager.cpp') -Raw
$dlg = Get-Content (Join-Path $root 'TrafficMonitor\TrafficMonitorDlg.cpp') -Raw
$taskbarH = Get-Content (Join-Path $root 'TrafficMonitor\TaskBarDlg.h') -Raw

# TOCTOU: detection and reload must be in one critical section
if ($pm -notmatch 'bool CPluginManager::CheckAndReloadPlugins\(\)[\s\S]{0,400}CSingleLock lock\(&m_cs') {
    Fail 'CheckAndReloadPlugins does not hold m_cs across detect+reload'
}
# Upper API version bound
if ($pm -notmatch 'PLUGIN_MAX_SUPPORT_VERSION') {
    Fail 'missing upper bound for plugin API version'
}
# PE header validation in IAT patcher
if ($pm -notmatch 'IMAGE_DOS_SIGNATURE' -or $pm -notmatch 'IMAGE_NT_SIGNATURE') {
    Fail 'IAT patcher missing PE signature validation'
}
# UI pointer invalidation after reload
if ($dlg -notmatch 'InvalidatePluginPointers' -or $taskbarH -notmatch 'InvalidatePluginPointers') {
    Fail 'UI cached plugin pointers are not invalidated after reload'
}
# No developer absolute paths in shipped sources
$files = @('PluginManager.cpp', 'PluginManager.h', 'TrafficMonitorDlg.cpp', 'TaskBarDlg.h') | ForEach-Object { Join-Path (Join-Path $root 'TrafficMonitor') $_ }
foreach ($f in $files) {
    $c = Get-Content $f -Raw -ErrorAction SilentlyContinue
    if ($c -match '[A-Za-z]:\\(Temp|repos|Users)') {
        Fail "absolute developer path in $($f.Substring($root.Length+1))"
    }
}

if ($fail) { exit 1 }
Write-Host 'hot-reload static checks passed'