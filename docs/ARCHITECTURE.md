# Architecture

DivergentCortex.Witness is a PowerShell module that writes CMTrace-compatible structured log files with colorized console output. This document covers how the module is organized, how its components interact, and the design decisions behind the current structure.

## Repository layout

```
DivergentCortex.Witness/             The module, the only folder that ships
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
    Write-WitnessFailureLine.ps1     Non-recursive reporting of logger-internal failures
    Get-WitnessContextUser.ps1       Per-write identity for the context field
    New-WitnessLogDirectory.ps1      Log folder create with a post-create check
    Write-WitnessConsoleLine.ps1     Color-coded console line
    Invoke-WitnessRotation.ps1       Size check, rename and rotation notice
    Add-WitnessLogLine.ps1           Append with lock retries and contention note
    Invoke-WitnessAutoCleanup.ps1    Once-per-session age-based cleanup
    Restore-WitnessLocation.ps1      CMSite location restore
    ConvertTo-WitnessRedactedText.ps1  Credential redaction applied to every message
    Get-BannerConfig.ps1             Banner config reader, not wired into Initialize-Log
  config/
    banner.psd1                      Banner config defaults
  examples/
    Example-Usage.ps1                Runnable walkthrough
  Invoke-WitnessTests.ps1            Run the Pester suites with per-suite totals
  tests/
    DivergentCortex.Witness.Tests.ps1   Main Pester suite
    Witness.FailurePath.Tests.ps1       Logger-internal failure handling
    Redaction.Tests.ps1                 Redaction cases and the file-line check
    redaction_cases.json                Shared redaction cases
Write-Log/
  Write-Log.ps1                      Standalone single-file script for dot-sourcing
docs/                                README, ARCHITECTURE, CROSS-PLATFORM, INDEX, CHANGELOG,
                                     CONTRIBUTING, SECURITY
.github/workflows/test.yml           Pester on Linux, macOS, Windows pwsh and Windows 5.1
```

The manifest (`.psd1`) exports exactly three functions: `Write-Log`, `Initialize-Log`, `Write-LogFinal`. No cmdlets, variables, or aliases are exported. Everything under `Private/` is internal to the module and not accessible to consumers.

## Module loader

`DivergentCortex.Witness.psm1` does three things at load time:

1. **Platform probe.** Sets `$script:WitnessIsWindows` using `Test-Path Variable:IsWindows`. On PS 5.1, `$IsWindows` does not exist as an automatic variable; its absence is treated as Windows (correct, since PS 5.1 only runs on Windows). Every file in the module reads `$script:WitnessIsWindows`; raw `$IsWindows` is never used anywhere.

2. **Module-scope state initialization.** Declares `$script:WitnessLogFilePath` (set later by `Initialize-Log`), `$script:WitnessCleanupRan` (the once-per-session cleanup sentinel), and configuration defaults (`$script:WitnessMaxSizeMB`, `$script:WitnessMaxAgeDays`, etc.).

3. **Dot-source load order.** Private helpers first, in dependency order starting with Get-PlatformContext, then public functions (Write-Log, Initialize-Log, Write-LogFinal). The loader names each file explicitly rather than globbing the folders.

## Get-PlatformContext: the platform adapter

`Get-PlatformContext` is a private function that centralizes all OS-specific identity and context detection. It runs once during `Initialize-Log` and returns a `[pscustomobject]` with these fields:

| Field           | Windows                                          | Linux/macOS                                                        |
| --------------- | ------------------------------------------------ | ------------------------------------------------------------------ |
| Platform        | `'Windows'`                                      | `'Linux'` or `'macOS'`                                             |
| IdentityName    | `WindowsIdentity.GetCurrent().Name` (SAM format) | `[Environment]::UserDomainName\UserName`                           |
| LogonType       | `WindowsIdentity.AuthenticationType`             | `'N/A'`                                                            |
| IsSystem        | True if identity is `NT AUTHORITY\SYSTEM`        | Always `$false`                                                    |
| IsAdmin         | `WindowsPrincipal.IsInRole(Administrator)`       | `[Environment]::IsPrivilegedProcess` (7.4+) or `id -u` fallback    |
| UserDomainName  | AD domain or workgroup name                      | Hostname (documented gap)                                          |
| UserName        | `[Environment]::UserName`                        | `[Environment]::UserName`                                          |
| InteractiveUser | Owner of `explorer.exe`                          | loginctl graphical session, `who(1)`, or `[Environment]::UserName` |
| SessionType     | `WindowsIdentity.AuthenticationType`             | `SSH_CONNECTION` / `XDG_SESSION_TYPE` / loginctl / TTY heuristic   |
| HostName        | `[Environment]::MachineName`                     | `[Environment]::MachineName`                                       |
| ProcessId       | `$PID`                                           | `$PID`                                                             |

