#Requires -Version 5.1
<#
.SYNOPSIS
    Pester v5 tests for the Witness failure path of Initialize-Log and Get-BannerConfig.

.DESCRIPTION
    Neither function throws or calls Write-Warning. A failure is reported through
    Write-WitnessFailureLine and the caller gets a usable result.
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '')]
param()

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent $PSScriptRoot
    $script:ManifestPath = Join-Path $script:ModuleRoot 'DivergentCortex.Witness.psd1'
    $script:WorkDir = Join-Path ([System.IO.Path]::GetTempPath()) "witness-failurepath-$PID"
    New-Item -Path $script:WorkDir -ItemType Directory -Force | Out-Null
    Remove-Module DivergentCortex.Witness -Force -ErrorAction SilentlyContinue
    Import-Module $script:ManifestPath -Force -ErrorAction Stop
}

Describe 'Initialize-Log failure path' {

    It 'an uncreatable log folder does not throw, reports the failure and still prints the banner' {
        $blocker = Join-Path $script:WorkDir 'blocker_file'
        [System.IO.File]::WriteAllText($blocker, 'not a folder')
        $logPath = Join-Path (Join-Path $blocker 'sub') 'init.log'

        $errWriter = New-Object System.IO.StringWriter
        $originalErr = [System.Console]::Error
        [System.Console]::SetError($errWriter)
        try {
            { Initialize-Log -LogFilePath $logPath -ScriptName 'FailPathInit' -Version '0.0' 6>$null } |
                Should -Not -Throw -Because 'a failed folder create or banner write is reported, never thrown'
        }
        finally {
            [System.Console]::SetError($originalErr)
        }
        $errWriter.ToString() | Should -Match 'could not create log folder'
        $errWriter.ToString() | Should -Match 'failed to write banner'
    }

    It 'does not call Write-Warning on a banner write failure' {
        $blocker = Join-Path $script:WorkDir 'blocker_file2'
        [System.IO.File]::WriteAllText($blocker, 'not a folder')
        $logPath = Join-Path (Join-Path $blocker 'sub') 'init2.log'

        $errWriter = New-Object System.IO.StringWriter
        $originalErr = [System.Console]::Error
        [System.Console]::SetError($errWriter)
        try {
            $warnings = @()
            Initialize-Log -LogFilePath $logPath -ScriptName 'FailPathInit2' -Version '0.0' -WarningVariable warnings 6>$null
        }
        finally {
            [System.Console]::SetError($originalErr)
        }
        $warnings.Count | Should -Be 0 -Because 'failures go through the Witness failure line, not Write-Warning'
    }
}

Describe 'Get-BannerConfig failure path' {

    It 'a malformed config falls back to the shipped default with no warning' {
        $badConfig = Join-Path $script:WorkDir 'bad_banner.psd1'
        [System.IO.File]::WriteAllText($badConfig, '@{ Enabled = ')
        $loader = Join-Path $script:ModuleRoot 'Private/Get-BannerConfig.ps1'

        $errWriter = New-Object System.IO.StringWriter
        $originalErr = [System.Console]::Error
        [System.Console]::SetError($errWriter)
        $warnings = @()
        try {
            $module = Get-Module DivergentCortex.Witness
            $config = & $module {
                param($file, $bad)
                . $file
                Get-BannerConfig -ConfigPath $bad -WarningVariable +warnings
            } $loader $badConfig
        }
        finally {
            [System.Console]::SetError($originalErr)
        }

        $config | Should -BeOfType [hashtable]
        $config.ContainsKey('Enabled') | Should -Be $true
        $warnings.Count | Should -Be 0
    }
}
