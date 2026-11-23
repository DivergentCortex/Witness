function Write-WitnessBannerFile {
    <#
    .SYNOPSIS
        Appends the session-start banner lines to the log file as CMTrace entries.

    .DESCRIPTION
        Writes directly to the file, bypassing the Verbose and Debug gate, so the session context
        is always present. A failed write reports through Write-WitnessFailureLine and returns a
        structured result. This function never throws.

    .PARAMETER LogPath
        The log file to append to.

    .PARAMETER Lines
        The banner text lines.

    .PARAMETER LogTime
        The HH:mm:ss.fff time written to each entry.

    .PARAMETER LogDate
        The MM-dd-yyyy date written to each entry.

    .PARAMETER ContextUser
        The identity written to each entry.

    .OUTPUTS
        System.Management.Automation.PSCustomObject with Written and Reason.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$LogPath,

        [Parameter(Mandatory = $true)]
        [string[]]$Lines,

        [Parameter(Mandatory = $true)]
        [string]$LogTime,

        [Parameter(Mandatory = $true)]
        [string]$LogDate,

        [Parameter(Mandatory = $true)]
        [string]$ContextUser
    )

    $fileStream = $null
    $streamWriter = $null
    try {
        $fileMode = [System.IO.FileMode]::Append
        $fileAccess = [System.IO.FileAccess]::Write
        $fileShare = [System.IO.FileShare]::ReadWrite
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

        $fileStream = New-Object System.IO.FileStream($LogPath, $fileMode, $fileAccess, $fileShare)
        $streamWriter = New-Object System.IO.StreamWriter($fileStream, $utf8NoBom)
        $streamWriter.NewLine = [System.Environment]::NewLine

        foreach ($line in $Lines) {
            $entry = "<![LOG[$line]LOG]!>" +
                "<time=`"$LogTime`" " +
                "date=`"$LogDate`" " +
                "component=`"Initialize-Log`" " +
                "context=`"$ContextUser`" " +
                "type=`"1`" " +
                "thread=`"$PID`" " +
                "file=`"Initialize-Log.ps1`">"
            $streamWriter.WriteLine($entry)
        }
        return [pscustomobject]@{ Written = $true; Reason = $null }
    }
    catch {
        Write-WitnessFailureLine -ContextUser $ContextUser -Message "Initialize-Log: failed to write banner to '$LogPath': $($_.Exception.GetType().Name) at line $($MyInvocation.ScriptLineNumber): $($_.Exception.Message)"
        return [pscustomobject]@{ Written = $false; Reason = 'BannerWriteFailed' }
    }
    finally {
        if ($null -ne $streamWriter) { $streamWriter.Dispose() }
        if ($null -ne $fileStream) { $fileStream.Dispose() }
    }
}
