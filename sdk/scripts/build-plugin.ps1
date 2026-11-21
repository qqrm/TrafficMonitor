param(
    [string]$PluginDir = '.',
    [string]$OutDir = 'artifacts'
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

if (Test-Path (Join-Path $PluginDir 'Cargo.toml')) {
    & cargo build --manifest-path (Join-Path $PluginDir 'Cargo.toml') --release --target wasm32-wasip1
    $wasm = Get-ChildItem (Join-Path $PluginDir 'target\wasm32-wasip1\release') -Filter '*.wasm' | Select-Object -First 1
    Copy-Item $wasm.FullName (Join-Path $OutDir 'plugin.wasm') -Force
} elseif ($env:WASI_SYSROOT) {
    $sources = Get-ChildItem $PluginDir -Recurse -File -Include *.cpp,*.c
    & clang++ --target=wasm32-wasip1 --sysroot=$env:WASI_SYSROOT -O2 -fno-exceptions -shared `
        @($sources.FullName) -o (Join-Path $OutDir 'plugin.wasm')
} else {
    throw 'No Cargo.toml and WASI_SYSROOT is not set; cannot build WASM plugin.'
}

Get-FileHash (Join-Path $OutDir 'plugin.wasm') -Algorithm SHA256 | Format-List