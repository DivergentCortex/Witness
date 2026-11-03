"""Pre-commit entry point for the real-file Witness release invariant."""

from pypaths import add_module_path

add_module_path()

import sys

from pylogger import init_log, log

from witness_release.guard import check_candidate
from witness_release.paths import load_paths


def main() -> int:
    paths = load_paths(__file__)
    init_log(str(paths.logs / "hook.release.log"))
    try:
        failures = check_candidate(paths.root)
    except (OSError, RuntimeError, TypeError, ValueError) as error:
        log(
            f"Witness candidate check failed (repository={paths.root}, error={error!r})",
            "error",
        )
        sys.stderr.write(
            f"Witness commit refused: candidate could not be verified: {error}\n"
        )
        return 1
    if failures:
        sys.stderr.write("Witness commit refused:\n" + "\n".join(failures) + "\n")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
