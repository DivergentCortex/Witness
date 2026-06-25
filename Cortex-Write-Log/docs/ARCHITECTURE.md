# Architecture

DivergentCortex.Witness is a PowerShell module that writes CMTrace-compatible structured log files with colorized console output. This document covers how the module is organized, how its components interact, and the design decisions behind the current structure.

## Module layout

```
Cortex-Write-Log/
  DivergentCortex.Witness.psd1       Module manifest
  DivergentCortex.Witness.psm1       Module loader
  Public/
    Write-Log.ps1                    Core CMTrace logger
    Initialize-Log.ps1               Session init + start banner
    Write-LogFinal.ps1               Final entry + cleanup trigger
  Private/
    Get-PlatformContext.ps1          Cross-platform identity/context adapter
    Clear-LogFile.ps1                Age-based log cleanup
    Resolve-WitnessLogPath.ps1       Shared log path resolution chain
  donor-code/
    Write-Log.ps1                    Original monolithic script (read-only spec)
  docs/
    ARCHITECTURE.md                  This file
    CROSS-PLATFORM.md                Per-mechanism cross-platform research
    DESIGN.md                        Original design spec (pre-build)
  tests/
    DivergentCortex.Witness.Tests.ps1   Pester v5 test suite
```

The manifest (`.psd1`) exports exactly three functions: `Write-Log`, `Initialize-Log`, `Write-LogFinal`. No cmdlets, variables, or aliases are exported. Private helpers (`Clear-LogFile`, `Get-PlatformContext`, `Resolve-WitnessLogPath`) are internal to the module and not accessible to consumers.

## Module loader

`DivergentCortex.Witness.psm1` does three things at load time:

1. **Platform probe.** Sets `$script:WitnessIsWindows` using `Test-Path Variable:IsWindows`. On PS 5.1, `$IsWindows` does not exist as an automatic variable; its absence is treated as Windows (correct, since PS 5.1 only runs on Windows). Every file in the module reads `$script:WitnessIsWindows`; raw `$IsWindows` is never used anywhere.

2. **Module-scope state initialization.** Declares `$script:WitnessLogFilePath` (set later by `Initialize-Log`), `$script:WitnessCleanupRan` (the once-per-session cleanup sentinel), and configuration defaults (`$script:WitnessMaxSizeMB`, `$script:WitnessMaxAgeDays`, etc.).

3. **Dot-source load order.** Private helpers first (Get-PlatformContext, Clear-LogFile, Resolve-WitnessLogPath), then public functions (Write-Log, Initialize-Log, Write-LogFinal). This matches the fleet standard of private-before-public, top-to-bottom within each tier.

## Get-PlatformContext: the platform adapter

`Get-PlatformContext` is a private function that centralizes all OS-specific identity and context detection. It runs once during `Initialize-Log` and returns a `[pscustomobject]` with these fields:

| Field | Windows | Linux/macOS |
|---|---|---|
| Platform | `'Windows'` | `'Linux'` or `'macOS'` |
| IdentityName | `WindowsIdentity.GetCurrent().Name` (SAM format) | `[Environment]::UserDomainName\UserName` |
| LogonType | `WindowsIdentity.AuthenticationType` | `'N/A'` |
| IsSystem | True if identity is `NT AUTHORITY\SYSTEM` | Always `$false` |
| IsAdmin | `WindowsPrincipal.IsInRole(Administrator)` | `[Environment]::IsPrivilegedProcess` (7.4+) or `id -u` fallback |
| UserDomainName | AD domain or workgroup name | Hostname (documented gap) |
| UserName | `[Environment]::UserName` | `[Environment]::UserName` |
| InteractiveUser | Owner of `explorer.exe` | loginctl graphical session, `who(1)`, or `[Environment]::UserName` |
| SessionType | `WindowsIdentity.AuthenticationType` | `SSH_CONNECTION` / `XDG_SESSION_TYPE` / loginctl / TTY heuristic |
| HostName | `[Environment]::MachineName` | `[Environment]::MachineName` |
| ProcessId | `$PID` | `$PID` |

The adapter is used only for the `Initialize-Log` start banner. Its result is held in a local variable (`$ctx`) inside `Initialize-Log`, not stored in module scope. An earlier version cached it in `$script:WitnessContext`, but that was dead state (assigned but never read after `Initialize-Log` returned) and was removed.

The key design decision: public functions never branch on OS themselves. All platform-conditional logic lives inside `Get-PlatformContext` and the `$script:WitnessIsWindows` probe. Write-Log resolves `context=` per write using a lightweight inline check (see below), but that is the only OS-aware code outside the adapter.

## Per-write context resolution

Write-Log does not call `Get-PlatformContext` on every log line. Instead, it resolves the `context=` field directly:

- **Windows:** `[System.Security.Principal.WindowsIdentity]::GetCurrent().Name` per write. This preserves impersonation-correct identity (if the thread token changes mid-script, each log line reflects the active identity at write time).
- **Non-Windows:** `[System.Environment]::UserDomainName\[System.Environment]::UserName`. Cheap property access, no subprocess spawning.

This split exists because the donor called `WindowsIdentity.GetCurrent()` inline at three sites. The module consolidates the heavy adapter work into `Get-PlatformContext` for the banner, then uses the lightweight per-write path for the `context=` field where calling the full adapter on every line would be wasteful.

## Log path resolution

