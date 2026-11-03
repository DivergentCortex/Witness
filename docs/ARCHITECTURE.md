# Standalone Witness repository

This repository retains its independent Git history and publication identity.
The runtime module internals are documented in
[the module architecture](../DivergentCortex.Witness/docs/ARCHITECTURE.md).

## Canonical source and release boundary

The approved development layout makes `DivergentCortex.Witness` a local link
to Cortex Modules' canonical PowerShell module. Git release trees must contain
real files instead. The link cutover is pending an active commit guard; the
original directory remains in place until that guard is proven.

The ignored `_modules` bridge provides canonical Python paths, logging,
validation, config and process execution for the release tools. The tools do
not modify that shared source. `witness_release/paths.py` establishes the
repository anchors once.

`Sync-WitnessRelease.py` delegates to `witness_release/sync.py`: validate a
separate checkout, snapshot allowed canonical files, generate the distribution
donor, then copy and read back real files. Its dry run reports every write and
any stale destination file. Stale files require Axon archival before apply;
the tool never deletes them. The existing standalone manifest is retained
byte for byte, preserving this repository's manifest/version policy.

Root README, security, contribution, license, workflows and changelog files
are outside the copy boundary. Only the generated donor is distributable;
`original-src`, historical donor snapshots, ownership records, logs, archives
and the misplaced JavaScript subtree are excluded.

## Commit boundary

[The candidate check](HOOKS.md) validates the candidate index rather than the
linked development directory. Hook installation, real refusal proof, release
branch advancement and scratch-clone acceptance depend on approved Git MCP
capabilities. Source fixtures establish no running-hook or Git release claim.

The sync tool never commits, pushes, watches canonical changes or schedules
itself. Final release synchronization waits for canonical reconciliation.
Publishing GitHub main is a separate operator decision.

See [TOOLS](TOOLS.md) for interfaces, [INDEX](INDEX.md) for paths and
[CHANGELOG](CHANGELOG.md) for verified changes.
