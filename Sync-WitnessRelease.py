"""Manual release preparation. Never commits or pushes."""

from pypaths import add_module_path

add_module_path()

import argparse
import json
import sys
from pathlib import Path

from pylogger import init_log, log

from witness_release.paths import load_paths
from witness_release.sync import prepare_release


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release-root", required=True, type=Path)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--dry-run", action="store_true")
    mode.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    paths = load_paths(__file__)
    init_log(str(paths.logs / "release.sync.log"))
    try:
        result = prepare_release(paths, args.release_root, apply=args.apply)
    except (OSError, RuntimeError, TypeError, ValueError) as error:
        log(
            f"Witness release preparation failed (destination={args.release_root}, "
            f"error={error!r})",
            "error",
        )
        sys.stderr.write(f"Witness release preparation failed: {error}\n")
        return 1
    sys.stdout.write(json.dumps(result, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
