function Get-WitnessContextUser {
    <#
    .SYNOPSIS
        Returns the identity written to the context field, resolved per write.

    .DESCRIPTION
        On Windows the current WindowsIdentity name, read each time so impersonation changes show
        in the next line. Elsewhere DOMAIN\user from the environment. A failed lookup reports
        through Write-WitnessFailureLine and returns 'unknown'. This function never throws.

    .OUTPUTS
        System.String.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param ()

    try {
        if ($script:WitnessIsWindows) {
            return [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        }
        return "$([System.Environment]::UserDomainName)\$([System.Environment]::UserName)"
    }
    catch {
        Write-WitnessFailureLine -Message "Write-Log: identity lookup failed: $($_.Exception.GetType().Name) at line $($MyInvocation.ScriptLineNumber): $($_.Exception.Message)"
        return 'unknown'
    }
}
