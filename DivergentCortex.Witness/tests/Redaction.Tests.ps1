# redaction cases shared with the divergent cortex python, typescript and shell loggers,
# so every language logger produces identical text from the same input

BeforeDiscovery {
    # windows powershell 5.1 passes a parsed json array down the pipeline as one object
    $parsed = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'redaction_cases.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $RedactionCases = foreach ($case in $parsed) {
        @{ Name = $case.name; InputText = $case.input; Expected = $case.expected }
    }
}

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $moduleRoot 'DivergentCortex.Witness.psd1') -Force -ErrorAction Stop
    $script:WitnessModule = Get-Module DivergentCortex.Witness
}

Describe 'ConvertTo-WitnessRedactedText' {
    It 'redacts: <Name>' -ForEach $RedactionCases {
        $actual = & $script:WitnessModule { param($text) ConvertTo-WitnessRedactedText -Text $text } $InputText
        $actual | Should -BeExactly $Expected
    }

    It 'redacts a 200000 character unbroken run in under 2000 ms' {
        $longRun = 'a' * 200000
        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        $null = & $script:WitnessModule { param($text) ConvertTo-WitnessRedactedText -Text $text } $longRun
        $timer.Stop()
        $timer.Elapsed.TotalMilliseconds | Should -BeLessThan 2000
    }
}

Describe 'Write-Log redaction in the log file' {
    BeforeAll {
        # the token is assembled here so the source holds no credential-shaped literal
        $script:Token = 'ghp_' + 'A1b2C3d4E5f6G7h8I9j0'
        $script:LogPath = Join-Path $TestDrive 'redact.log'
        Initialize-Log -LogFilePath $script:LogPath -ScriptName 'RedactionTest' -Version '1.0' 6>$null
        Write-Log -Message "pushing with $script:Token to https://bob:hunter2hunter2@host/r.git" -Severity Info -WriteBackToHost:$false
        $script:Content = Get-Content -LiteralPath $script:LogPath -Raw -Encoding UTF8
    }

    It 'leaves neither the token nor the password in the file' {
        $script:Content.Contains($script:Token) | Should -BeFalse
        $script:Content.Contains('hunter2hunter2') | Should -BeFalse
    }

    It 'writes the redacted message on the log line' {
        $script:Content.Contains('<![LOG[pushing with [REDACTED] to https://bob:[REDACTED]@host/r.git]LOG]!>') | Should -BeTrue
    }
}
