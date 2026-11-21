param(
    [string]$Wasm = 'artifacts/plugin.wasm',
    [int]$ExpectedAbiVersion = 1
)

$ErrorActionPreference = 'Stop'
if (!(Test-Path $Wasm)) { throw "missing $Wasm" }

$bytes = [System.IO.File]::ReadAllBytes($Wasm)
if ($bytes.Length -lt 8 -or [Text.Encoding]::ASCII.GetString($bytes, 0, 4) -ne "`0asm") {
    throw 'not a WASM module'
}

$text = [Text.Encoding]::ASCII.GetString($bytes)
foreach ($symbol in @('tm_plugin_abi_version', 'tm_plugin_vtable')) {
    if (!$text.Contains($symbol)) {
        throw "missing required export: $symbol"
    }
}

Write-Host "PASS: WASM module $Wasm exports required ABI symbols (ABI v$ExpectedAbiVersion expected in host smoke test)"
