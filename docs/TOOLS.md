# Release tools

These are local maintenance tools, not part of the frozen PowerShell API.
They require Python 3.11+ and canonical families available through `_modules/py`
on the launcher's `PYTHONPATH`. Each entry bootstraps with `add_module_path()`.

## Sync-WitnessRelease.py

| Argument | Type | Required | Default |
| --- | --- | --- | --- |
| `--release-root` | Existing scratch Git checkout directory | Yes | None |
| `--dry-run` | Switch, mutually exclusive with apply | No | Effective default |
| `--apply` | Switch, mutually exclusive with dry run | No | False |

The destination module must be a real directory with the standalone manifest.
The development checkout and canonical tree are refused as destinations.
The CLI returns exit 0 and JSON fields `applied`, `destination`, `writes`,
`stale_requires_archive` and `preserved_manifest`; failures return exit 1 with
an error on stderr. A stale file blocks apply without removing that file.

The tool reads canonical module files and invokes canonical
`Build-WitnessDonor.ps1 -OutputPath <release-module>/donor-code/Write-Log.ps1`.
Dry run adds `-WhatIf`. Nonzero generator exit or missing output fails closed.
The real generator integration is pending canonical reconciliation; fixture
stubs verify command arguments, refusal and copy ordering.

Apply writes only the scratch module tree and operational logs. It neither
stages files nor commits, pushes or updates refs. The original standalone
manifest and every root repository-specific file remain unchanged.

## Test-WitnessReleaseIndex.py

No arguments. Reads the development repository's candidate index through
canonical pyprocess and returns exit 0 for a valid real-file snapshot or exit 1
for a non-file entry, unresolved stage, missing required module file or read
failure. Refusals go to stderr. See [HOOKS](HOOKS.md) for activation state.

## Test-WitnessRelease.py

No arguments. Runs `test_witness_release.py` through pytest and returns its
exit code. Fixtures stub donor generation and do not execute Git or prove
cloneability, Pester behavior or an installed hook. Pytest is required.

Operational log targets are listed in [logs/README](../logs/README.md).
See [ARCHITECTURE](ARCHITECTURE.md) for ownership and publication boundaries.
