# Cross-Platform Identity and Context: Windows to Linux/macOS

## Purpose

DivergentCortex.Witness is a CMTrace-compatible structured logger for PowerShell, rebuilt from the
Write-Log donor script (`donor-code/Write-Log.ps1`). The donor is a Windows-only function that uses
Win32 security principals, WMI, and SCCM APIs to populate CMTrace log fields (context, component,
thread). The rebuild targets Windows, Linux, and macOS under PowerShell 7.

The donor script is the untouched specification. It is not modified. The rebuild reads its behavior,
replicates it where the platform allows, and substitutes verified equivalents where it does not.

This document records the verified cross-platform equivalent for each Windows-specific identity and
context mechanism the donor uses. Every idiom below was independently researched and then verified
against primary .NET runtime source, POSIX specifications, and man pages. The verdict column records
whether the verifier confirmed the idiom or flagged corrections. All source URLs are preserved as
the permanent citation record for this research.

---

## 1. Process Identity / Username

**What the donor does:** Retrieves the current process owner as a `DOMAIN\username` string for the
CMTrace `context=` field.

**Windows API:** `[System.Security.Principal.WindowsIdentity]::GetCurrent().Name` at donor lines
258, 351, and 399.

**Verdict:** needs-correction

The proposed idiom works on Linux in isolation, but shipping it without the `$IsWindows` guard
causes Windows behavior to regress (loses AD domain name, loses impersonation token). The guard
is the correct implementation: Windows keeps the full WindowsIdentity path; Linux uses the
Environment API path.

### Verified Linux/PS7 Idiom

```powershell
# Cross-platform username for the CMTrace context= field:
$context = if ($IsWindows) {
    [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
} else {
    "$([System.Environment]::UserDomainName)\$([System.Environment]::UserName)"
}

# Bare username (logging, auditing, preferred for cross-platform scripts):
[System.Environment]::UserName
```

### Caveats

- `[Environment]::UserName` returns the effective user (euid), not the real/login user. Under
  `sudo`, it returns `root`, not the invoking user. To get the login user under sudo, check
  `$env:SUDO_USER`, but note this can be spoofed.
- `[Environment]::UserDomainName` on Linux always returns the machine hostname. The .NET source
  (`Environment.UnixOrBrowser.cs`) literally aliases it to `MachineName`. It does not return an AD
  domain even if the box is joined via SSSD/realmd. The resulting `hostname\username` string is
  structurally equivalent to the Windows standalone-machine format but carries no domain semantics.
- `[WindowsIdentity]::GetCurrent()` throws `System.PlatformNotSupportedException` on Linux. Any
  cross-platform code must guard this call with `$IsWindows`.
- No special permissions required. `[Environment]::UserName` calls `getpwuid_r()` which reads
  `/etc/passwd` or NSS-configured backends.
- Shell-out fallbacks: `whoami` or `id -un` return the effective username. Both require coreutils.
- `$env:USER` is less reliable than `[Environment]::UserName` because it can be unset or tampered
  with. The .NET API queries the OS directly via `getpwuid_r()`.

### Sources