The adapter is used only for the `Initialize-Log` start banner. Its result is held in a local variable (`$ctx`) inside `Initialize-Log`, not stored in module scope. An earlier version cached it in `$script:WitnessContext`, but that was dead state (assigned but never read after `Initialize-Log` returned) and was removed.

The key design decision: public functions never branch on OS themselves. All platform-conditional logic lives inside `Get-PlatformContext` and the `$script:WitnessIsWindows` probe. Write-Log resolves `context=` per write using a lightweight inline check (see below), but that is the only OS-aware code outside the adapter.

## Per-write context resolution

Write-Log does not call `Get-PlatformContext` on every log line. Instead, it resolves the `context=` field directly:

- **Windows:** `[System.Security.Principal.WindowsIdentity]::GetCurrent().Name` per write. This preserves impersonation-correct identity (if the thread token changes mid-script, each log line reflects the active identity at write time).
- **Non-Windows:** `[System.Environment]::UserDomainName\[System.Environment]::UserName`. Cheap property access, no subprocess spawning.

This split exists because the original Write-Log script called `WindowsIdentity.GetCurrent()` inline at three sites. The module consolidates the heavy adapter work into `Get-PlatformContext` for the banner, then uses the lightweight per-write path for the `context=` field where calling the full adapter on every line would be wasteful.

## Log path resolution

Both `Write-Log` and `Initialize-Log` resolve the log file path through a shared chain implemented in `Resolve-WitnessLogPath`. The public function handles the first two layers (which require `$PSCmdlet.SessionState` access), then delegates to the private resolver for layers 3 and 4.

Resolution order (first non-empty value wins):

1. **Explicit parameter:** `-Logfile` on Write-Log, `-LogFilePath` on Initialize-Log.
2. **Caller scope:** The public function reads `$LogFilePath` from the caller's scope via `$PSCmdlet.SessionState.PSVariable.GetValue('LogFilePath')`. This preserves the original dot-source-era pattern where the caller just sets `$LogFilePath = '...'` before calling. Note: this works for same-session-state callers (direct calls, dot-sourced helpers). It cannot cross a foreign-module boundary; under `Import-Module`, use the explicit parameter or `$Global:LogFilePath`.
3. **Module scope:** `$script:WitnessLogFilePath`, set by `Initialize-Log`.
4. **Global scope:** `$Global:LogFilePath`, for back-compat with the legacy pattern.

If no path resolves, Write-Log and Initialize-Log report through the non-recursive failure path and return without writing the requested entry or initializing a new log target.

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
<![LOG[message text]LOG]!><time="HH:mm:ss.fff" date="MM-dd-yyyy" component="CallerName" context="DOMAIN\user" type="N" thread="PID" file="Source">
```

Field details:

- **time:** `HH:mm:ss.fff` local time only. No UTC offset suffix. The original script appended UTC offset minutes; Witness drops them on purpose so a line is always readable without timezone arithmetic.
- **date:** `MM-dd-yyyy` (CMTrace convention, not ISO).
- **component:** Auto-detected from the call stack. If the caller is a named function, uses the function name. If it is a script body, uses the script filename without extension. Overridable via `-Component`.
- **context:** Per-write identity (see above).
- **type:** Severity-to-CMTrace type code mapping (see table below).
- **thread:** Process ID (`$PID`).
- **file:** Source location from `Get-PSCallStack` (script path and line).

### Severity to type mapping

| Severity value | CMTrace type code             |
| -------------- | ----------------------------- |
| Info           | 1                             |
| Information    | 1 (mapped to Info internally) |
| Success        | 1                             |
| Warning        | 2                             |
| Error          | 3                             |
| Verbose        | 4                             |
| Debug          | 5                             |

## Secret redaction

`Write-Log` passes `$Message` through the private `ConvertTo-WitnessRedactedText` before the
CMTrace line and the console line are built, with no opt-in; `Write-LogFinal` goes through
`Write-Log`. Credential-shaped text becomes `[REDACTED]`: GitHub classic and fine-grained
tokens, AWS access key ids (including the vendor example key, an accepted false positive),
Slack tokens, PEM private keys (header and body), inline `Bearer` headers, and credentials in
URLs (`https://user:secret@host` keeps scheme and user; a single-field `https://<20+ chars>@host`
token is redacted, a short username is not). The patterns and replacement text match
the Divergent Cortex Python, TypeScript and shell loggers. `tests/Redaction.Tests.ps1` runs the
shared cases in `tests/redaction_cases.json`, the same case file those loggers run, plus a
`Write-Log` file-line check.

