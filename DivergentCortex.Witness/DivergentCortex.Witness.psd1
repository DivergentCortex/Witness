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
    ModuleVersion        = '1.0.1'
    GUID                 = 'b4e2f1c3-8d47-4a9e-b5f0-3c6a1e2d8b9f'
    Author               = 'Curtis Leggett'
    CompanyName          = 'DivergentCortex'
    Copyright            = '(c) 2026 Curtis Leggett. All rights reserved.'
    Description          = 'There is always a Witness. CMTrace-compatible structured logger for PowerShell. Cross-platform (Windows/Linux/macOS), supports PS 5.1 and PS 7.4+.'

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

    # Module tags for PowerShell Gallery discovery (Fix [8]: corrected ProjectUri casing)
    PrivateData          = @{
        PSData = @{
            Tags         = @('Logging', 'CMTrace', 'Cross-Platform', 'Structured-Logging', 'PowerShell', 'DivergentCortex', 'Witness')
            ProjectUri   = 'https://github.com/DivergentCortex/Witness'
            LicenseUri   = 'https://github.com/DivergentCortex/Witness/blob/main/LICENSE'
            ReleaseNotes = 'v1.0.1: Review fixes - caller-scope path resolution, per-write context, cleanup sentinel lifecycle, macOS detection, line-ending consistency, Write-LogFinal ValidateSet.'
        }
    }
}