Both `Write-Log` and `Initialize-Log` resolve the log file path through a shared chain implemented in `Resolve-WitnessLogPath`. The public function handles the first two layers (which require `$PSCmdlet.SessionState` access), then delegates to the private resolver for layers 3 and 4.

Resolution order (first non-empty value wins):

1. **Explicit parameter:** `-Logfile` on Write-Log, `-LogFilePath` on Initialize-Log.
2. **Caller scope:** The public function reads `$LogFilePath` from the caller's scope via `$PSCmdlet.SessionState.PSVariable.GetValue('LogFilePath')`. This preserves the original dot-source-era pattern where the caller just sets `$LogFilePath = '...'` before calling. Note: this works for same-session-state callers (direct calls, dot-sourced helpers). It cannot cross a foreign-module boundary; under `Import-Module`, use the explicit parameter or `$Global:LogFilePath`.
3. **Module scope:** `$script:WitnessLogFilePath`, set by `Initialize-Log`.
4. **Global scope:** `$Global:LogFilePath`, for back-compat with the legacy pattern.

If no path resolves, Write-Log and Initialize-Log both throw.

## Cleanup sentinel lifecycle

Log cleanup (age-based deletion of old `.log` files) runs at most once per session. The guard is `$script:WitnessCleanupRan`, a boolean in module scope.

The lifecycle:

1. **Module load:** `$script:WitnessCleanupRan` is set to `$false` in the `.psm1` loader.
2. **First trigger:** Either Write-Log's auto-cleanup (runs on the first write when `$script:WitnessAutoCleanup` is true) or Write-LogFinal's explicit cleanup, whichever fires first. Both check the sentinel, set it to `$true` before calling `Clear-LogFile`, and skip if already set.
3. **Reset:** Calling `Initialize-Log` again resets the sentinel to `$false`. This allows a second session context (new log tree, new target directory) to get exactly one cleanup pass.
4. **Invariant:** Write-LogFinal sets the sentinel to `$true` on all return paths, including early exits from path-resolution failures. No code path can leave the sentinel unset after Write-LogFinal has been invoked.

`Clear-LogFile` itself is straightforward: it scans the log folder for `.log` files, deletes any older than `$MaxAgeDays` (default 7, overridable via `$Global:WriteLogMaxAgeDays`), and logs each deletion through Write-Log.

## CMTrace line format

Every log line follows the CMTrace XML-ish format:

```
<![LOG[message text]LOG]!><time="HH:mm:ss.fff+offset" date="MM-dd-yyyy" component="CallerName" context="DOMAIN\user" type="N" thread="PID" file="Source">
```

Field details:

- **time:** `HH:mm:ss.fff` with UTC offset in total minutes appended directly (e.g., `14:30:45.123-300` for US Eastern).
- **date:** `MM-dd-yyyy` (CMTrace convention, not ISO).
- **component:** Auto-detected from the call stack. If the caller is a named function, uses the function name. If it is a script body, uses the script filename without extension. Overridable via `-Component`.
- **context:** Per-write identity (see above).
- **type:** Severity-to-CMTrace type code mapping (see table below).
- **thread:** Process ID (`$PID`).
- **file:** Source location from `Get-PSCallStack` (script path and line).

### Severity to type mapping

| Severity value | CMTrace type code |
|---|---|
| Info | 1 |
| Information | 1 (mapped to Info internally) |
| Success | 1 |
| Warning | 2 |
| Error | 3 |
| Verbose | 4 |
| Debug | 5 |

## Size-based rotation

When a log file exceeds the size threshold (default 10 MB, overridable via `$Global:WriteLogMaxSizeMB`), Write-Log renames the current file with a `_r01`, `_r02`, etc. suffix and starts a new file. The first line of the new file is a rotation notice indicating the archive filename. The rotation notice uses `[System.IO.File]::WriteAllText` with `[System.Environment]::NewLine` so the line ending matches the platform convention (CRLF on Windows, LF on Linux/macOS).

## SCCM drive handling

On Windows, if the current working directory is on a ConfigMgr `CMSite` PSDrive (detected via `$originalLocation.Provider.Name -eq 'CMSite'`), Write-Log hops to `C:` before file I/O and restores the original location in a `finally` block. This is skipped entirely when `$script:WitnessIsWindows` is false.

## The donor relationship

The original `Write-Log.ps1` lives at `donor-code/Write-Log.ps1` and is read-only. It is never edited. It serves as the behavioral specification: four years of hardening in production SCCM deployments. The module re-implements its behavior with the platform adapter layered in, but the donor defines what "correct" looks like for CMTrace format, severity handling, console output, rotation, cleanup, and caller detection.

Public function names (`Write-Log`, `Initialize-Log`, `Write-LogFinal`) are preserved unchanged. Existing consumer scripts work without modification when switching from the dot-sourced donor to the module import.

## PS 5.1 compatibility

Windows PowerShell 5.1 is the original deployment target. The module avoids all PS 7+ syntax:

- No ternary operators (`? :`). All conditionals use `if/else`.
- No null-coalescing (`??`). Explicit null checks throughout.
- `$IsWindows` is never referenced directly. The module-scope probe `Test-Path Variable:IsWindows` handles 5.1 where the automatic variable does not exist.
- `$IsMacOS` is similarly guarded with `Test-Path Variable:IsMacOS` inside `Get-PlatformContext`.
- `[Environment]::IsPrivilegedProcess` (requires .NET 8+, which ships with PS 7.4+) is wrapped in a try/catch with an `id -u` fallback that only runs on non-Windows systems.
