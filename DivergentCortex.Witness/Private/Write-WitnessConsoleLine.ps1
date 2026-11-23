function Write-WitnessConsoleLine {
    <#
    .SYNOPSIS
        Writes the color-coded console line for one log entry.

    .DESCRIPTION
        Interactive presentation of the entry Write-Log also writes to the file. The severity
        label color is fixed per severity and the message color defaults per severity unless
        MessageColor is given. This function never throws.

    .PARAMETER Severity
        Info, Warning, Error, Verbose, Debug or Success.

    .PARAMETER Component
        The component label, shortened to 10 characters plus two dots past 12.

    .PARAMETER LineNumber
        The caller line number shown in the third bracket.

    .PARAMETER Message
        The already redacted message text.

    .PARAMETER MessageColor
        Optional ConsoleColor name overriding the default message color.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Severity,

        [Parameter(Mandatory = $true)]
        [string]$Component,

        [Parameter(Mandatory = $true)]
        [string]$LineNumber,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [string]$MessageColor
    )

    $displayComponent = $Component
    if ($displayComponent.Length -gt 12) {
        $displayComponent = $displayComponent.Substring(0, 10) + '..'
    }

    $severityConfig = @{
        'Error'   = @{ Label = ' ERROR ';   LabelColor = 'Red';      MessageColor = 'Red' }
        'Warning' = @{ Label = ' WARNING '; LabelColor = 'Yellow';   MessageColor = 'Yellow' }
        'Info'    = @{ Label = ' INFO ';    LabelColor = 'Green';    MessageColor = 'White' }
        'Success' = @{ Label = ' SUCCESS '; LabelColor = 'Green';    MessageColor = 'Green' }
        'Verbose' = @{ Label = ' VERBOSE '; LabelColor = 'DarkGray'; MessageColor = 'DarkGray' }
        'Debug'   = @{ Label = ' DEBUG ';   LabelColor = 'Magenta';  MessageColor = 'Magenta' }
    }

    $config = $severityConfig[$Severity]
    $finalMessageColor = $config.MessageColor
    if (-not [string]::IsNullOrEmpty($MessageColor)) { $finalMessageColor = $MessageColor }

    try {
        Write-Host '[' -NoNewline -ForegroundColor Gray
        Write-Host $config.Label -NoNewline -ForegroundColor $config.LabelColor
        Write-Host '] [' -NoNewline -ForegroundColor Gray
        Write-Host "$displayComponent" -NoNewline -ForegroundColor Blue
        Write-Host '] [' -NoNewline -ForegroundColor Gray
        Write-Host "$LineNumber" -NoNewline -ForegroundColor Cyan
        Write-Host ']' -NoNewline -ForegroundColor Gray
        Write-Host ': ' -NoNewline -ForegroundColor Magenta
        Write-Host "$Message" -ForegroundColor $finalMessageColor
    }
    catch {
        Write-WitnessFailureLine -Message "Write-Log: console write failed for component '$Component': $($_.Exception.GetType().Name) at line $($MyInvocation.ScriptLineNumber): $($_.Exception.Message)"
    }
}
