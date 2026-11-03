"""Prepare a real-file Witness release in an explicitly supplied scratch checkout."""

from dataclasses import dataclass
from pathlib import Path
from typing import TypedDict

from pyconfig import get_raw_environment
from pylogger import log
from pyprocess import run_command
from pyvalidate import require_directory, require_file

from witness_release.paths import ReleasePaths

MODULE = "DivergentCortex.Witness"
MANIFEST = f"{MODULE}.psd1"
DONOR = Path("donor-code/Write-Log.ps1")
EXCLUDED = frozenset(
    {
        "OWNERSHIP.md",
        "logs",
        "js",
        "original-src",
        "donor-code",
        ".archive",
        ".archives",
        "archive",
        "archives",
        ".git",
        "__pycache__",
    }
)


@dataclass(frozen=True)
class FileWrite:
    relative: Path
    content: bytes


@dataclass(frozen=True)
class ReleasePlan:
    destination: Path
    writes: tuple[FileWrite, ...]
    stale: tuple[str, ...]


class ReleaseReport(TypedDict):
    applied: bool
    destination: str
    writes: list[str]
    stale_requires_archive: list[str]
    preserved_manifest: str


def plan_release(paths: ReleasePaths, release_root: Path) -> ReleasePlan:
    source = Path(require_directory(paths.canonical)).resolve()
    root = Path(require_directory(release_root)).absolute()
    if root != root.resolve():
        raise ValueError("release checkout path must not traverse a symlink")
    if (
        root == paths.root.resolve()
        or root.is_relative_to(source)
        or source.is_relative_to(root)
    ):
        raise ValueError(
            "release checkout must be separate from development and canonical trees"
        )
    if not (root / ".git").exists():
        raise ValueError("release destination must be an existing Git checkout")
    destination = root / MODULE
    if destination.is_symlink() or not destination.is_dir():
        raise ValueError(
            "release module destination must be an existing real directory"
        )
    manifest = Path(require_file(destination / MANIFEST))
    writes: list[FileWrite] = []
    for path in sorted(source.rglob("*")):
        relative = path.relative_to(source)
        if any(part in EXCLUDED for part in relative.parts) or not path.is_file():
            continue
        if not path.resolve().is_relative_to(source):
            raise ValueError(f"canonical file escapes module: {relative}")
        target = destination / relative
        for candidate in (target, *target.parents):
            if candidate == root:
                break
            if candidate.is_symlink():
                raise ValueError(f"release destination traverses a symlink: {relative}")
        content = (
            manifest.read_bytes() if relative == Path(MANIFEST) else path.read_bytes()
        )
        writes.append(FileWrite(relative, content))
    planned = {item.relative for item in writes} | {DONOR}
    required = {Path(MANIFEST), Path(f"{MODULE}.psm1"), Path("Build-WitnessDonor.ps1")}
    if not required.issubset(planned):
        raise ValueError(
            "canonical release is missing its manifest, loader or donor generator"
        )
    stale = tuple(
        str(path.relative_to(destination))
        for path in sorted(destination.rglob("*"))
        if (path.is_file() or path.is_symlink())
        and path.relative_to(destination) not in planned
    )
    return ReleasePlan(destination, tuple(writes), stale)


def generate_donor(paths: ReleasePaths, plan: ReleasePlan, *, dry_run: bool) -> None:
    output = plan.destination / DONOR
    if output.is_symlink() or output.parent.is_symlink():
        raise ValueError("generated donor destination must not traverse a symlink")
    script = Path(require_file(paths.canonical / "Build-WitnessDonor.ps1"))
    command = [
        "pwsh",
        "-NoLogo",
        "-NoProfile",
        "-NonInteractive",
        "-File",
        str(script),
        "-OutputPath",
        str(output),
    ]
    if dry_run:
        command.append("-WhatIf")
    log(
        f"generating release donor (script={script}, output={output}, dry_run={dry_run})",
        "info",
    )
    result = run_command(
        command,
        env=get_raw_environment(),
        cwd=paths.root,
        timeout_seconds=120,
        max_output_bytes=1048576,
    )
    if result.returncode:
        raise RuntimeError(
            f"donor generation failed (exit={result.returncode}, "
            f"stdout={result.stdout}, stderr={result.stderr})"
        )
    if not dry_run:
        require_file(output)
        if output.is_symlink():
            raise ValueError(
                "donor generator produced a symlink instead of a real file"
            )
    log(
        f"release donor generation verified (output={output}, dry_run={dry_run}, "
        f"generator_output={result.stdout})",
        "success",
    )


def prepare_release(
    paths: ReleasePaths, release_root: Path, *, apply: bool
) -> ReleaseReport:
    log(
        f"preparing Witness release (destination={release_root}, apply={apply})", "info"
    )
    plan = plan_release(paths, release_root)
    if apply and plan.stale:
        raise ValueError(
            f"archive stale release files through Axon before applying: {plan.stale}"
        )
    generate_donor(paths, plan, dry_run=not apply)
    if apply:
        for item in plan.writes:
            target = plan.destination / item.relative
            log(
                f"copying canonical release file (path={target}, bytes={len(item.content)})",
                "verbose",
            )
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(item.content)
            target.chmod(0o644)
            if target.read_bytes() != item.content:
                raise OSError(f"release readback differs: {target}")
            log(
                f"canonical release file verified (path={target}, bytes={len(item.content)})",
                "verbose",
            )
    result: ReleaseReport = {
        "applied": apply,
        "destination": str(plan.destination),
        "writes": [str(item.relative) for item in plan.writes] + [str(DONOR)],
        "stale_requires_archive": list(plan.stale),
        "preserved_manifest": str(plan.destination / MANIFEST),
    }
    log(
        f"Witness release preparation verified (destination={plan.destination}, "
        f"writes={len(plan.writes) + 1}, stale={len(plan.stale)}, applied={apply})",
        "success",
    )
    return result