### Redaction known difference

.NET `\s`, used by the `Bearer` and URL patterns, matches Unicode whitespace including U+0085 but
not the separators U+001C to U+001F that pylogger's `\s` also matches. `tests/Redaction.Tests.ps1`
also times a 200000 character unbroken run.

### Failure path

`Write-Log` never throws. It cannot report a failure through itself, so every failure goes
through the private `Write-WitnessFailureLine`: one CMTrace Warning line (type 2, component
`Write-Log`) appended straight to the log file with a low-level append, or written to the
process error stream when there is no usable log file or the append itself fails. The risky
steps each own a sandwich in their own private function and return a structured result:
`New-WitnessLogDirectory`, `Invoke-WitnessRotation` (size check, rename, rotation notice),
`Add-WitnessLogLine` (lock retries and the contention note), `Invoke-WitnessAutoCleanup`,
`Write-WitnessConsoleLine`, `Get-WitnessContextUser` and `Restore-WitnessLocation`. A missing
log path no longer throws: the entry is not written and the failure line goes to the error stream.

## Size-based rotation

When a log file reaches the size threshold (default 10 MB, overridable via `$Global:WriteLogMaxSizeMB`), Write-Log renames the current file with a `_r01`, `_r02`, etc. suffix and starts a new file. The first line of the new file is a rotation notice indicating the archive filename. The rotation notice uses `[System.IO.File]::WriteAllText` with `[System.Environment]::NewLine` so the line ending matches the platform convention (CRLF on Windows, LF on Linux/macOS).

## SCCM drive handling

On Windows, if the current working directory is on a ConfigMgr `CMSite` PSDrive (detected via `$originalLocation.Provider.Name -eq 'CMSite'`), Write-Log hops to `C:` before file I/O and restores the original location in a `finally` block. This is skipped entirely when `$script:WitnessIsWindows` is false.

## Standalone distribution and preserved lineage

`Public/`, the runtime helpers in `Private/`, and the loader are the only authoring sources.
`donor-code/Write-Log.ps1` is a generated single-file distribution of those sources, not a
separate implementation. It retains the three public command names, shared private helpers,
10 MB rotation default, redaction, local timestamps, native preference gates and cleanup
sentinel. Dot-sourcing requires no module installation or import. The generator omits the
loader's strict-mode command so it does not change the caller's strict-mode setting.
A dot-sourced distribution necessarily places its helper functions and script state in the
consumer scope; manifest-based imports keep those helpers private.

From the module directory:

```powershell
./Build-WitnessDonor.ps1
./Build-WitnessDonor.ps1 -OutputPath /tmp/witness-release/Write-Log.ps1 -WhatIf
./Invoke-WitnessTests.ps1 -Suite DonorParity.Tests.ps1
```

`-OutputPath` defaults to `donor-code/Write-Log.ps1`. `-WhatIf` reads and parses sources
without changing the output artifact; build diagnostics still use
`logs/build.witness_YYYYMMDD.log`. The build-only `Private/New-WitnessDonorArtifact.ps1`
reads the loader's source order and emits UTF-8 without BOM. Output has no build timestamp.
The entry returns `Ok`, `Written`, `OutputPath`, `SourceCount`, and `Reason`; exit 0 means a
verified write or a declined ShouldProcess operation, and exit 1 means failure.
Rebuild before release synchronization. Never edit the generated artifact by hand.

