# Private/Get-PlatformContext.ps1
# Cross-platform identity and execution context adapter.
# Runs ONCE per session via Initialize-Log; result cached in $script:WitnessContext.
# Used ONLY for the Initialize-Log banner. Write-Log resolves context= cheaply per line.
#
# Fix references:
#   [3]  Uses $script:WitnessIsWindows - never raw $IsWindows (undefined on PS 5.1).
#   [4]  Replaces Windows-only Get-ExecutionContextInfo.
#   [7]  macOS detection: Platform returns 'Windows'/'macOS'/'Linux'.
#        $IsMacOS guarded with Test-Path Variable:IsMacOS for 5.1-safety.
#   [8]  Elevation branches Windows/non-Windows first, [Environment]::IsPrivilegedProcess
#        with id -u fallback. id -u NEVER runs on Windows.
#   [9]  Interactive-user fallback uses [Environment]::UserName, not $env:USER.
#   [10] Reuses $identity from the identity block for elevation check on Windows.
#        No second [WindowsIdentity]::GetCurrent() call.

function Get-PlatformContext {
    [CmdletBinding()]
    param()

    # ---- Platform string (Fix [7]) ----
    # $IsMacOS does not exist on PS 5.1; guard with Test-Path.
    $platformStr = 'Linux'
    if ($script:WitnessIsWindows) {
        $platformStr = 'Windows'
    } elseif ((Test-Path Variable:IsMacOS) -and $IsMacOS) {
        $platformStr = 'macOS'
    }

    # ---- Process identity / username ----
    # Windows: WindowsIdentity preserves AD domain + impersonation token.
    # Non-Windows: [Environment]::UserDomainName returns hostname (documented gap, not a bug).
    if ($script:WitnessIsWindows) {
        $identity     = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $identityName = $identity.Name  # SAM format: DOMAIN\user
        $logonType    = if ($identity.AuthenticationType) { $identity.AuthenticationType } else { 'N/A' }
    } else {
        $identity     = $null
        $identityName = "$([System.Environment]::UserDomainName)\$([System.Environment]::UserName)"
        $logonType    = 'N/A'
    }

    # ---- Elevation (Fix [8], Fix [10]) ----
    # Branch on platform FIRST. id -u never runs on Windows.
    # Fix [10]: reuse $identity already obtained above - no second GetCurrent() call.
    if ($script:WitnessIsWindows) {
        $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
        $isAdmin   = $principal.IsInRole(
            [System.Security.Principal.WindowsBuiltInRole]::Administrator
        )
    } else {
        # IsPrivilegedProcess requires .NET 8+ (PS 7.4+). Fall back to id -u on older builds.
        try {
            $isAdmin = [System.Environment]::IsPrivilegedProcess
        } catch {
            try {
                $idOutput = id -u 2>$null
                $isAdmin  = ([int]$idOutput) -eq 0
            } catch {
                $isAdmin = $false
            }
        }
    }

    # ---- SYSTEM-equivalent check (Windows only) ----
    $isSystem = $false
    if ($script:WitnessIsWindows) {
        $isSystem = $identityName -eq 'NT AUTHORITY\SYSTEM'
    }

    # ---- Hostname ----
    # [Environment]::MachineName is fully cross-platform per verified research.
    $hostName = [System.Environment]::MachineName

    # ---- Interactive user (Fix [9]) ----
    # Windows: find owner of explorer.exe (donor pattern; -IncludeUserName is Windows-only).
    # Non-Windows: tiered approach per CROSS-PLATFORM.md Section 5.
    $interactiveUser = $null
    if ($script:WitnessIsWindows) {
        try {
            $explorer = Get-Process explorer -IncludeUserName -ErrorAction SilentlyContinue
            if ($explorer) {
                $interactiveUser = ($explorer | Select-Object -First 1).UserName
            }
        } catch {}
        if (-not $interactiveUser) {
            $interactiveUser = [System.Environment]::UserName
        }
    } else {
        # Tier 1: loginctl (systemd) - graphical session detection
        try {
            $raw = loginctl list-sessions --no-legend 2>$null
            if ($LASTEXITCODE -eq 0 -and $raw) {
                foreach ($line in ($raw -split "`n")) {
                    $fields = $line.Trim() -split '\s+'
                    if ($fields.Count -ge 3) {
                        $sessionId   = $fields[0]
                        $sessionUser = $fields[2]
                        $sessionType = (loginctl show-session $sessionId -p Type --value 2>$null)
                        if ($null -ne $sessionType) { $sessionType = $sessionType.Trim() }
                        if ($sessionType -in 'x11', 'wayland') {
                            $interactiveUser = $sessionUser
                            break
                        }
                    }
                }
            }
        } catch {}

        # Tier 2: who(1), utmp-based, works on non-systemd distros
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

        # Tier 3: [Environment]::UserName - process owner, last resort (Fix [9])
        if (-not $interactiveUser) {
            $interactiveUser = [System.Environment]::UserName
        }
    }

    # ---- Session type (logon type equivalent) ----
    # Windows: AuthenticationType from identity token (captured above).
    # Non-Windows: layered SSH_CONNECTION > XDG_SESSION_TYPE > loginctl > isatty heuristic.
    $sessionType = $logonType
    if (-not $script:WitnessIsWindows) {
        $sshConn  = [System.Environment]::GetEnvironmentVariable('SSH_CONNECTION')
        $xdgType  = [System.Environment]::GetEnvironmentVariable('XDG_SESSION_TYPE')
        $xdgClass = [System.Environment]::GetEnvironmentVariable('XDG_SESSION_CLASS')

        if ($sshConn) {
            $sessionType = "ssh ($sshConn)"
        } elseif ($xdgType) {
            $sessionType = if ($xdgClass) { "$xdgType ($xdgClass)" } else { $xdgType }
        } else {
            $xdgSessionId = [System.Environment]::GetEnvironmentVariable('XDG_SESSION_ID')
            if ($xdgSessionId) {
                try {
                    $lType  = (loginctl show-session $xdgSessionId -p Type  --value 2>$null)
                    $lClass = (loginctl show-session $xdgSessionId -p Class --value 2>$null)
                    if ($LASTEXITCODE -eq 0 -and $lType) {
                        $parts = @()
                        if ($lType)  { $parts += "type=$($lType.Trim())" }
                        if ($lClass) { $parts += "class=$($lClass.Trim())" }
                        $sessionType = $parts -join '; '
                    }
                } catch {}
            }
            if ($sessionType -eq 'N/A') {
                $hasTty = -not [System.Console]::IsInputRedirected
                $sessionType = if ($hasTty) { 'local-interactive' } else { 'non-interactive-or-unknown' }
            }
        }
    }

    [pscustomobject]@{
        Platform        = $platformStr
        IdentityName    = $identityName
        LogonType       = $logonType
        IsSystem        = $isSystem
        IsAdmin         = $isAdmin
        UserDomainName  = [System.Environment]::UserDomainName
        UserName        = [System.Environment]::UserName
        InteractiveUser = $interactiveUser
        SessionType     = $sessionType
        HostName        = $hostName
        ProcessId       = $PID
    }
}
