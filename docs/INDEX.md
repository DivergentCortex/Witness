# Project index

| Path | Role |
| --- | --- |
| [Root README](../README.md) | Existing module overview and installation |
| [ARCHITECTURE](ARCHITECTURE.md) | Canonical/development/release boundaries |
| [TOOLS](TOOLS.md) | Maintenance CLI contracts and prerequisites |
| [HOOKS](HOOKS.md) | Guard activation state and required commit chain |
| [CHANGELOG](CHANGELOG.md) | Attributable changes and verification limits |
| `DivergentCortex.Witness/` | Runtime module; approved canonical link cutover pending |
| `Sync-WitnessRelease.py` | Manual dry-run/apply CLI |
| `Test-WitnessReleaseIndex.py` | Candidate-check CLI, not installed as hook yet |
| `Test-WitnessRelease.py` | Sanctioned pytest fixture runner |
| `witness_release/paths.py` | Project anchors through canonical pypaths |
| `witness_release/guard.py` | Candidate-index mode and required-file rules |
| `witness_release/sync.py` | Release plan, donor invocation and verified copy |
| `test_witness_release.py` | Permanent guard/sync fixtures |
| [Log inventory](../logs/README.md) | Canonical logger targets |
| `_modules` | Ignored local bridge to canonical fleet families |

Root security, contribution, license and `.github` content are preserved.
