function Write-WitnessFailureLine {
    <#
    .SYNOPSIS
        Reports a logger-internal failure without calling Write-Log.

    .DESCRIPTION
        Write-Log cannot report its own failures through itself without recursing, so its
        failure path appends one CMTrace Warning line (type 2, component Write-Log) straight
        to the log file with a low-level append. When there is no usable log file, or the
        append itself fails, the same line goes to the process error stream, the only channel
        left. The text is redacted like every other message. This function never throws.

    .PARAMETER Message
        The failure text: the action, the target, the exception type, the line and the message.

    .PARAMETER LogPath
        The log file to append to. Empty when no log file could be resolved.

    .PARAMETER ContextUser
        The identity written to the context field.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [string]$LogPath,

        [Parameter(Mandatory = $false)]
        [string]$ContextUser = 'unknown'
    )

    $now = Get-Date
    $safeMessage = ConvertTo-WitnessRedactedText -Text $Message
    $line = "<![LOG[$safeMessage]LOG]!>" +
        "<time=`"$($now.ToString('HH:mm:ss.fff'))`" " +
        "date=`"$($now.ToString('MM-dd-yyyy'))`" " +
        "component=`"Write-Log`" " +
        "context=`"$ContextUser`" " +
        "type=`"2`" thread=`"$PID`" file=`"Write-Log.ps1`">"

    if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
        try {
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::AppendAllText($LogPath, "$line$([System.Environment]::NewLine)", $utf8NoBom)
            return
        }
        catch {
            # the log file is the failing part, fall through to the error stream
            $line = "$line [append to '$LogPath' failed: $($_.Exception.GetType().Name)]"
        }
    }

    try {
        [System.Console]::Error.WriteLine($line)
    }
    catch {
        # no channel is left to report this on
        return
    }
}
