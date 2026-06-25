# Contributing

Contributions are welcome. Here is how to do it cleanly.

## Workflow

1. Fork the repository and create a branch from `main`.
2. Make your changes. Keep commits focused - one logical change per commit.
3. Add or update tests in `DivergentCortex.Witness/tests/` to cover your change.
4. Run the test suite locally before pushing:
   ```powershell
   Invoke-Pester -Path DivergentCortex.Witness/tests/ -Output Detailed
   ```
   All tests must pass on your platform.
5. Open a pull request against `main`. Describe what you changed and why.

## Code standards

- PowerShell 5.1 syntax only - no ternary operators, no `??`, no `??=`.
- ASCII only in all source files. No smart quotes, em dashes, or other
  non-ASCII characters.
- Private helpers go in `DivergentCortex.Witness/Private/`. Public functions go
  in `DivergentCortex.Witness/Public/`. Do not add new public exports without
  discussion.
- CMTrace line format must remain byte-compatible with the existing output.
  If you change Write-Log.ps1, run Describe 2 and 8 from the test suite to
  verify format parity.

## Platform scope

The module targets Windows PowerShell 5.1 and PowerShell 7.4+ on Windows,
Linux, and macOS. Changes that break any supported platform will not be merged.
The CI workflow runs all four combinations on every pull request.

## Questions

Open an issue for discussion before starting large changes. Small fixes and
test additions can go straight to a PR.
