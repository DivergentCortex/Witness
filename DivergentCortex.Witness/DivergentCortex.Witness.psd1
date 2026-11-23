#
# Module manifest for DivergentCortex.Witness
# Cross-platform CMTrace-compatible structured logger for PowerShell.
# Supports: Windows PowerShell 5.1 and PowerShell 7.4+ on Windows / Linux / macOS.
#
# FunctionsToExport lists EXACTLY the three public functions. Never '*'.
# Clear-LogFile, Get-PlatformContext, and Resolve-WitnessLogPath are private; NOT exported.

@{
    # Module identity
    RootModule           = 'DivergentCortex.Witness.psm1'
    ModuleVersion        = '2026.11.23.064'
    GUID                 = 'b4e2f1c3-8d47-4a9e-b5f0-3c6a1e2d8b9f'
    Author               = 'Curtis Leggett'
    CompanyName          = 'Divergent Cortex'
    Copyright            = '(c) 2026 Divergent Cortex. All rights reserved.'
    Description          = 'The logging backbone of an entire PowerShell fleet - a hardened, cross-platform, CMTrace-compatible logging module for Windows PowerShell 5.1 and PowerShell 7.'

    # Minimum supported version of PowerShell
    PowerShellVersion    = '5.1'

    # Compatible editions
    CompatiblePSEditions = @('Desktop', 'Core')

    # Explicit export list - never '*'
    FunctionsToExport    = @(
        'Write-Log'
        'Initialize-Log'
        'Write-LogFinal'
    )

    # Nothing else exported - private helpers stay private
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    # Module tags for PowerShell Gallery discovery
    PrivateData          = @{
        PSData = @{
            Tags         = @('Logging', 'CMTrace', 'Cross-Platform', 'Structured-Logging', 'PowerShell', 'DivergentCortex', 'Witness')
            ProjectUri   = 'https://github.com/DivergentCortex/Witness'
            LicenseUri   = 'https://github.com/DivergentCortex/Witness/blob/main/LICENSE'
            ReleaseNotes = 'See docs/CHANGELOG.md in the repository.'
        }
    }
}
