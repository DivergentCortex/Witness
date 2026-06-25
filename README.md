# DivergentCortex.Witness

**There is always a Witness.**

A hardened, cross-platform, CMTrace-compatible logging module for PowerShell. Born from four years of daily use in SCCM deployments, scheduled tasks, and remote automation on Windows, then rebuilt as a proper module that runs everywhere PowerShell does.

Three exported functions. Zero breaking changes from the original. Drop it into an existing script and it works the same way it always did, except now it also runs on Linux and macOS.

## Platform support

| Runtime | OS | Status |
|---|---|---|
| Windows PowerShell 5.1 | Windows | Full support (original target) |
| PowerShell 7.4+ | Windows | Full support |
| PowerShell 7.4+ | Linux | Full support (see cross-platform notes) |
| PowerShell 7.4+ | macOS | Full support (see cross-platform notes) |

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

# Set a log path and initialize
$logPath = Join-Path $PSScriptRoot ("logs\MyScript_{0}.log" -f (Get-Date -Format 'yyyyMMdd'))
Initialize-Log -LogFilePath $logPath -ScriptName 'MyScript' -Version '1.0'

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

| Severity | Aliases | CMTrace type code | Console color |
|---|---|---|---|
| Info | Information | 1 | White |
| Success | | 1 | Green |
| Warning | | 2 | Yellow |
| Error | | 3 | Red |
| Verbose | | 4 | Dark gray |
| Debug | | 5 | Magenta |

## Write-Log parameters

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| Message | string | Yes | | The message to log. Accepts pipeline input. |
| Logfile | string | No | (resolved) | Path to the log file. Falls back through the resolution chain described below. |
| Severity | string | No | Info | Log level. ValidateSet: Info, Information, Warning, Error, Verbose, Debug, Success. |
| Component | string | No | (auto) | Override the auto-detected component name from the call stack. |
| WriteBackToHost | switch | No | $true | Write formatted output to the console alongside the log file. |
| MaxRetries | int | No | 3 | Retry attempts when the file is locked by another process. |
| RetryDelay | double | No | 0.5 | Seconds between retry attempts. |
| Color | ConsoleColor | No | (severity) | Override the console color for this message. |

**Aliases for Severity:** The `-Severity` parameter also responds to `-LogLevel`, `-Type`, and `-level`.

## Log path resolution

Write-Log and Initialize-Log resolve the log file path through a layered chain. The first non-empty value wins:

1. Explicit `-Logfile` (Write-Log) or `-LogFilePath` (Initialize-Log) parameter
2. `$LogFilePath` in the caller's scope (read via `$PSCmdlet.SessionState`; works for same-session-state callers, not across module boundaries)
3. `$script:WitnessLogFilePath` (set internally by Initialize-Log)
4. `$Global:LogFilePath` (back-compat with the original dot-source pattern)

If none of these resolve, Write-Log throws. The safest pattern under `Import-Module` is to pass the path to `Initialize-Log -LogFilePath` explicitly, or set `$Global:LogFilePath` before the first call.

## How it works

The module's internal structure follows a one-file-per-function layout with a platform adapter that keeps OS-specific logic out of the public functions.

**Get-PlatformContext** (private) is the cross-platform adapter. It runs once during `Initialize-Log` to collect identity, elevation status, hostname, interactive user, session type, and platform string. Each field branches internally on `$script:WitnessIsWindows` (a 5.1-safe platform probe set at module load), so the public functions never branch on OS themselves.

The adapter result is used only for the Initialize-Log start banner. Write-Log resolves `context=` cheaply per write: `WindowsIdentity.GetCurrent().Name` on Windows, `[Environment]::UserDomainName\UserName` on non-Windows. This keeps impersonation-correct identity on Windows without running the full adapter on every log line.

For details on module internals, see [docs/ARCHITECTURE.md](DivergentCortex.Witness/docs/ARCHITECTURE.md).

## Configuration

These module-scope defaults can be overridden with global variables before or after import:

| Global variable | Default | Effect |
|---|---|---|
| `$Global:WriteLogMaxSizeMB` | 10 | Rotate the log file when it exceeds this size in MB |
| `$Global:WriteLogMaxAgeDays` | 7 | Delete log files older than this many days |
| `$Global:WriteLogAutoCleanup` | $true | Run age-based cleanup once per session |
| `$Global:VerboseConsole` | $true | Show Verbose entries in the console |
| `$Global:VerboseLogfile` | $true | Write Verbose entries to the log file |
| `$Global:DebugConsole` | $true | Show Debug entries in the console |
| `$Global:DebugLogfile` | $true | Write Debug entries to the log file |

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

MIT. Copyright (c) 2023-2026 Curtis Leggett. See [LICENSE](LICENSE).

DivergentCortex.Witness is part of the [DivergentCortex](https://github.com/DivergentCortex) module line.
