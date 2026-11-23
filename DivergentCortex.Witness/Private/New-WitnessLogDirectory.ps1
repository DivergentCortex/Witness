function New-WitnessLogDirectory {
    <#
    .SYNOPSIS
        Creates the parent folder of the log file when it does not exist.

    .DESCRIPTION
        The folder is checked after the create, because a create under a path that is not a
        folder can return without an error. A failed create reports through
        Write-WitnessFailureLine and returns a structured result. This function never throws.

    .PARAMETER LogPath
        The log file whose parent folder is ensured.

    .PARAMETER ContextUser
        The identity written to failure lines.

    .OUTPUTS
        System.Management.Automation.PSCustomObject with Ok and Reason.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$LogPath,

        [Parameter(Mandatory = $true)]
        [string]$ContextUser
    )

    $logDir = Split-Path $LogPath
    if (-not $logDir) { return [pscustomobject]@{ Ok = $true; Reason = $null } }
    if (Test-Path $logDir) { return [pscustomobject]@{ Ok = $true; Reason = $null } }

    try {
        New-Item -Path $logDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
        if (-not (Test-Path $logDir -PathType Container)) {
            Write-WitnessFailureLine -ContextUser $ContextUser -Message "Write-Log: could not create log folder '$logDir': the folder does not exist after the create"
            return [pscustomobject]@{ Ok = $false; Reason = 'LogFolderMissingAfterCreate' }
        }
        return [pscustomobject]@{ Ok = $true; Reason = $null }
    }
    catch {
        Write-WitnessFailureLine -ContextUser $ContextUser -Message "Write-Log: could not create log folder '$logDir': $($_.Exception.GetType().Name) at line $($MyInvocation.ScriptLineNumber): $($_.Exception.Message)"
        return [pscustomobject]@{ Ok = $false; Reason = 'LogFolderCreateFailed' }
    }
}
