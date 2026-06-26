<!-- logo banner goes here once finalized -->

# DivergentCortex.Witness

*the observer of the unsaid, the truth within the artifacts*

[![CI](https://github.com/DivergentCortex/Witness/actions/workflows/test.yml/badge.svg)](https://github.com/DivergentCortex/Witness/actions/workflows/test.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE) ![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Linux%20%7C%20macOS-lightgrey) ![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207.4%2B-blue)

---

- Color-coded console output, live. Severity at a glance, success green, warning yellow, error red. You watch what is happening as it runs instead of squinting at a wall of white text.
- Every line knows where it came from, the function and line that wrote it, stamped in automatically.
- When it fails, it points at the exact spot. That is the difference between debugging for an hour and fixing it in a minute.

It also writes a permanent CMTrace-compatible record to disk for the audit trail and the CMTrace viewer, but the thing you feel every day is the console. That is the visibility.

This is the logging backbone of an entire PowerShell fleet, hundreds of scripts, every server, for years, from SCCM deployments to database jobs to reboot prompts to security tooling. Built because every other PowerShell logger out there does nothing worth using. If you have gone looking for a good one, you already know.

## See it work

A quick run of examples/Example-Usage.ps1:

```
[ INFO    ] [Test-Wareh..] [125]: Endpoint reachable. Latency: 38ms.
[ WARNING ] [Get-Widget..] [64]: SKU WGT-200 is out of stock in 'WH-01'.
[ SUCCESS ] [Get-Widget..] [74]: Inventory read complete. 3 SKUs returned.
[ ERROR   ] [Invoke-Wid..] [103]: Reorder failed for SKU=WGT-200. Detail: item discontinued.
```

That error did not come with a tag. Witness read the call stack and recorded exactly where it happened, in the log file:

```
component="Invoke-WidgetReorder"  file="Example-Usage.ps1: line 103"  type="3"
```

Function and line number, automatically. That is the difference.

## Platform support

| Runtime                | OS      | Status                                  |
| ---------------------- | ------- | --------------------------------------- |
| Windows PowerShell 5.1 | Windows | Full support (original target)          |
| PowerShell 7.4+        | Windows | Full support                            |
| PowerShell 7.4+        | Linux   | Full support (see cross-platform notes) |
| PowerShell 7.4+        | macOS   | Full support (see cross-platform notes) |

## Install

PSGallery publish is planned but not yet live. For now, clone and import directly:

```powershell
git clone https://github.com/DivergentCortex/Witness.git
Import-Module ./Witness/DivergentCortex.Witness/DivergentCortex.Witness.psd1
```

Or copy the `DivergentCortex.Witness` folder into any directory on your `$env:PSModulePath` and import by name:

```powershell
Import-Module DivergentCortex.Witness
```

## Quick start

```powershell
Import-Module DivergentCortex.Witness

# Set a log path and initialize (logs/ folder beside the script, gitignored)
Initialize-Log -LogFilePath "$PSScriptRoot/logs/MyScript.log" -ScriptName 'MyScript' -Version '1.0'

# Log at different severities
Write-Log -Message 'Starting work'              -Severity Info
Write-Log -Message 'Heads up, check this'       -Severity Warning
Write-Log -Message 'That did not go well'       -Severity Error
Write-Log -Message 'Operation completed cleanly' -Severity Success

# Wrap up and trigger cleanup
Write-LogFinal -Message 'Script finished.'
```

Every call writes a CMTrace-formatted line to the log file and prints a color-coded line to the console. The component field fills itself from the call stack, so you rarely need to set it by hand.

## Severity levels

| Severity | Aliases     | CMTrace type code | Console color |
| -------- | ----------- | ----------------- | ------------- |
| Info     | Information | 1                 | White         |
| Success  |             | 1                 | Green         |
| Warning  |             | 2                 | Yellow        |
| Error    |             | 3                 | Red           |
| Verbose  |             | 4                 | Dark gray     |
| Debug    |             | 5                 | Magenta       |

## Write-Log parameters

| Parameter       | Type         | Required | Default    | Description                                                                         |
| --------------- | ------------ | -------- | ---------- | ----------------------------------------------------------------------------------- |
| Message         | string       | Yes      |            | The message to log. Accepts pipeline input.                                         |
| Logfile         | string       | No       | (resolved) | Path to the log file. Falls back through the resolution chain described below.      |
| Severity        | string       | No       | Info       | Log level. ValidateSet: Info, Information, Warning, Error, Verbose, Debug, Success. |
| Component       | string       | No       | (auto)     | Override the auto-detected component name from the call stack.                      |
| WriteBackToHost | switch       | No       | $true      | Write formatted output to the console alongside the log file.                       |
| MaxRetries      | int          | No       | 3          | Retry attempts when the file is locked by another process.                          |
| RetryDelay      | double       | No       | 0.5        | Seconds between retry attempts.                                                     |
| Color           | ConsoleColor | No       | (severity) | Override the console color for this message.                                        |

**Aliases for Severity:** The `-Severity` parameter also responds to `-LogLevel`, `-Type`, and `-level`.

## Log path resolution

Write-Log and Initialize-Log resolve the log file path through a layered chain. The first non-empty value wins:

1. Explicit `-Logfile` (Write-Log) or `-LogFilePath` (Initialize-Log) parameter
2. `$LogFilePath` in the caller's scope (read via `$PSCmdlet.SessionState`; works for same-session-state callers, not across module boundaries)
3. `$script:WitnessLogFilePath` (set internally by Initialize-Log)
4. `$Global:LogFilePath` (back-compat with the original dot-source pattern)

If none of these resolve, Write-Log throws. The safest pattern under `Import-Module` is to pass the path to `Initialize-Log -LogFilePath` explicitly, or set `$Global:LogFilePath` before the first call.

## How it works

Built modular for easy maintenance, easy additions, and a readable structure.

**Get-PlatformContext** (private) is the cross-platform adapter. It runs once during `Initialize-Log` to collect identity, elevation status, hostname, interactive user, session type, and platform string. Each field branches internally on `$script:WitnessIsWindows` (a 5.1-safe platform probe set at module load), so the public functions never branch on OS themselves.

The adapter result is used only for the Initialize-Log start banner. Write-Log resolves `context=` cheaply per write: `WindowsIdentity.GetCurrent().Name` on Windows, `[Environment]::UserDomainName\UserName` on non-Windows. This keeps impersonation-correct identity on Windows without running the full adapter on every log line.

For details on module internals, see [docs/ARCHITECTURE.md](DivergentCortex.Witness/docs/ARCHITECTURE.md).

## Native debug and verbose control

Write-Log honors the standard PowerShell preference variables. A consumer who invokes their script or function with `-Debug` or `-Verbose` gets debug/verbose output from Write-Log automatically, with no flags required.

```powershell
# Run your script with -Debug: every Write-Log -Severity Debug call emits automatically
.\MyScript.ps1 -Debug

# Set the preference directly in scope - same effect
$DebugPreference = 'Continue'
Write-Log -Message 'Diagnosing state' -Severity Debug

# -Verbose works identically
$VerbosePreference = 'Continue'
Write-Log -Message 'Processing item 42' -Severity Verbose
```

This matches how `Write-Debug` and `Write-Verbose` behave. When the preference is `'SilentlyContinue'` (the default) and no `$Global:` flags are set, debug and verbose produce nothing.

### Module boundary note

Write-Log is a module function. PowerShell's preference variable propagation does NOT automatically cross the module session-state boundary - reading `$DebugPreference` directly inside the module always returns the module's own default (`'SilentlyContinue'`), even when the calling script set it to `'Continue'`. Write-Log reads preference variables with `$PSCmdlet.GetVariableValue('DebugPreference')`, which walks the dynamic scope chain and crosses the module boundary correctly. This is the only reliable mechanism for module functions.

### Precedence

The three sources are evaluated independently per surface (console and log file):

1. Native `$DebugPreference`/`$VerbosePreference` (via `GetVariableValue`): master "on" switch. When active, enables both console and file output.
2. `$Global:DebugConsole`/`$Global:DebugLogfile` (and Verbose equivalents): per-surface overrides. These still work unchanged for back-compat.
3. Module defaults (all `$false`): baseline when neither of the above is set.

## Configuration

These module-scope defaults can be overridden with global variables before or after import:

| Global variable               | Default | Effect                                                       |
| ----------------------------- | ------- | ------------------------------------------------------------ |
| `$Global:WriteLogMaxSizeMB`   | 10      | Rotate the log file when it exceeds this size in MB          |
| `$Global:WriteLogMaxAgeDays`  | 7       | Delete log files older than this many days                   |
| `$Global:WriteLogAutoCleanup` | $true   | Run age-based cleanup once per session                       |
| `$Global:VerboseConsole`      | $false  | Show Verbose entries in the console (back-compat override)   |
| `$Global:VerboseLogfile`      | $false  | Write Verbose entries to the log file (back-compat override) |
| `$Global:DebugConsole`        | $false  | Show Debug entries in the console (back-compat override)     |
| `$Global:DebugLogfile`        | $false  | Write Debug entries to the log file (back-compat override)   |

## Cross-platform notes

The module reaches full behavioral parity on Linux and macOS for everything that has a real equivalent. Honest gaps:

- **LogonType:** Always `N/A` on non-Windows. Windows uses `WindowsIdentity.AuthenticationType`; there is no direct counterpart on Linux/macOS.
- **UserDomainName:** Returns the hostname on Linux/macOS. There are no AD domain semantics outside Windows; `[Environment]::UserDomainName` returns the machine name, and the module surfaces that honestly rather than faking a domain.
- **Interactive user detection:** Windows checks for `explorer.exe` ownership. Linux uses a tiered approach: `loginctl` for graphical sessions, `who(1)` as fallback, `[Environment]::UserName` as last resort.
- **Session type:** Windows uses `WindowsIdentity.AuthenticationType`. Non-Windows layers `SSH_CONNECTION`, `XDG_SESSION_TYPE`, `loginctl`, and TTY detection.
- **SCCM/CMSite drive handling:** Windows-only. The module detects when the working directory is on a ConfigMgr PSDrive, hops to `C:` for file I/O, then restores the original location. This code path is skipped entirely on non-Windows.
- **Elevation:** Windows uses `WindowsPrincipal.IsInRole(Administrator)`. PowerShell 7.4+ on Linux/macOS uses `[Environment]::IsPrivilegedProcess`; older builds fall back to `id -u`.

For the full research with sources, see [docs/CROSS-PLATFORM.md](DivergentCortex.Witness/docs/CROSS-PLATFORM.md).

## Viewing logs

Open `.log` files in [CMTrace](https://learn.microsoft.com/en-us/mem/configmgr/core/support/cmtrace), part of the Configuration Manager toolkit. The log format is CMTrace-native, so entries render with proper severity coloring, timestamps, and component labels out of the box.

On Linux and macOS where CMTrace is not available, the files are still human-readable XML-ish lines. Any text editor works; the structured format (`<![LOG[...]LOG]!>`) is parseable with standard text tools.

## License

MIT. Copyright (c) 2023-2026 Divergent Cortex. See [LICENSE](LICENSE).

DivergentCortex.Witness is part of the [DivergentCortex](https://github.com/DivergentCortex) module line.