- [Environment.UserName Property (.NET API docs): confirms Unix wraps getpwuid_r](https://learn.microsoft.com/en-us/dotnet/api/system.environment.username?view=net-9.0)
- [dotnet/runtime Environment.Unix.cs: UserName => GetUserNameFromPasswd(GetEUid())](https://github.com/dotnet/runtime/blob/main/src/libraries/System.Private.CoreLib/src/System/Environment.Unix.cs)
- [dotnet/runtime Environment.UnixOrBrowser.cs: UserDomainName => MachineName](https://raw.githubusercontent.com/dotnet/runtime/main/src/libraries/System.Private.CoreLib/src/System/Environment.UnixOrBrowser.cs)
- [Environment.UserDomainName Property: fallback to host computer name when not domain-joined](https://learn.microsoft.com/en-us/dotnet/api/system.environment.userdomainname?view=net-10.0)
- [Microsoft Learn Q&A: WindowsIdentity.GetCurrent() on Linux throws PlatformNotSupportedException](https://learn.microsoft.com/en-us/answers/questions/175614/how-to-get-windows-username-in-an-asp-net-core-3-1)
- [dotnet/standard issue #1279: WindowsIdentity API is Windows-specific](https://github.com/dotnet/standard/issues/1279)
- [Stack Overflow: current username in PowerShell, confirms [Environment]::UserName cross-platform](https://stackoverflow.com/questions/2085744/how-do-i-get-the-current-username-in-windows-powershell)
- [getpwuid_r(3) man page: the POSIX function .NET calls on Unix](https://man7.org/linux/man-pages/man3/getpwuid_r.3.html)
- [whoami(1) man page: print effective user name](https://man7.org/linux/man-pages/man1/whoami.1.html)
- [id(1) man page: print effective user ID/name](https://man7.org/linux/man-pages/man1/id.1.html)
- [PowerShell differences on non-Windows platforms: .NET Core subset behavior](https://learn.microsoft.com/en-us/powershell/scripting/whats-new/unix-support?view=powershell-7.6)

---

## 2. Admin / Elevation Status

**What the donor does:** Checks whether the current process is running with administrator/root
privileges.

**Windows API:** `([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)`

**Verdict:** confirmed

### Verified Linux/PS7 Idiom

```powershell
[System.Environment]::IsPrivilegedProcess
```

### Caveats

- **Version gate:** `[System.Environment]::IsPrivilegedProcess` requires .NET 8.0+, which means
  PowerShell 7.4 or later. PS 7.2 and 7.3 do not have this API. For those versions, fall back to
  `(id -u) -eq 0`.
- The underlying call is `geteuid(2)`, which returns the effective UID, not the real UID. A process
  launched via `sudo` has euid 0 even if the real uid is nonzero. This is the correct behavior for
  privilege detection.
- The .NET runtime caches the result after the first call. If a process somehow changes its euid
  during execution (requires `CAP_SETUID`, extremely rare), the cached value will be stale.
- Inside a user namespace (rootless containers), euid can be 0 relative to the namespace while the
  process has no real host-level root privileges. `IsPrivilegedProcess` returns `true` in that case.
- No special permissions required. `geteuid(2)` always succeeds per POSIX.
- Full cross-platform pattern for modules supporting PS 7.2+:

```powershell
if ($IsWindows) {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
} else {
    # Prefer .NET 8+ API, fall back to id(1)
    try { $isAdmin = [System.Environment]::IsPrivilegedProcess }
    catch { $isAdmin = (id -u) -eq 0 }
}
```

### Sources

- [dotnet/runtime Environment.Unix.cs: IsPrivilegedProcessCore() => GetEUid() == 0](https://raw.githubusercontent.com/dotnet/runtime/main/src/libraries/System.Private.CoreLib/src/System/Environment.Unix.cs)
- [dotnet/runtime Environment.cs: IsPrivilegedProcess property with caching](https://raw.githubusercontent.com/dotnet/runtime/main/src/libraries/System.Private.CoreLib/src/System/Environment.cs)
- [dotnet/runtime Environment.Windows.cs: Windows IsPrivilegedProcessCore via TOKEN_ELEVATION](https://raw.githubusercontent.com/dotnet/runtime/main/src/libraries/System.Private.CoreLib/src/System/Environment.Windows.cs)
- [dotnet/runtime Interop.GetEUid.cs: P/Invoke wrapper for geteuid(2)](https://github.com/dotnet/runtime/blob/main/src/libraries/Common/src/Interop/Unix/System.Native/Interop.GetEUid.cs)
- [dotnet/runtime issue #68770: API Proposal for IsPrivilegedProcess (milestone 8.0.0)](https://github.com/dotnet/runtime/issues/68770)
- [dotnet/runtime PR #77355: Implement Environment.IsPrivilegedProcess (merged 2022-11-03)](https://github.com/dotnet/runtime/pull/77355)
- [git blame Environment.Unix.cs: IsPrivilegedProcessCore added commit aaf9c8a](https://github.com/dotnet/runtime/blame/main/src/libraries/System.Private.CoreLib/src/System/Environment.Unix.cs)
- [geteuid(2) man page: POSIX.1-2024, always succeeds, returns effective UID](https://man7.org/linux/man-pages/man2/geteuid.2.html)
- [PowerShell Support Lifecycle: version-to-.NET mapping (7.4=.NET 8, 7.5=.NET 9, 7.6=.NET 10)](https://learn.microsoft.com/en-us/powershell/scripting/install/powershell-support-lifecycle?view=powershell-7.6)
- [Programmatically elevate a .NET application on any platform (cross-platform geteuid check)](https://anthonysimmon.com/programmatically-elevate-dotnet-app-on-any-platform/)
- [GitHub Gist: cross-platform PowerShell Test-IsAdmin using (id -u) on Unix](https://gist.github.com/jhochwald/46014a3de425dc21c1f1f7e31cd49cf1)

---

## 3. Machine / Host Name

**What the donor does:** Gets the local machine name for log context and file paths.

**Windows API:** `[System.Environment]::MachineName` (and `$env:COMPUTERNAME`).

**Verdict:** confirmed

### Verified Linux/PS7 Idiom

```powershell
[System.Environment]::MachineName
```

### Caveats

- No special permissions required. The underlying `gethostname()` syscall is unprivileged.
- On Unix, `MachineName` calls `gethostname()` then strips everything after the first dot. A
  hostname of `server1.example.com` returns `server1`. This matches the Windows short-name behavior.
- POSIX `HOST_NAME_MAX` is 255 bytes. Linux's actual limit is typically 64 bytes (`__NEW_UTS_LEN`),
  well below the .NET 256-byte buffer. No silent truncation in practice.
- Unlike Windows where `COMPUTERNAME` is static until reboot, on Linux `gethostname()` reflects
  runtime changes made via `sethostname()`. `MachineName` is not cached and will reflect hostname
  changes during process lifetime (documented in dotnet/runtime issue #122077).
- `$env:COMPUTERNAME` does not exist on Linux (PowerShell issue #2312, closed by design). Do not
  use it cross-platform.
- `$env:HOSTNAME` is set by bash but not exported by default. If pwsh is launched from a non-bash
  shell, a login shell, or a service manager, this variable will be missing.
- `[System.Net.Dns]::GetHostName()` also calls `gethostname()` but does NOT strip dots, so it may
  return an FQDN. Use only if you want the full hostname.

### Sources

- [dotnet/runtime Environment.Unix.cs: MachineName calls gethostname(), truncates at first dot](https://github.com/dotnet/runtime/blob/main/src/libraries/System.Private.CoreLib/src/System/Environment.Unix.cs)
- [dotnet/runtime Interop.GetHostName.cs: Unix interop with HOST_NAME_MAX buffer](https://github.com/dotnet/runtime/blob/main/src/libraries/Common/src/Interop/Unix/System.Native/Interop.GetHostName.cs)
- [Environment.MachineName Property (.NET API docs)](https://learn.microsoft.com/en-us/dotnet/api/system.environment.machinename?view=net-9.0)
- [about_Environment_Variables (PowerShell 7.6): case-sensitive on non-Windows](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_environment_variables?view=powershell-7.6)
- [PowerShell issue #2312: $env:COMPUTERNAME missing on Linux, closed by design](https://github.com/PowerShell/PowerShell/issues/2312)
- [dotnet/runtime issue #122077: MachineName inconsistent semantics across platforms](https://github.com/dotnet/runtime/issues/122077)
- [Stack Overflow: get computer name in .NET, confirms MachineName vs Dns.GetHostName differences](https://stackoverflow.com/questions/1768198/how-do-i-get-the-computer-name-in-net)
- [Dns.GetHostName Method (.NET API docs)](https://learn.microsoft.com/en-us/dotnet/api/system.net.dns.gethostname?view=net-10.0)

---

## 4. Domain-Qualified User Identity

**What the donor does:** Constructs a `DOMAIN\username` string for the CMTrace `context=` field,
where the domain portion comes from the Windows security token.

**Windows API:** `[System.Security.Principal.WindowsIdentity]::GetCurrent().Name` returns the
SAM-format `DOMAIN\user`. On standalone machines, the domain portion is the computer name.

**Verdict:** confirmed

### Verified Linux/PS7 Idiom

```powershell
[System.Environment]::UserDomainName
```

### Caveats

- **Partial equivalence, not full.** `UserDomainName` exists on Linux and will not throw, but it
  returns the short hostname, not a security domain. The .NET source (`Environment.UnixOrBrowser.cs`)
  defines it as `=> MachineName`. It never returns an AD domain even when the Linux machine is
  AD-joined via SSSD/realmd.
- `$env:USERDOMAIN` does not exist on Linux. It will be `$null`.
- The "domain" concept on Linux is fragmented across unrelated systems:
  - **DNS domain:** accessible via `hostname -d`. Also via `[System.Net.Dns]::GetHostName()` which
    may return an FQDN depending on `/etc/hosts` and resolver config.
  - **NIS/YP domain:** `[Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().DomainName`
    calls `getdomainname(2)`, which returns the NIS domain, NOT the DNS domain. Typically empty or
    `(none)` on modern systems.
  - **AD domain (SSSD/realmd):** stored in `/etc/sssd/sssd.conf` (mode 0600, requires root to read).
    Users are formatted as `user@domain.example.com` (Kerberos UPN), not `DOMAIN\user` (SAM).
- On a Linux machine where the hostname is an FQDN (e.g., `myhost.example.com`), `MachineName` and
  therefore `UserDomainName` return only `myhost` because .NET strips everything after the first dot.
- **Recommended approach for the logging module:** use `[Environment]::UserDomainName` as-is. On
  Windows it returns the AD domain; on Linux it returns the short hostname. The resulting
  `DOMAIN\user` on Windows becomes `hostname\user` on Linux. This is the closest structural
  equivalent and matches what .NET itself considers the cross-platform answer.

### Sources

- [dotnet/runtime Environment.UnixOrBrowser.cs line 58: UserDomainName => MachineName](https://github.com/dotnet/runtime/blob/main/src/libraries/System.Private.CoreLib/src/System/Environment.UnixOrBrowser.cs)
- [dotnet/runtime Environment.Unix.cs: MachineName calls gethostname(2), strips domain suffix](https://github.com/dotnet/runtime/blob/main/src/libraries/System.Private.CoreLib/src/System/Environment.Unix.cs)
- [dotnet/runtime Environment.Windows.cs: UserDomainName calls GetUserNameExW(NameSamCompatible)](https://github.com/dotnet/runtime/blob/main/src/libraries/System.Private.CoreLib/src/System/Environment.Windows.cs)
- [Environment.UserDomainName Property docs: confirms Unix source and fallback behavior](https://learn.microsoft.com/en-us/dotnet/api/system.environment.userdomainname?view=net-9.0)
- [Environment.UserName Property docs: confirms Unix wraps getpwuid_r](https://learn.microsoft.com/en-us/dotnet/api/system.environment.username?view=net-9.0)
- [dotnet/runtime HostInformationPal.Unix.cs: IPGlobalProperties.DomainName calls getdomainname(2)](https://github.com/dotnet/runtime/blob/main/src/libraries/Common/src/System/Net/NetworkInformation/HostInformationPal.Unix.cs)
- [dotnet/runtime Interop.GetDomainName.cs: wraps getdomainname(2), converts "(none)" to empty](https://github.com/dotnet/runtime/blob/main/src/libraries/Common/src/Interop/Unix/System.Native/Interop.GetDomainName.cs)
- [hostname(1) man page: hostname -d (DNS domain), domainname (NIS/YP domain)](https://man7.org/linux/man-pages/man1/hostname.1.html)
- [Ubuntu Server docs: SSSD with Active Directory, user format is user@domain not DOMAIN\user](https://ubuntu.com/server/docs/how-to/sssd/with-active-directory/)
- [Debian manpages: realm(8) for realm list on AD-joined machines](https://manpages.debian.org/testing/realmd/realm.8.en.html)

---

## 5. Interactive Console/Desktop User

**What the donor does:** Identifies the human at the console (the interactive desktop user), as
distinct from the process owner. On Windows, this is typically detected by finding the owner of
`explorer.exe`.

**Windows API:** `Get-Process -Name explorer -IncludeUserName` to find the desktop shell owner.

**Verdict:** needs-correction

The verifier found that `loginctl show-session ... --value` can return trailing whitespace or
carriage returns on some systemd builds. Without `.Trim()`, the `-in 'x11','wayland'` comparison
fails silently, causing the code to fall through to weaker tiers. The corrected idiom includes
`.Trim()` on the `$type` assignment and a `Where-Object` filter in the `who(1)` block to skip
empty lines.

### Verified Linux/PS7 Idiom

```powershell
$interactiveUser = $null

# Tier 1: loginctl (systemd), enumerate sessions, find graphical ones
try {
    $raw = loginctl list-sessions --no-legend 2>$null
    if ($LASTEXITCODE -eq 0 -and $raw) {
        foreach ($line in $raw -split "`n") {
            $fields = $line.Trim() -split '\s+'
            if ($fields.Count -ge 3) {
                $sessionId   = $fields[0]
                $sessionUser = $fields[2]
                # --value suppresses the "Type=" prefix; .Trim() guards trailing whitespace/CR
                $type = (loginctl show-session $sessionId -p Type --value 2>$null).Trim()
                if ($type -in 'x11', 'wayland') {
                    $interactiveUser = $sessionUser
                    break
                }
            }
        }
    }
} catch {}

# Tier 2: who(1), traditional utmp-based, works on non-systemd distros
if (-not $interactiveUser) {
    try {
        $whoOutput = who 2>$null
        if ($LASTEXITCODE -eq 0 -and $whoOutput) {
            $interactiveUser = ($whoOutput -split "`n" |
                Where-Object { $_ -match '\S' } |
                Select-Object -First 1) -split '\s+' |
                Select-Object -First 1
        }
    } catch {}
}

# Tier 3: [Environment]::UserName - process owner, NOT interactive user (last resort)
# [Environment]::UserName is more reliable than $env:USER: it calls getpwuid_r() directly
# via the .NET PAL and cannot be tampered with by unsetting or overriding the env var.
# $env:USER can be unset in non-login shells, containers, and service contexts.
if (-not $interactiveUser) {
    $interactiveUser = [System.Environment]::UserName
}

$interactiveUser
```

### Caveats

- **No single .NET/PowerShell cross-platform API provides "interactive desktop user" on Linux.**
  `[Environment]::UserName` returns the process owner (via euid + getpwuid_r), not the desktop
  user. When running as root or a systemd service, it returns `root`.
- `loginctl` requires systemd-logind (standard on Ubuntu, Fedora, Debian, Arch, RHEL, SUSE; absent
  on Alpine, Void, Artix, and containers without systemd). No elevated privileges needed.
- `who(1)` requires `/var/run/utmp` to be maintained; some minimal or containerized distros do not
  populate utmp.
- `Get-Process` on Linux (pwsh 7) does NOT support `-IncludeUserName`; that parameter is
  Windows-only.
- **Headless servers:** loginctl finds no x11/wayland session, `who` may find SSH sessions. The
  code falls through to `$env:USER` which returns the process owner.
- **Multiple graphical sessions:** the code takes the first one found. Linux supports multiple
  concurrent X/Wayland sessions; there is no single-process equivalent to Windows explorer.exe.
- **Containers and WSL:** loginctl is typically absent; `who` may be absent; `$env:USER` is the
  only fallback.
- The Tier 3 fallback is explicitly not equivalent to the Windows signal. It is included only to
  avoid returning `$null`.

### Sources

- [Environment.UserName Property (.NET 10)](https://learn.microsoft.com/en-us/dotnet/api/system.environment.username?view=net-10.0)
- [dotnet/runtime Environment.Unix.cs: calls GetEUid then GetUserNameFromPasswd](https://github.com/dotnet/runtime/blob/main/src/libraries/System.Private.CoreLib/src/System/Environment.Unix.cs)
- [dotnet/runtime pal_uid.c: SystemNative_GetPwUidR wraps getpwuid_r](https://github.com/dotnet/runtime/blob/main/src/native/libs/System.Native/pal_uid.c)
- [loginctl(1) man page: list-sessions, show-session -p Type](https://man7.org/linux/man-pages/man1/loginctl.1.html)
- [who(1) man page: show who is logged on, reads /var/run/utmp](https://man7.org/linux/man-pages/man1/who.1.html)
- [w(1) man page: who is logged on and what they are doing](https://man7.org/linux/man-pages/man1/w.1.html)
- [getpwuid_r(3) man page: get password file entry by UID](https://man7.org/linux/man-pages/man3/getpwuid_r.3.html)
- [Unix StackExchange: loginctl show-session -p Type for detecting x11/wayland](https://unix.stackexchange.com/questions/202891/how-to-know-whether-wayland-or-x11-is-being-used)
- [dotnet/standard issue #779: Environment.UserName on Linux](https://github.com/dotnet/standard/issues/779)
- [SS64: Find the LoggedOn user in PowerShell (Windows explorer.exe pattern)](https://ss64.com/ps/syntax-loggedon.html)

---

## 6. Logon / Session Type

**What the donor does:** Determines how the user authenticated (Kerberos, NTLM, local console) for
audit and diagnostic context.

**Windows API:** `[System.Security.Principal.WindowsIdentity]::GetCurrent().AuthenticationType`,
backed by the kernel's Security Support Provider.

**Verdict:** needs-correction

The verifier found a dead variable (`$sshTty` assigned but never read) and a missing
`$LASTEXITCODE` check after `loginctl` calls. The corrected idiom removes dead code and adds the
exit-code guard.

### Verified Linux/PS7 Idiom

```powershell
function Get-SessionType {
    $sshConn   = [System.Environment]::GetEnvironmentVariable('SSH_CONNECTION')
    $sshClient = [System.Environment]::GetEnvironmentVariable('SSH_CLIENT')

    if ($sshConn) {
        return "ssh ($sshConn)"
    }

    $xdgType  = [System.Environment]::GetEnvironmentVariable('XDG_SESSION_TYPE')
    $xdgClass = [System.Environment]::GetEnvironmentVariable('XDG_SESSION_CLASS')

    if ($xdgType) {
        $result = $xdgType
        if ($xdgClass) { $result += " ($xdgClass)" }
        return $result
    }

    $sessionId = [System.Environment]::GetEnvironmentVariable('XDG_SESSION_ID')
    if ($sessionId) {
        try {
            $type       = loginctl show-session $sessionId -p Type      --value 2>$null
            $class      = loginctl show-session $sessionId -p Class     --value 2>$null
            $remote     = loginctl show-session $sessionId -p Remote    --value 2>$null
            $remoteHost = loginctl show-session $sessionId -p RemoteHost --value 2>$null
            $service    = loginctl show-session $sessionId -p Service   --value 2>$null

            # loginctl exits non-zero when the session is not found; check before trusting output
            if ($LASTEXITCODE -eq 0) {
                $parts = @()
                if ($type)                                       { $parts += "type=$type" }
                if ($class)                                      { $parts += "class=$class" }
                if ($remote -eq 'yes' -and $remoteHost)         { $parts += "remote=$remoteHost" }
                if ($service)                                    { $parts += "service=$service" }
                if ($parts.Count -gt 0) { return ($parts -join '; ') }
            }
        }
        catch {
            # loginctl binary not found on PATH; fall through
        }
    }

    $hasTty = -not [System.Console]::IsInputRedirected
    if ($hasTty) {
        return 'local-interactive'
    }

    return 'non-interactive-or-unknown'
}
```

### Caveats

- **No single equivalent exists.** Windows has one authoritative API backed by the kernel's SSP.
  Linux has no single equivalent; session provenance is scattered across multiple independent sources
  that must be composed.
- `SSH_CONNECTION` does not survive `su -` or `sudo -i`. Those commands typically strip SSH
  environment variables from the new shell.
- `XDG_SESSION_TYPE` and `XDG_SESSION_CLASS` require systemd-logind. They are set by `pam_systemd(8)`
  during PAM session registration. Absent on non-systemd distros, containers without login sessions,
  cron jobs that do not go through PAM, and direct process spawning without PAM.
- `loginctl` requires systemd as init, the `loginctl` binary on PATH, and the current process
  belonging to a registered logind session.
- `[System.Console]::IsInputRedirected` calls `isatty(0)` on Unix. It cannot distinguish local
  console from SSH (both have a TTY allocated). Useful only as a last-resort heuristic.
- `[Environment]::UserInteractive` is **useless on Linux**: hardcoded to return `true` in
  `Environment.UnixOrBrowser.cs` (dotnet/runtime issue #66530).
- **No authentication method detection.** The closest Linux equivalent is `SSH_USER_AUTH` (requires
  `ExposeAuthInfo` in `sshd_config`), which is sshd-only and not available for local console logins.
- **Containers:** In Docker/Podman containers, none of these signals may be present. The function
  returns `non-interactive-or-unknown`, which is the correct honest answer.

### Sources

- [WindowsIdentity.AuthenticationType Property (.NET API Reference)](https://learn.microsoft.com/en-us/dotnet/api/system.security.principal.windowsidentity.authenticationtype?view=net-9.0)
- [System.Security.Principal.Windows.csproj: confirms PlatformNotSupportedException on non-Windows](https://raw.githubusercontent.com/dotnet/runtime/main/src/libraries/System.Security.Principal.Windows/src/System.Security.Principal.Windows.csproj)
- [pam_systemd(8) man page: documents XDG_SESSION_TYPE, XDG_SESSION_CLASS](https://man7.org/linux/man-pages/man8/pam_systemd.8.html)
- [sd_session_get_type(3) man page: systemd C API for session properties](https://man7.org/linux/man-pages/man3/sd_session_get_type.3.html)
- [loginctl(1) man page: show-session command](https://man7.org/linux/man-pages/man1/loginctl.1.html)
- [OpenSSH environment variables (SSH_CONNECTION, SSH_CLIENT, SSH_TTY)](https://serverfault.com/questions/278041/what-environment-variables-are-available-during-an-ssh-session)
- [Unix StackExchange: What are SSH_TTY and SSH_CONNECTION](https://unix.stackexchange.com/questions/120080/what-are-ssh-tty-and-ssh-connection)
- [Unix StackExchange: How to detect if shell is controlled from SSH](https://unix.stackexchange.com/questions/9605/how-can-i-detect-if-the-shell-is-controlled-from-ssh)
- [Environment.GetEnvironmentVariable (.NET API, cross-platform)](https://learn.microsoft.com/en-us/dotnet/api/system.environment.getenvironmentvariable?view=net-9.0)
- [dotnet/runtime issue #66530: UserInteractive always true on Unix](https://github.com/dotnet/runtime/issues/66530)
- [Environment.UserInteractive Property (.NET)](https://learn.microsoft.com/en-us/dotnet/api/system.environment.userinteractive?view=net-9.0)

---

## 7. Service / Non-Interactive (SYSTEM-Equivalent) Context

**What the donor does:** Detects whether the script is running as a background service with no
interactive user, equivalent to the Windows SYSTEM account or a Windows service context.

**Windows API:** `[System.Environment]::UserInteractive` (checks the window station for
`WSF_VISIBLE` flag via `GetProcessWindowStation`).

**Verdict:** confirmed

### Verified Linux/PS7 Idiom

```powershell
function Test-NonInteractiveService {
    if ($IsWindows) {
        # Windows: the .NET API works correctly here
        return -not [System.Environment]::UserInteractive
    }

    # Linux / macOS: multi-signal detection
    #
    # [System.Environment]::UserInteractive is USELESS on Linux.
    # The .NET runtime hardcodes it to true on all Unix platforms
    # (Environment.UnixOrBrowser.cs: "public static bool UserInteractive => true;").

    # Signal 1 (strongest): No controlling TTY on stdin.
    # Console.IsInputRedirected calls isatty(3) on fd 0 via the .NET PAL.
    $noTty = [System.Console]::IsInputRedirected -and
             [System.Console]::IsOutputRedirected -and
             [System.Console]::IsErrorRedirected

    # Signal 2: systemd INVOCATION_ID (present since systemd v232).
    # Set for all processes spawned as part of a service unit.
    $hasInvocationId = -not [string]::IsNullOrEmpty(
        [System.Environment]::GetEnvironmentVariable('INVOCATION_ID')
    )

    # Signal 3: systemd JOURNAL_STREAM (present since systemd v231).
    # Set when stdout/stderr are connected to the systemd journal.
    $hasJournalStream = -not [string]::IsNullOrEmpty(
        [System.Environment]::GetEnvironmentVariable('JOURNAL_STREAM')
    )

    # Non-interactive/service if no TTY OR systemd explicitly marked it as a service unit.
    return $noTty -or ($hasInvocationId -and $hasJournalStream)
}
```

### Caveats

- **`[Environment]::UserInteractive` is hardcoded `true` on all Unix platforms.** The .NET runtime
  source (`Environment.UnixOrBrowser.cs`) returns `true` unconditionally. It never returns `false`
  on Linux regardless of execution context.
- A script piped through stdin (`echo "Get-Date" | pwsh`) also shows `IsInputRedirected=$true`.
  Checking all three streams (stdin + stdout + stderr) reduces false positives since a pipe
  typically redirects only one or two.
- SSH sessions DO have a TTY allocated, so remote interactive sessions correctly appear interactive.
- `INVOCATION_ID` inherits to all child processes of the service, not just the direct `ExecStart`
  process. On some desktop distros, the user session itself is managed by `systemd --user`, so
  `INVOCATION_ID` may be present in interactive terminal emulators.
- `JOURNAL_STREAM` is only set when stdout/stderr are connected to the journal
  (`Type=simple` with default `StandardOutput`). A service with `StandardOutput=file:/path` may not
  have `JOURNAL_STREAM` set.
- **Non-systemd Linux (OpenRC, runit, s6):** neither `INVOCATION_ID` nor `JOURNAL_STREAM` will be
  set. The TTY check (`$noTty`) remains the only signal and is sufficient for most cases since
  daemons on any init system typically lack a controlling terminal.
- No elevated permissions required for any of these checks.

### Sources

- [dotnet/runtime Environment.UnixOrBrowser.cs: UserInteractive hardcoded to true](https://raw.githubusercontent.com/dotnet/runtime/main/src/libraries/System.Private.CoreLib/src/System/Environment.UnixOrBrowser.cs)
- [dotnet/runtime Environment.Windows.cs: UserInteractive uses GetProcessWindowStation + WSF_VISIBLE](https://raw.githubusercontent.com/dotnet/runtime/main/src/libraries/System.Private.CoreLib/src/System/Environment.Windows.cs)
- [dotnet/runtime ConsolePal.Unix.cs: IsInputRedirectedCore calls Interop.Sys.IsATty(fd)](https://source.dot.net/System.Console/System/ConsolePal.Unix.cs.html)
- [dotnet/runtime pal_console.c: SystemNative_IsATty wraps POSIX isatty(3)](https://raw.githubusercontent.com/dotnet/runtime/main/src/native/libs/System.Native/pal_console.c)
- [Environment.UserInteractive Property (.NET 8)](https://learn.microsoft.com/en-us/dotnet/api/system.environment.userinteractive?view=net-8.0)
- [isatty(3) man page: POSIX test whether fd refers to a terminal](https://man7.org/linux/man-pages/man3/isatty.3.html)
- [Stack Overflow: How can a program detect if running as a systemd daemon (INVOCATION_ID since v232)](https://stackoverflow.com/questions/39368185/how-can-a-program-detect-if-it-is-running-as-a-systemd-daemon)
- [Unix StackExchange: JOURNAL_STREAM (v231) and INVOCATION_ID (v232) for systemd service detection](https://unix.stackexchange.com/questions/622902/how-can-i-determine-within-a-shell-script-whether-it-is-being-called-by-system)
- [systemd.exec(5) man page: env vars set for services](https://www.man7.org/linux/man-pages/man5/systemd.exec.5.html)
- [PowerShell -NonInteractive parameter](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_powershell_exe?view=powershell-7.4)

---

## Summary Table

| Mechanism                         | Linux Equivalent Exists | Final Idiom (one-liner)                                                                                                           | Verdict          |
| --------------------------------- | ----------------------- | --------------------------------------------------------------------------------------------------------------------------------- | ---------------- |
| Process identity / username       | Full                    | `if ($IsWindows) { [WindowsIdentity]::GetCurrent().Name } else { "$([Environment]::UserDomainName)\$([Environment]::UserName)" }` | needs-correction |
| Admin / elevation status          | Full                    | `[System.Environment]::IsPrivilegedProcess`                                                                                       | confirmed        |
| Machine / host name               | Full                    | `[System.Environment]::MachineName`                                                                                               | confirmed        |
| Domain-qualified user identity    | Partial                 | `[System.Environment]::UserDomainName`                                                                                            | confirmed        |
| Interactive console/desktop user  | Partial                 | Tiered: loginctl > who > $env:USER                                                                                                | needs-correction |
| Logon / session type              | Partial                 | Layered: SSH_CONNECTION > XDG_SESSION_TYPE > loginctl > isatty                                                                    | needs-correction |
| Service / non-interactive context | Partial                 | `$noTty -or ($hasInvocationId -and $hasJournalStream)`                                                                            | confirmed        |

**Verdict key:** "confirmed" means the verifier validated the idiom with no changes needed.
"needs-correction" means the verifier found defects (dead variables, missing guards, trailing
whitespace) and the idiom shown in this document is the corrected version.

---

## Known Platform Gaps

### Linux has no AD domain semantics

`[Environment]::UserDomainName` on Linux returns the short hostname, not an Active Directory domain.
The .NET source (`Environment.UnixOrBrowser.cs`) aliases `UserDomainName` to `MachineName`. Even on
machines joined to AD via SSSD/realmd, the .NET API does not detect the AD domain. The resulting
`hostname\username` string is structurally valid CMTrace context but carries no domain authority.
Any downstream tooling that parses the `context=` field for domain-qualified identity will see a
format mismatch on Linux.

### SCCM/CMSite is Windows-only by design

SCCM (Configuration Manager) client APIs, WMI namespaces (`root\ccm`), and the CMSite concept are
Windows-only. There is no Linux SCCM client. This is out of scope for the Linux port. The rebuild
omits SCCM-specific functionality and documents its absence.

### Elevation API version gate (.NET 8 / PS 7.4+) with id -u fallback

`[System.Environment]::IsPrivilegedProcess` requires .NET 8.0+, which maps to PowerShell 7.4 or
later. PowerShell 7.2 (.NET 6) and 7.3 (.NET 7) do not have this API. Calling it on those versions
throws a missing-member error. The standard fallback is:

```powershell
try { $isAdmin = [System.Environment]::IsPrivilegedProcess }
catch { $isAdmin = (id -u) -eq 0 }
```

The `(id -u) -eq 0` fallback works because pwsh coerces the string output of `id -u` to int when
the right operand of `-eq` is an integer. The `id` command is POSIX-standard and present on all
standard Linux distributions.

### [Environment]::UserInteractive is broken on Linux

The .NET runtime hardcodes `UserInteractive` to `true` on all Unix platforms. It never returns
`false` on Linux regardless of whether the process is a daemon, a cron job, or a systemd service.
This is documented in dotnet/runtime issue #66530. The rebuild uses the multi-signal approach from
Section 7 (TTY check + systemd env vars) instead.

---

## Critical Donor Finding

> **`[WindowsIdentity]::GetCurrent().Name` at donor lines 258, 351, and 399 throws
> `System.PlatformNotSupportedException` on Linux.**

The donor script (`donor-code/Write-Log.ps1`) calls
`[System.Security.Principal.WindowsIdentity]::GetCurrent().Name` unconditionally in three places
to populate the CMTrace `context=` field. There is no `$IsWindows` guard.

Running the donor as-is on a Linux CI runner throws `PlatformNotSupportedException` on every single
log write. Every CMTrace log line the fleet emits passes through one of these three code paths.

This is why the rebuild uses a platform adapter rather than the donor as-is. The adapter calls
`[WindowsIdentity]::GetCurrent().Name` on Windows (preserving full AD domain and impersonation
token behavior) and falls back to
`"$([Environment]::UserDomainName)\$([Environment]::UserName)"` on Linux (producing a
structurally equivalent `hostname\username` string with no domain authority).

The three specific locations in the donor:

- **Line 258:** Primary log line construction (the main `$logline` variable).
- **Line 351:** Log rotation event (first entry written to a new rotated log file).
- **Line 399:** File contention retry note (logged when a write required retries due to file locks).
