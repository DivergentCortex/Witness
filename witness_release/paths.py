"""Repository anchors for the manual Witness release tools."""

from dataclasses import dataclass
from pathlib import Path

from pypaths import get_script_root, join_path


@dataclass(frozen=True)
class ReleasePaths:
    root: Path
    canonical: Path
    logs: Path


def load_paths(entrypoint: str) -> ReleasePaths:
    root = get_script_root(entrypoint)
    return ReleasePaths(
        root=Path(root),
        canonical=Path(join_path(root, "_modules", "ps", "DivergentCortex.Witness")),
        logs=Path(join_path(root, "logs")),
    )