`original-src/Write-Log.ps1` preserves the 596-line legacy script.
`original-src/Write-Log.20260629.ps1` preserves the 1097-line standalone rewrite from June 29.
These byte-preserved historical snapshots contain employer references and are not published.
The June rewrite already carried the module's cross-platform context, quiet defaults,
local timestamps and native preference support. Those are not differences between today's
module and generated distribution. The older snapshot's Windows-only context, enabled
debug defaults and UTC-offset timestamps remain history, not restored behavior.

The standalone repository retains its own README, SECURITY, CONTRIBUTING, workflows,
license and root changelog. Its release process materializes actual canonical source files
in a separate release tree; the local development symlink must never replace GitHub source
files. GitHub publication is an explicit operator action, not a side effect of a canonical
source edit.

The shipped `Get-BannerConfig.ps1` and `config/banner.psd1` are not loaded or consumed by
`Initialize-Log`. Its public parameters remain LogFilePath, ScriptName and Version.
No configurable-banner capability is implied by these retained files.

## Native debug/verbose preference gate

Write-Log honors the standard PowerShell preference variables (`$DebugPreference`, `$VerbosePreference`) as the master "on" switch for debug and verbose output. A consumer who runs their script or function with `-Debug` or `-Verbose`, or who sets `$DebugPreference`/`$VerbosePreference` directly, gets debug/verbose output from Write-Log automatically with no custom flags required. This matches the behavior of Microsoft's own `Write-Debug`/`Write-Verbose`.

### The module boundary subtlety

Write-Log is a module function. Preference variables set in the caller's scope or in an ancestor function's scope do NOT flow into a module function automatically via the standard `$DebugPreference` variable. The module has its own session state and its own copy of `$DebugPreference`, which defaults to `'SilentlyContinue'`.

The fix is `$PSCmdlet.GetVariableValue('DebugPreference')`. This method walks the dynamic scope chain - caller, parent, grandparent - and crosses the module session-state boundary to find the value the caller or its ancestor set. It is the only reliable way to read a preference variable that was set by `-Debug`/`-Verbose` on a parent function when the callee is in a different module session-state.

Verified empirically: reading `$DebugPreference` directly inside Write-Log always returns the module's own default (`'SilentlyContinue'`) even when the calling script or function was invoked with `-Debug`. `$PSCmdlet.GetVariableValue('DebugPreference')` returns `'Continue'` in the same scenario. This is the implementation Write-Log uses.

### Precedence model

The three sources are evaluated per message, per surface (console and logfile independently):

1. **Native preference variable** (`$DebugPreference`/`$VerbosePreference` read via `GetVariableValue`): master "on" switch. When active (any value that is not `'SilentlyContinue'`), enables BOTH console and file for that severity, overriding the per-surface controls.
2. **`$Global:DebugConsole`/`$Global:DebugLogfile`** (and Verbose equivalents): per-surface fine-grained overrides. Consumers who set only `$Global:DebugLogfile = $true` get file-only output without touching the native mechanism. Old consumers who already use these flags continue to work unchanged.
3. **`$script:Witness*` module defaults** (set in the `.psm1` loader, all `$false`): fallback when neither the native preference nor a `$Global:` override is set.

Default behavior: with no `-Debug`/`-Verbose`, no preference set, and no `$Global:` flags, debug and verbose produce nothing on either surface.

### Robust comparison

The gate uses `-ne 'SilentlyContinue'` rather than `-eq 'Continue'`. PowerShell can set preference variables to `'Inquire'`, `'Break'`, or `'Stop'`, all of which indicate that output is wanted. Testing for equality with `'Continue'` would miss those cases. The `-ne 'SilentlyContinue'` check correctly classifies all "active" states.

## PS 5.1 compatibility

Windows PowerShell 5.1 is the original deployment target. The module avoids all PS 7+ syntax:

- No ternary operators (`? :`). All conditionals use `if/else`.
- No null-coalescing (`??`). Explicit null checks throughout.
- `$IsWindows` is never referenced directly. The module-scope probe `Test-Path Variable:IsWindows` handles 5.1 where the automatic variable does not exist.
- `$IsMacOS` is similarly guarded with `Test-Path Variable:IsMacOS` inside `Get-PlatformContext`.
- `[Environment]::IsPrivilegedProcess` (requires .NET 8+, which ships with PS 7.4+) is wrapped in a try/catch with an `id -u` fallback that only runs on non-Windows systems.
