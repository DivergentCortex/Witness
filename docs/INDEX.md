# Project index

| Path | Role |
| --- | --- |
| [README](README.md) | What Witness does, install, quick start, parameters, configuration |
| [ARCHITECTURE](ARCHITECTURE.md) | Module internals: loader, platform adapter, path resolution, rotation, redaction, failure path |
| [CROSS-PLATFORM](CROSS-PLATFORM.md) | Per-mechanism research behind the Linux and macOS behavior |
| [CHANGELOG](CHANGELOG.md) | Every change, newest first |
| [CONTRIBUTING](CONTRIBUTING.md) | Workflow, code standards, platform scope |
| [SECURITY](SECURITY.md) | How to report a vulnerability |
| `DivergentCortex.Witness/` | The module: manifest, loader, Public, Private, config, examples, tests |
| `DivergentCortex.Witness/Invoke-WitnessTests.ps1` | Runs the three Pester suites with per-suite totals |
| `Write-Log/Write-Log.ps1` | Standalone single-file script for dot-sourcing |
| `.github/workflows/test.yml` | Pester on Linux, macOS, Windows pwsh and Windows PowerShell 5.1 |
| [Log inventory](../logs/README.md) | Log files written by the test runner |
