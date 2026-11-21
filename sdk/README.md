# TrafficMonitor Plugin SDK (C ABI → WASM → Rust host)

This repository is the single source of truth for migrating the existing C++/MFC
TrafficMonitor plugins to the future Rust core.

## What we port (in order)

1. `qqrm/TrafficMonitor-WirelessDeviceBatteryPlugin` — battery plugin (small, pure data + drawing).
2. `qqrm/better-trafficmonitor-ai-usage-plugin` — AI usage plugin (network + file parsing; keep the Rust core native, move only the plugin layer).
3. `qqrm/TrafficMonitorPlugins` — the wider plugin catalogue, migrated on demand.
4. `qqrm/TrafficMonitor` — the MFC host shell stays as a compatibility bridge until the Rust host is stable.

## How we port

The C++ virtual-plugin ABI (`ITMPlugin` / `IPluginItem`) is replaced by a flat C ABI
defined in [`abi/tm_plugin_abi.h`](abi/tm_plugin_abi.h). Every plugin exposes one
entry point returning a vtable. C++ plugins are compiled with
`clang++ --target=wasm32-wasi`; Rust plugins compile natively to the same ABI.

All operating-system interaction goes through **host functions** supplied by the
Rust host (`draw_text`, `fill_rect`, `draw_image`, `get_config_dir`, `poll_devices`,
`http_get`). A plugin never calls MFC/GDI, opens files, or creates sockets itself.
This makes the plugin sandboxed and keeps the ABI stable across host rewrites.

The Rust host loads WASM modules with `wasmtime`, validates the ABI version before
instantiation, and hot-reloads a module when its file changes (5 s dev / 60 s release,
same as the current MFC fork).

## Criteria of truth (acceptance)

A plugin is "ported" only when **all** of the following pass in CI:

| # | Criterion | Check |
|---|---|---|
| 1 | Compiles to `wasm32-wasi` without host headers | `scripts/build-plugin.ps1` |
| 2 | Exports `tm_plugin_abi_version` and `tm_plugin_vtable` | `wasm-objdump -x` / host loader |
| 3 | ABI version equals the SDK version | host smoke test |
| 4 | Loads in the validation host within 2 s | `plugin-host smoke` |
| 5 | `data_required` returns fixture-derived values | deterministic JSON fixture |
| 6 | `draw_item` produces the golden surface | pixel/surface hash comparison |
| 7 | 10 hot-reload cycles: no crash, no GDI/memory growth | soak test |
| 8 | No raw file/socket imports beyond the host function list | WASM import audit |
| 9 | Binary + source SHA256 recorded | release step |

These are *behavioural* checks, not "it builds" checks. External plugins are the
oracle: if a third-party plugin built against this SDK passes 1–9, the host ABI is
compatible; if it fails, the host regressed.

## Reusable pipeline

[`.github/workflows/plugin-gate.yml`](.github/workflows/plugin-gate.yml) is a reusable
workflow. A plugin repository needs only:

```yaml
jobs:
  gate:
    uses: qqrm/trafficmonitor-plugin-sdk/.github/workflows/plugin-gate.yml@<sha>
    with:
      plugin-dir: .
      fixture: tests/fixture.json
```

The gate builds the plugin, validates the ABI, loads it in the host, renders the
fixture, compares the golden hash, and runs the hot-reload soak test.

## Current status

- [x] Roadmap and criteria fixed (this document)
- [x] C ABI header
- [ ] Minimal Rust validation host (`crates/plugin-host`)
- [ ] Reusable CI workflow
- [ ] First migrated plugin (battery)
- [ ] Second migrated plugin (AI usage)
