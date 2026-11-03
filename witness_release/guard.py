"""Reject non-file Witness release candidates before Git writes a commit."""

from pathlib import Path

from pyconfig import get_raw_environment
from pylogger import log
from pyprocess import run_command

MODULE = "DivergentCortex.Witness"
REQUIRED_FILES = frozenset(
    {
        f"{MODULE}/{MODULE}.psd1",
        f"{MODULE}/{MODULE}.psm1",
        f"{MODULE}/Public/Write-Log.ps1",
        f"{MODULE}/Public/Initialize-Log.ps1",
        f"{MODULE}/Public/Write-LogFinal.ps1",
    }
)


def validate_index(records: str) -> tuple[str, ...]:
    files: set[str] = set()
    failures: list[str] = []
    for record in records.split("\0"):
        if not record:
            continue
        metadata, separator, path = record.partition("\t")
        fields = metadata.split()
        if not separator or len(fields) != 3:
            failures.append("malformed candidate index record")
            continue
        mode, _, stage = fields
        if path != MODULE and not path.startswith(f"{MODULE}/"):
            continue
        if mode != "100644" or stage != "0":
            failures.append(
                f"release requires regular stage-zero files: {mode} {stage} {path}"
            )
        else:
            files.add(path)
    failures.extend(
        f"release file missing: {path}" for path in sorted(REQUIRED_FILES - files)
    )
    return tuple(failures)


def check_candidate(root: Path) -> tuple[str, ...]:
    log(f"checking Witness candidate index (repository={root})", "info")
    result = run_command(
        ["git", "ls-files", "--stage", "-z", "--", MODULE],
        cwd=root,
        env=get_raw_environment(),
        timeout_seconds=30,
        max_output_bytes=4194304,
    )
    if result.returncode:
        raise RuntimeError(f"candidate index read failed: {result.stderr}")
    failures = validate_index(result.stdout)
    if failures:
        log(
            f"Witness commit refused (repository={root}, reasons={failures})", "warning"
        )
    else:
        log(
            f"Witness candidate verified (repository={root}, required={len(REQUIRED_FILES)})",
            "success",
        )
    return failures
