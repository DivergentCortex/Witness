function Invoke-WitnessRotation {
    <#
    .SYNOPSIS
        Rotates the log file to the next _rNN archive name when it has reached the size limit.

    .DESCRIPTION
        Checks the file size, renames the file to the next free _rNN name and writes the rotation
        notice as the first line of the new file. Each of the three risky steps is its own
        sandwich in sequence, and a failed step reports through Write-WitnessFailureLine and
        returns a structured result. A failed rename leaves the original file untouched and
        writes no notice. This function never throws.

    .PARAMETER LogPath
        The active log file.

    .PARAMETER MaxSizeMB
        The rotation threshold in megabytes.

    .PARAMETER LogTime
        The HH:mm:ss.fff time written to the rotation notice.

    .PARAMETER LogDate
        The MM-dd-yyyy date written to the rotation notice.

    .PARAMETER ContextUser
        The identity written to the notice and to failure lines.

    .OUTPUTS
        System.Management.Automation.PSCustomObject with Rotated, NoticeWritten and Reason.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$LogPath,

        [Parameter(Mandatory = $true)]
        $MaxSizeMB,

        [Parameter(Mandatory = $true)]
        [string]$LogTime,

        [Parameter(Mandatory = $true)]
        [string]$LogDate,

        [Parameter(Mandatory = $true)]
        [string]$ContextUser
    )

    $currentSize = 0
    try {
        $currentSize = (Get-Item $LogPath -ErrorAction Stop).Length / 1MB
    }
    catch {
        Write-WitnessFailureLine -LogPath $LogPath -ContextUser $ContextUser -Message "Write-Log: size check failed on '$LogPath': $($_.Exception.GetType().Name) at line $($MyInvocation.ScriptLineNumber): $($_.Exception.Message)"
        return [pscustomobject]@{ Rotated = $false; NoticeWritten = $false; Reason = 'SizeCheckFailed' }
    }

    if ($currentSize -lt $MaxSizeMB) {
        return [pscustomobject]@{ Rotated = $false; NoticeWritten = $false; Reason = 'BelowThreshold' }
    }

    $rotLogDir = Split-Path $LogPath
    $logBase = [System.IO.Path]::GetFileNameWithoutExtension($LogPath)
    $logExt = [System.IO.Path]::GetExtension($LogPath)
    $rotNum = 1
    do {
        $archiveName = '{0}_r{1:D2}{2}' -f $logBase, $rotNum, $logExt
        $archivePath = Join-Path $rotLogDir $archiveName
        $rotNum++
    } while (Test-Path $archivePath)

    try {
        Rename-Item -Path $LogPath -NewName $archiveName -Force -ErrorAction Stop
    }
    catch {
        Write-WitnessFailureLine -LogPath $LogPath -ContextUser $ContextUser -Message "Write-Log: could not rotate log to '$archiveName': $($_.Exception.GetType().Name) at line $($MyInvocation.ScriptLineNumber): $($_.Exception.Message)"
        return [pscustomobject]@{ Rotated = $false; NoticeWritten = $false; Reason = 'RenameFailed' }
    }

    $rotationMsg = "<![LOG[LOG ROTATION: Previous log archived to $archiveName (exceeded ${MaxSizeMB}MB)]LOG]!>" +
        "<time=`"$LogTime`" date=`"$LogDate`" component=`"Write-Log`" " +
        "context=`"$ContextUser`" " +
        "type=`"1`" thread=`"$PID`" file=`"Write-Log.ps1`">"

    try {
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($LogPath, "$rotationMsg$([System.Environment]::NewLine)", $utf8NoBom)
    }
    catch {
        Write-WitnessFailureLine -LogPath $LogPath -ContextUser $ContextUser -Message "Write-Log: failed to write rotation notice to '$LogPath': $($_.Exception.GetType().Name) at line $($MyInvocation.ScriptLineNumber): $($_.Exception.Message)"
        return [pscustomobject]@{ Rotated = $true; NoticeWritten = $false; Reason = 'NoticeWriteFailed' }
    }

    return [pscustomobject]@{ Rotated = $true; NoticeWritten = $true; Reason = $null }
}
