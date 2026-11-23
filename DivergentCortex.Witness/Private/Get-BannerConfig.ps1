function Get-BannerConfig {
    <#
    .SYNOPSIS
        Loads the banner configuration PSD1, with fallback to the shipped default.

    .DESCRIPTION
        Resolution order (first non-empty path that resolves to a readable file wins):
          1. Explicit $ConfigPath parameter.
          2. $Global:WitnessBannerConfigPath.
          3. The module-shipped default: <ModuleRoot>/config/banner.psd1.

        Returns a hashtable with keys: Enabled, Separator, HeaderLines, Fields, FooterLines.
        If the resolved file cannot be imported, the failure is reported through
        Write-WitnessFailureLine and the shipped default is returned so the caller always
        gets a usable config. If the shipped default cannot be imported either, a disabled
        banner config is returned. This function never throws.

    .PARAMETER ConfigPath
        Optional explicit path to a banner.psd1 config file.

    .OUTPUTS
        [hashtable] -- the loaded banner configuration.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory = $false)]
        [string]$ConfigPath
    )

    $defaultPath = Join-Path $PSScriptRoot '..' 'config' 'banner.psd1'
    $defaultPath = [System.IO.Path]::GetFullPath($defaultPath)

    $resolvedPath = $null

    if (-not [string]::IsNullOrWhiteSpace($ConfigPath) -and (Test-Path $ConfigPath -PathType Leaf)) {
        $resolvedPath = $ConfigPath
    }
    elseif (-not [string]::IsNullOrWhiteSpace($Global:WitnessBannerConfigPath) -and
            (Test-Path $Global:WitnessBannerConfigPath -PathType Leaf)) {
        $resolvedPath = $Global:WitnessBannerConfigPath
    }
    else {
        $resolvedPath = $defaultPath
    }

    try {
        return Import-PowerShellDataFile -Path $resolvedPath -ErrorAction Stop
    }
    catch {
        Write-WitnessFailureLine -LogPath $script:WitnessLogFilePath -Message "Get-BannerConfig: could not load banner config from '$resolvedPath': $($_.Exception.GetType().Name) at line $($MyInvocation.ScriptLineNumber): $($_.Exception.Message). Falling back to the shipped default."
    }

    try {
        return Import-PowerShellDataFile -Path $defaultPath -ErrorAction Stop
    }
    catch {
        Write-WitnessFailureLine -LogPath $script:WitnessLogFilePath -Message "Get-BannerConfig: could not load the shipped default config '$defaultPath': $($_.Exception.GetType().Name) at line $($MyInvocation.ScriptLineNumber): $($_.Exception.Message). The banner will be suppressed."
    }

    return @{
        Enabled     = $false
        Separator   = ''
        HeaderLines = @()
        Fields      = @()
        FooterLines = @()
    }
}
