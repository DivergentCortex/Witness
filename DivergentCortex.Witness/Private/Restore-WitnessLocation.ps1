function Restore-WitnessLocation {
    <#
    .SYNOPSIS
        Restores the working location Write-Log left for a CMSite drive.

    .DESCRIPTION
        A failed restore reports through Write-WitnessFailureLine and returns a structured result.
        This function never throws.

    .PARAMETER Location
        The location captured before Write-Log moved to C:.

    .OUTPUTS
        System.Management.Automation.PSCustomObject with Ok and Reason.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory = $true)]
        $Location
    )

    try {
        Set-Location $Location -ErrorAction Stop
        return [pscustomobject]@{ Ok = $true; Reason = $null }
    }
    catch {
        Write-WitnessFailureLine -Message "Write-Log: could not restore CMSite location '$Location': $($_.Exception.GetType().Name) at line $($MyInvocation.ScriptLineNumber): $($_.Exception.Message)"
        return [pscustomobject]@{ Ok = $false; Reason = 'LocationRestoreFailed' }
    }
}
