# Logs

The release tools call canonical pylogger through the local `_modules` bridge.
Files are flat under this directory; pylogger supplies dates and rotation.

| Target | Written by | Contents |
| --- | --- | --- |
| `release.sync_YYYYMMDD.log` | `Sync-WitnessRelease.py` | Release planning, donor generation, file copy outcomes and failures |
| `hook.release_YYYYMMDD.log` | `Test-WitnessReleaseIndex.py` | Candidate-index validation and refusal |

The index-check entry point is not yet installed as a Git hook. Fixture tests
use `tests.release_YYYYMMDD.log` under pytest scratch directories, not here.
