function Add-WitnessLogLine {
    <#
    .SYNOPSIS
        Appends one CMTrace line to the log file with lock retries.

    .DESCRIPTION
        Opens the file for append with a read-write share so concurrent readers are not blocked.
        A file lock (IOException) is retried up to MaxRetries times with RetryDelay seconds between
        attempts, and a write that needed retries adds a contention note line. Any other failure
        stops the attempt. Failures report through Write-WitnessFailureLine and a structured
        result is returned. This function never throws.

    .PARAMETER LogPath
        The log file to append to.

    .PARAMETER Line
        The complete CMTrace line.

    .PARAMETER MaxRetries
        Retry attempts after a lock.

    .PARAMETER RetryDelay
        Seconds to wait between attempts.

    .PARAMETER LogTime
        The HH:mm:ss.fff time written to a contention note.

    .PARAMETER LogDate
        The MM-dd-yyyy date written to a contention note.

    .PARAMETER ContextUser
        The identity written to the contention note and to failure lines.

    .OUTPUTS
        System.Management.Automation.PSCustomObject with Written, Retries and Reason.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$LogPath,

        [Parameter(Mandatory = $true)]
        [string]$Line,

        [Parameter(Mandatory = $true)]
        [int]$MaxRetries,

        [Parameter(Mandatory = $true)]
        [double]$RetryDelay,

        [Parameter(Mandatory = $true)]
        [string]$LogTime,

        [Parameter(Mandatory = $true)]
        [string]$LogDate,

        [Parameter(Mandatory = $true)]
        [string]$ContextUser
    )

    $retryCount = 0
    $writeSucceeded = $false
    $reason = $null

    while (-not $writeSucceeded -and $retryCount -le $MaxRetries) {
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
            $streamWriter.WriteLine($Line)
            $writeSucceeded = $true

            if ($retryCount -gt 0) {
                $retryNote = "<![LOG[WRITE-LOG FILE CONTENTION: Previous entry required $retryCount retry attempt(s) due to file lock on $LogPath]LOG]!>" +
                    "<time=`"$LogTime`" date=`"$LogDate`" component=`"Write-Log`" " +
                    "context=`"$ContextUser`" " +
                    "type=`"2`" thread=`"$PID`" file=`"Write-Log.ps1`">"
                $streamWriter.WriteLine($retryNote)
            }
        }
        catch [System.IO.IOException] {
            $retryCount++
            if ($retryCount -le $MaxRetries) {
                Start-Sleep -Milliseconds ([int]($RetryDelay * 1000))
            }
            else {
                $reason = 'FileLocked'
                Write-WitnessFailureLine -LogPath $LogPath -ContextUser $ContextUser -Message "Write-Log: failed to write to log after $MaxRetries retries (file locked): $LogPath"
            }
        }
        catch {
            $reason = 'WriteFailed'
            Write-WitnessFailureLine -LogPath $LogPath -ContextUser $ContextUser -Message "Write-Log: failed to write to log file '$LogPath': $($_.Exception.GetType().Name) at line $($MyInvocation.ScriptLineNumber): $($_.Exception.Message)"
            break
        }
        finally {
            if ($null -ne $streamWriter) { $streamWriter.Dispose() }
            if ($null -ne $fileStream) { $fileStream.Dispose() }
        }
    }

    return [pscustomobject]@{ Written = $writeSucceeded; Retries = $retryCount; Reason = $reason }
}
