function Get-PlatformContext {
    <#
    .SYNOPSIS
        Returns a cross-platform identity and execution context object.

    .DESCRIPTION
        Detects the current platform (Windows/Linux/macOS), process identity,
        elevation status, interactive user, session type, and hostname. Runs once
        per session via Initialize-Log; the result is used only for the start
        banner. Write-Log resolves context= cheaply per line on its own.

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
        =  Organization:  Divergent Cortex                                =
        -  Version:       2026.06.12.002                                  -
        =-=-                       =-=-=-=-=-=-=-=                     -=-=
        -       The witness is a ghost,                                   -
        =                      yet, somewhere,                            =
        -                             a file is remembering you.          -
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
    #>
    [CmdletBinding()]
    param()

    # $IsMacOS does not exist on PS 5.1; guard with Test-Path
    $platformStr = 'Linux'
    if ($script:WitnessIsWindows) {
        $platformStr = 'Windows'
    }
    elseif ((Test-Path Variable:IsMacOS) -and $IsMacOS) {
        $platformStr = 'macOS'
    }

    # windows: WindowsIdentity keeps AD domain + impersonation token intact
    # non-windows: UserDomainName returns the hostname -- documented gap not a bug
    if ($script:WitnessIsWindows) {
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $identityName = $identity.Name  # SAM format DOMAIN\user
        $logonType = if ($identity.AuthenticationType) {
            $identity.AuthenticationType 
        }
        else {
            'N/A' 
        }
    }
    else {
        $identity = $null
        $identityName = "$([System.Environment]::UserDomainName)\$([System.Environment]::UserName)"
        $logonType = 'N/A'
    }

    # platform branch first -- id -u must never run on windows
    # reuse $identity from above to avoid a second GetCurrent() call
    if ($script:WitnessIsWindows) {
        $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
        $isAdmin = $principal.IsInRole(
            [System.Security.Principal.WindowsBuiltInRole]::Administrator
        )
    }
    else {
        # IsPrivilegedProcess needs .NET 8+ so fall back to id -u on older builds
        try {
            $isAdmin = [System.Environment]::IsPrivilegedProcess
        }
        catch {
            try {
                $idOutput = id -u 2>$null
                $isAdmin = ([int]$idOutput) -eq 0
            }
            catch {
                $isAdmin = $false
            }
        }
    }

    $isSystem = $false
    if ($script:WitnessIsWindows) {
        $isSystem = $identityName -eq 'NT AUTHORITY\SYSTEM'
    }

    # MachineName is cross-platform -- no platform branch needed here
    $hostName = [System.Environment]::MachineName

    # windows: explorer.exe owner is the interactive user (-IncludeUserName is windows-only)
    # non-windows: tiered fallback -- loginctl then who then process owner
    $interactiveUser = $null
    if ($script:WitnessIsWindows) {
        try {
            $explorer = Get-Process explorer -IncludeUserName -ErrorAction SilentlyContinue
            if ($explorer) {
                $interactiveUser = ($explorer | Select-Object -First 1).UserName
            }
        }
        catch {
        }
        if (-not $interactiveUser) {
            $interactiveUser = [System.Environment]::UserName
        }
    }
    else {
        # tier 1: loginctl catches graphical sessions on systemd distros
        try {
            $raw = loginctl list-sessions --no-legend 2>$null
            if ($LASTEXITCODE -eq 0 -and $raw) {
                foreach ($line in ($raw -split "`n")) {
                    $fields = $line.Trim() -split '\s+'
                    if ($fields.Count -ge 3) {
                        $sessionId = $fields[0]
                        $sessionUser = $fields[2]
                        $sessionType = (loginctl show-session $sessionId -p Type --value 2>$null)
                        if ($null -ne $sessionType) {
                            $sessionType = $sessionType.Trim() 
                        }
                        if ($sessionType -in 'x11', 'wayland') {
                            $interactiveUser = $sessionUser
                            break
                        }
                    }
                }
            }
        }
        catch {
        }

        # tier 2: who is utmp-based and works on non-systemd distros
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
            }
        }

        # tier 3: process owner only -- could be a service account not a human
        if (-not $interactiveUser) {
            $interactiveUser = [System.Environment]::UserName
        }
    }

    # non-windows: SSH_CONNECTION > XDG_SESSION_TYPE > loginctl > isatty -- each covers a gap the previous misses
    $sessionType = $logonType
    if (-not $script:WitnessIsWindows) {
        $sshConn = [System.Environment]::GetEnvironmentVariable('SSH_CONNECTION')
        $xdgType = [System.Environment]::GetEnvironmentVariable('XDG_SESSION_TYPE')
        $xdgClass = [System.Environment]::GetEnvironmentVariable('XDG_SESSION_CLASS')

        if ($sshConn) {
            $sessionType = "ssh ($sshConn)"
        }
        elseif ($xdgType) {
            $sessionType = if ($xdgClass) {
                "$xdgType ($xdgClass)" 
            }
            else {
                $xdgType 
            }
        }
        else {
            $xdgSessionId = [System.Environment]::GetEnvironmentVariable('XDG_SESSION_ID')
            if ($xdgSessionId) {
                try {
                    $lType = (loginctl show-session $xdgSessionId -p Type --value 2>$null)
                    $lClass = (loginctl show-session $xdgSessionId -p Class --value 2>$null)
                    if ($LASTEXITCODE -eq 0 -and $lType) {
                        $parts = @()
                        if ($lType) {
                            $parts += "type=$($lType.Trim())" 
                        }
                        if ($lClass) {
                            $parts += "class=$($lClass.Trim())" 
                        }
                        $sessionType = $parts -join '; '
                    }
                }
                catch {
                }
            }
            if ($sessionType -eq 'N/A') {
                $hasTty = -not [System.Console]::IsInputRedirected
                $sessionType = if ($hasTty) {
                    'local-interactive' 
                }
                else {
                    'non-interactive-or-unknown' 
                }
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
