function Get-PlatformContext {
    <#
    .SYNOPSIS
        Returns a cross-platform identity and execution context object.

    .DESCRIPTION
        Detects the current platform (Windows/Linux/macOS), process identity,
        elevation status, interactive user, session type, and hostname. Called once
        per session from Initialize-Log; the result is used only for the start banner.
        Write-Log resolves context= cheaply per line on its own.

        Windows: uses WindowsIdentity for SAM-format identity and admin detection.
        Linux/macOS: uses .NET Environment APIs with id(1) and loginctl fallbacks.

    .OUTPUTS
        PSCustomObject with properties: Platform, IdentityName, LogonType,
        IsSystem, IsAdmin, UserDomainName, UserName, InteractiveUser,
        SessionType, HostName, ProcessId.

    .EXAMPLE
        $ctx = Get-PlatformContext
        Write-Host "Running on $($ctx.Platform) as $($ctx.IdentityName)"

    .NOTES
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
        -  Created on:    9/04/2025 3:50 PM                               -
        =  Author:        Curtis Leggett                                  =
        -  Copyright:     2025 Synapse Co.                                -
        =  Organization:  Divergent Cortex                                -
        -  Version:       2026.06.12.002                                  -
        =-=-                       =-=-=-=-=-=-=-=                     -=-=
        -       The witness is a ghost,                                   -
        =                      yet, somewhere,                            =
        -                             a file is remembering you.          -
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    # $IsMacOS does not exist on PS 5.1; guard with Test-Path.
    $platformStr = 'Linux'
    if ($script:WitnessIsWindows) {
        $platformStr = 'Windows'
    }
    elseif ((Test-Path Variable:IsMacOS) -and $IsMacOS) {
        $platformStr = 'macOS'
    }

    # Windows: WindowsIdentity keeps AD domain and impersonation token intact.
    # Non-Windows: UserDomainName returns the hostname -- documented gap, not a bug.
    if ($script:WitnessIsWindows) {
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $identityName = $identity.Name  # SAM format: DOMAIN\user
        $logonType = if ($identity.AuthenticationType) { $identity.AuthenticationType } else { 'N/A' }
    }
    else {
        $identity = $null
        $identityName = "$([System.Environment]::UserDomainName)\$([System.Environment]::UserName)"
        $logonType = 'N/A'
    }

    # Platform branch first -- id -u must never run on Windows.
    # Reuse $identity from above to avoid a second GetCurrent() call.
    if ($script:WitnessIsWindows) {
        $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
        $isAdmin = $principal.IsInRole(
            [System.Security.Principal.WindowsBuiltInRole]::Administrator
        )
    }
    else {
        # IsPrivilegedProcess needs .NET 8+; fall back to id -u on older builds.
        try {
            $isAdmin = [System.Environment]::IsPrivilegedProcess
        }
        catch {
            try {
                $idOutput = id -u 2>$null
                $isAdmin = ([int]$idOutput) -eq 0
            }
            catch {
                # Both probes failed -- assume non-privileged rather than throwing.
                $isAdmin = $false
            }
        }
    }

    $isSystem = $false
    if ($script:WitnessIsWindows) {
        $isSystem = $identityName -eq 'NT AUTHORITY\SYSTEM'
    }

    # MachineName is cross-platform; no platform branch needed.
    $hostName = [System.Environment]::MachineName

    # Windows: explorer.exe owner is the interactive user (-IncludeUserName is Windows-only).
    # Non-Windows: tiered fallback -- loginctl then who then process owner.
    $interactiveUser = $null
    if ($script:WitnessIsWindows) {
        try {
            $explorer = Get-Process explorer -IncludeUserName -ErrorAction SilentlyContinue
            if ($explorer) {
                $interactiveUser = ($explorer | Select-Object -First 1).UserName
            }
        }
        catch {
            # explorer.exe probe failed (headless/service context). Fall through to username fallback.
            Write-Verbose "Get-PlatformContext: explorer.exe probe failed: $_"
        }
        if (-not $interactiveUser) {
            $interactiveUser = [System.Environment]::UserName
        }
    }
    else {
        # Tier 1: loginctl catches graphical sessions on systemd distros.
        try {
            $raw = loginctl list-sessions --no-legend 2>$null
            if ($LASTEXITCODE -eq 0 -and $raw) {
                foreach ($line in ($raw -split "`n")) {
                    $fields = $line.Trim() -split '\s+'
                    if ($fields.Count -ge 3) {
                        $sessionId = $fields[0]
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
        }
        catch {
            # loginctl unavailable (non-systemd distro). Fall through to tier 2.
            Write-Verbose "Get-PlatformContext: loginctl probe failed: $_"
        }

        # Tier 2: who is utmp-based and works on non-systemd distros.
        if (-not $interactiveUser) {
            try {
                $whoOutput = who 2>$null
                if ($LASTEXITCODE -eq 0 -and $whoOutput) {
                    $interactiveUser = ($whoOutput -split "`n" |
                            Where-Object { $_ -match '\S' } |
                            Select-Object -First 1) -split '\s+' |
                            Select-Object -First 1
                }
            }
            catch {
                # who unavailable. Fall through to tier 3.
                Write-Verbose "Get-PlatformContext: who probe failed: $_"
            }
        }

        # Tier 3: process owner only -- could be a service account rather than a human.
        if (-not $interactiveUser) {
            $interactiveUser = [System.Environment]::UserName
        }
    }

    # Non-Windows: SSH_CONNECTION > XDG_SESSION_TYPE > loginctl > isatty.
    # Each covers a gap the previous probe misses.
    $sessionType = $logonType
    if (-not $script:WitnessIsWindows) {
        $sshConn = [System.Environment]::GetEnvironmentVariable('SSH_CONNECTION')
        $xdgType = [System.Environment]::GetEnvironmentVariable('XDG_SESSION_TYPE')
        $xdgClass = [System.Environment]::GetEnvironmentVariable('XDG_SESSION_CLASS')

        if ($sshConn) {
            $sessionType = "ssh ($sshConn)"
        }
        elseif ($xdgType) {
            $sessionType = if ($xdgClass) { "$xdgType ($xdgClass)" } else { $xdgType }
        }
        else {
            $xdgSessionId = [System.Environment]::GetEnvironmentVariable('XDG_SESSION_ID')
            if ($xdgSessionId) {
                try {
                    $lType = (loginctl show-session $xdgSessionId -p Type --value 2>$null)
                    $lClass = (loginctl show-session $xdgSessionId -p Class --value 2>$null)
                    if ($LASTEXITCODE -eq 0 -and $lType) {
                        $parts = @()
                        if ($lType) { $parts += "type=$($lType.Trim())" }
                        if ($lClass) { $parts += "class=$($lClass.Trim())" }
                        $sessionType = $parts -join '; '
                    }
                }
                catch {
                    # loginctl session query failed; isatty fallback below handles it.
                    Write-Verbose "Get-PlatformContext: loginctl session query failed: $_"
                }
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
