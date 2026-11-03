"""Fixture proofs, not Git clone, hook-activation or committed-tree evidence."""

from collections.abc import Iterator
from pathlib import Path

import pytest
from pylogger import close_log, init_log
from pyprocess import CommandResult

from witness_release.guard import MODULE, REQUIRED_FILES, validate_index
from witness_release.paths import ReleasePaths
from witness_release.sync import DONOR, MANIFEST, plan_release, prepare_release


@pytest.fixture
def release(tmp_path: Path) -> tuple[ReleasePaths, Path]:
    source = tmp_path / "canonical"
    source.mkdir()
    root = tmp_path / "development"
    root.mkdir()
    checkout = tmp_path / "release"
    checkout.mkdir()
    (checkout / ".git").write_text("fixture only, not a real checkout")
    destination = checkout / MODULE
    destination.mkdir()
    (destination / MANIFEST).write_bytes(b"standalone manifest version 1.0.1")
    for name in (
        MANIFEST,
        f"{MODULE}.psm1",
        "Build-WitnessDonor.ps1",
        "Public/Write-Log.ps1",
    ):
        path = source / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b"canonical " + name.encode())
    paths = ReleasePaths(root, source, tmp_path / "logs")
    init_log(str(paths.logs / "tests.release.log"))
    return paths, checkout


@pytest.fixture(autouse=True)
def close_logs() -> Iterator[None]:
    yield
    close_log()


def test_real_files_are_accepted() -> None:
    records = "".join(f"100644 {'a' * 40} 0\t{path}\0" for path in REQUIRED_FILES)
    assert validate_index(records) == ()


@pytest.mark.parametrize("mode", ["120000", "160000", "100755"])
def test_non_regular_module_candidate_is_refused(mode: str) -> None:
    failures = validate_index(f"{mode} {'a' * 40} 0\t{MODULE}\0")
    assert any(mode in reason for reason in failures)
    assert any("release file missing" in reason for reason in failures)


@pytest.mark.parametrize(
    "records", ["", "malformed\0", f"100644 oid 2\t{MODULE}/file\0"]
)
def test_missing_malformed_and_unmerged_candidates_are_refused(records: str) -> None:
    assert validate_index(records)


@pytest.mark.parametrize(
    "name",
    [
        "OWNERSHIP.md",
        "logs/a.log",
        "examples/logs/a.log",
        "js/file.js",
        "original-src/Write-Log.ps1",
        ".archive/old.ps1",
        "donor-code/Write-Log.ps1",
    ],
)
def test_private_and_runtime_material_is_not_copied(
    release: tuple[ReleasePaths, Path],
    name: str,
) -> None:
    paths, checkout = release
    path = paths.canonical / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("not for release")
    plan = plan_release(paths, checkout)
    assert Path(name) not in {item.relative for item in plan.writes}


def test_dry_run_lists_all_writes_without_mutation(
    release: tuple[ReleasePaths, Path],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    paths, checkout = release
    calls: list[list[str]] = []

    def generator(command: list[str], **kwargs: object) -> CommandResult:
        calls.append(command)
        return CommandResult(0, "WhatIf: no write", "")

    monkeypatch.setattr("witness_release.sync.run_command", generator)
    result = prepare_release(paths, checkout, apply=False)
    expected = {
        MANIFEST,
        f"{MODULE}.psm1",
        "Build-WitnessDonor.ps1",
        "Public/Write-Log.ps1",
        str(DONOR),
    }
    assert set(result["writes"]) == expected
    assert "-WhatIf" in calls[0]
    assert "-OutputPath" in calls[0]
    assert not (checkout / MODULE / DONOR).exists()
    assert (
        checkout / MODULE / MANIFEST
    ).read_bytes() == b"standalone manifest version 1.0.1"
    assert not (checkout / MODULE / f"{MODULE}.psm1").exists()


def test_apply_preserves_manifest_and_root_files(
    release: tuple[ReleasePaths, Path],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    paths, checkout = release
    (checkout / "README.md").write_text("repository specific")

    def generator(command: list[str], **kwargs: object) -> CommandResult:
        assert "-WhatIf" not in command
        target = Path(command[command.index("-OutputPath") + 1])
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(b"generated canonical runtime")
        return CommandResult(0, "Ok=True Written=True", "")

    monkeypatch.setattr("witness_release.sync.run_command", generator)
    result = prepare_release(paths, checkout, apply=True)
    assert result["applied"] is True
    assert (checkout / MODULE / DONOR).read_bytes() == b"generated canonical runtime"
    assert (
        checkout / MODULE / MANIFEST
    ).read_bytes() == b"standalone manifest version 1.0.1"
    assert (checkout / "README.md").read_text() == "repository specific"
    assert (
        checkout / MODULE / "Public/Write-Log.ps1"
    ).read_bytes() == b"canonical Public/Write-Log.ps1"


def test_failed_generator_does_not_copy_consumers(
    release: tuple[ReleasePaths, Path],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    paths, checkout = release
    monkeypatch.setattr(
        "witness_release.sync.run_command",
        lambda *args, **kwargs: CommandResult(1, "", "source parse failed"),
    )
    with pytest.raises(RuntimeError, match="source parse failed"):
        prepare_release(paths, checkout, apply=True)
    assert not (checkout / MODULE / f"{MODULE}.psm1").exists()


def test_stale_release_files_require_archive(
    release: tuple[ReleasePaths, Path],
) -> None:
    paths, checkout = release
    stale = checkout / MODULE / "retired.ps1"
    stale.write_text("preserve me")
    plan = plan_release(paths, checkout)
    assert plan.stale == ("retired.ps1",)
    with pytest.raises(ValueError, match="archive stale"):
        prepare_release(paths, checkout, apply=True)
    assert stale.read_text() == "preserve me"


def test_source_escape_is_refused(release: tuple[ReleasePaths, Path]) -> None:
    paths, checkout = release
    outside = checkout / "outside.ps1"
    outside.write_text("not canonical")
    (paths.canonical / "escape.ps1").symlink_to(outside)
    with pytest.raises(ValueError, match="escapes module"):
        plan_release(paths, checkout)


def test_destination_link_is_refused(release: tuple[ReleasePaths, Path]) -> None:
    paths, checkout = release
    (checkout / MODULE / "Public").symlink_to(paths.canonical / "Public")
    with pytest.raises(ValueError, match="traverses a symlink"):
        plan_release(paths, checkout)


def test_development_destination_is_refused(release: tuple[ReleasePaths, Path]) -> None:
    paths, _ = release
    with pytest.raises(ValueError, match="separate"):
        plan_release(paths, paths.root)
