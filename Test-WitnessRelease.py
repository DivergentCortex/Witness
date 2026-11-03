"""Run the permanent release-tool fixture tests without executing Git."""

from pypaths import add_module_path

add_module_path()

import pytest

from witness_release.paths import load_paths

if __name__ == "__main__":
    paths = load_paths(__file__)
    raise SystemExit(
        pytest.main(
            [
                str(paths.root / "test_witness_release.py"),
                "-v",
                "-p",
                "no:cacheprovider",
            ]
        )
    )
