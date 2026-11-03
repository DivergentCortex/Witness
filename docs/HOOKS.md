# Witness release guard

## Activation state

`Test-WitnessReleaseIndex.py` and `witness_release/guard.py` implement the
candidate check. No pre-commit hook is installed by this change yet. The
requested module-directory link must not be installed before the effective
commit path executes the guard and a real commit attempt proves refusal.

## Required chain

The approved installation must preserve existing fleet pre-commit checks,
resolve the effective `core.hooksPath`, then invoke the Witness candidate
check for this repository on both manual commits and git-pulse checkpoints.
A `.git/hooks/pre-commit` file alone is insufficient when hooksPath points
elsewhere. There is no hook-bypass option in the release tooling.

The check reads the candidate index, requires regular mode `100644` and
stage zero for every module entry, and requires the manifest, loader and the
three frozen public-function files. A root `120000` link, nested links,
gitlinks, executable entries, unresolved stages and wholesale module deletion
are refused. Index-read failure also refuses the commit. Its process and log
dependencies are described in [TOOLS](TOOLS.md).

Hook installation does not authorize deleting or replacing existing checks.
Git plumbing for safe activation and a disposable refusal candidate is an
external prerequisite, not supplied by the fixture suite.

## Release-only donor transition

The current `.gitignore` still excludes the historical local donor. Keep it
excluded until the original module is archived and guard-first cutover is
proven. Only then replace that exclusion with an `original-src` exclusion so
the generated distribution donor can be staged. Never stage the old snapshots.
Existing public-history removal and GitHub main publication require operator
decisions and are not performed by these tools.

See [ARCHITECTURE](ARCHITECTURE.md) for the real-file publication boundary.
