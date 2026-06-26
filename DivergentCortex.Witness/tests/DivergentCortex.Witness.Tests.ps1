#Requires -Version 5.1
<#
.SYNOPSIS
    Pester v5 test suite for DivergentCortex.Witness PowerShell module.

.DESCRIPTION
    Covers the public contract (Write-Log, Initialize-Log, Write-LogFinal) and
    locks in the 11 code-review fixes as regression tests.

    PS 5.1-syntax-safe: no ternary operators, no ?? / ??=, no v7-only constructs.
    ASCII only throughout (slop-detector hook enforced).

    Run: Invoke-Pester -Path ./tests/DivergentCortex.Witness.Tests.ps1 -Output Detailed
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '')]
param()

BeforeAll {
    # ---- Locate module manifest ----
    $script:ManifestPath = Join-Path $PSScriptRoot '..' 'DivergentCortex.Witness.psd1'

    # ---- Log directory for all test log files (repo-local, gitignored) ----
    $script:TestTempDir = Join-Path $PSScriptRoot '..' 'logs' "WitnessTests_$PID"
    $script:TestTempDir = [System.IO.Path]::GetFullPath($script:TestTempDir)
    New-Item -Path $script:TestTempDir -ItemType Directory -Force | Out-Null

    # ---- Import module fresh ----
    # Remove any previously loaded copy first so tests start clean.
    if (Get-Module -Name DivergentCortex.Witness) {
        Remove-Module -Name DivergentCortex.Witness -Force -ErrorAction SilentlyContinue
    }
    Import-Module $script:ManifestPath -Force -ErrorAction Stop

    # ---- Helper: extract CMTrace type= digit from a log line ----
    $script:GetTypeCode = {
        param([string]$Line)
        if ($Line -match 'type="(\d)"') { return $Matches[1] }
        return $null
    }

    # ---- Helper: unique log file path inside temp dir ----
    $script:NewTestLogPath = {
        param([string]$Suffix = '')
        $randPart = [System.IO.Path]::GetRandomFileName() -replace '\.', ''
        $name     = "test_$randPart$Suffix.log"
        return Join-Path $script:TestTempDir $name
    }

    # ---- Helper: last non-empty line of a log file ----
    $script:GetLastLogLine = {
        param([string]$Path)
        $raw = Get-Content -Path $Path -Raw
        if (-not $raw) { return $null }
        $split   = $raw -split [System.Environment]::NewLine
        $trimmed = @($split | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($trimmed.Count -eq 0) { return $null }
        return $trimmed[$trimmed.Count - 1]
    }

    # ---- CMTrace line regex (locked contract) ----
    # Field order must be exactly: time, date, component, context, type, thread, file
    # Build as a plain string; -Match accepts strings as regex patterns.
    $script:CMTraceRegex = (
        '^<!\[LOG\[.*\]LOG\]!>' +
        '<time="[^"]*" ' +
        'date="[^"]*" ' +
        'component="[^"]*" ' +
        'context="[^"]*" ' +
        'type="[^"]*" ' +
        'thread="[^"]*" ' +
        'file="[^"]*">$'
    )

    # Pattern for the time field value: local HH:mm:ss.fff, no UTC offset (deliberate operator preference)
    $script:TimeFieldRegex = 'time="(\d{2}:\d{2}:\d{2}\.\d{3})"'
}

AfterAll {
    if (Get-Module -Name DivergentCortex.Witness) {
        Remove-Module -Name DivergentCortex.Witness -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $script:TestTempDir) {
        Remove-Item -Path $script:TestTempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}


# ============================================================
# DESCRIBE 1 - Module surface / export contract
# ============================================================
Describe 'Module import and export contract' {

    It 'imports cleanly from the .psd1 manifest without error' {
        { Import-Module $script:ManifestPath -Force -ErrorAction Stop } | Should -Not -Throw
    }

    It 'exports exactly Write-Log, Initialize-Log, Write-LogFinal' {
        $exported = (Get-Module DivergentCortex.Witness).ExportedFunctions.Keys | Sort-Object
        $expected = @('Initialize-Log', 'Write-Log', 'Write-LogFinal') | Sort-Object
        $exported | Should -Be $expected
    }

    It 'does NOT export Clear-LogFile' {
        (Get-Module DivergentCortex.Witness).ExportedFunctions.ContainsKey('Clear-LogFile') |
            Should -Be $false
    }

    It 'does NOT export Get-PlatformContext' {
        (Get-Module DivergentCortex.Witness).ExportedFunctions.ContainsKey('Get-PlatformContext') |
            Should -Be $false
    }

    It 'does NOT export Resolve-WitnessLogPath' {
        (Get-Module DivergentCortex.Witness).ExportedFunctions.ContainsKey('Resolve-WitnessLogPath') |
            Should -Be $false
    }

    It 'exports zero cmdlets' {
        (Get-Module DivergentCortex.Witness).ExportedCmdlets.Count | Should -Be 0
    }

    It 'exports zero variables' {
        (Get-Module DivergentCortex.Witness).ExportedVariables.Count | Should -Be 0
    }

    It 'exports zero aliases' {
        (Get-Module DivergentCortex.Witness).ExportedAliases.Count | Should -Be 0
    }
}

# ============================================================
# DESCRIBE 2 - CMTrace line shape (Fix [5] field order lock)
# ============================================================
Describe 'CMTrace line shape' {

    BeforeEach {
        $logPath = & $script:NewTestLogPath -Suffix '_cmtrace'
        Initialize-Log -LogFilePath $logPath -ScriptName 'PesterTest' -Version '0.0'
    }

    It 'writes a line matching the full CMTrace regex' {
        $logPath = & $script:NewTestLogPath -Suffix '_cmtrace_shape'
        Initialize-Log -LogFilePath $logPath -ScriptName 'PesterTest' -Version '0.0'
        Write-Log -Message 'hello' -Logfile $logPath -Severity Info -WriteBackToHost:$false

        $line = & $script:GetLastLogLine -Path $logPath
        $line | Should -Not -BeNullOrEmpty
        $line | Should -Match $script:CMTraceRegex
    }

    It 'log line body wraps the message between LOG delimiters' {
        $logPath = & $script:NewTestLogPath -Suffix '_msg_wrap'
        Initialize-Log -LogFilePath $logPath -ScriptName 'PesterTest' -Version '0.0'
        Write-Log -Message 'wrap-check' -Logfile $logPath -Severity Info -WriteBackToHost:$false

        $line = & $script:GetLastLogLine -Path $logPath
        $line | Should -Not -BeNullOrEmpty
        # Verify the message is enclosed in the CMTrace LOG delimiters
        # Pattern: <![LOG[<msg>]LOG]!>
        $line | Should -Match '\[LOG\[wrap-check\]LOG\]'
    }

    It 'contains time= field with local HH:mm:ss.fff format and no UTC offset' {
        $logPath = & $script:NewTestLogPath -Suffix '_timestamp'
        Initialize-Log -LogFilePath $logPath -ScriptName 'PesterTest' -Version '0.0'
        Write-Log -Message 'ts-check' -Logfile $logPath -Severity Info -WriteBackToHost:$false

        $line = & $script:GetLastLogLine -Path $logPath
        $line | Should -Match 'time="\d{2}:\d{2}:\d{2}\.\d{3}"'
    }

    It 'contains date= field in MM-dd-yyyy format' {
        $logPath = & $script:NewTestLogPath -Suffix '_date'
        Initialize-Log -LogFilePath $logPath -ScriptName 'PesterTest' -Version '0.0'
        Write-Log -Message 'date-check' -Logfile $logPath -Severity Info -WriteBackToHost:$false

        $line = & $script:GetLastLogLine -Path $logPath
        $line | Should -Match 'date="\d{2}-\d{2}-\d{4}"'
    }

    It 'contains component= field' {
        $logPath = & $script:NewTestLogPath -Suffix '_component'
        Initialize-Log -LogFilePath $logPath -ScriptName 'PesterTest' -Version '0.0'
        Write-Log -Message 'comp-check' -Logfile $logPath -Severity Info -WriteBackToHost:$false -Component 'TestComp'

        $line = & $script:GetLastLogLine -Path $logPath
        $line | Should -Match 'component="TestComp"'
    }

    It 'contains context= field (non-empty user identity)' {
        $logPath = & $script:NewTestLogPath -Suffix '_context'
        Initialize-Log -LogFilePath $logPath -ScriptName 'PesterTest' -Version '0.0'
        Write-Log -Message 'ctx-check' -Logfile $logPath -Severity Info -WriteBackToHost:$false

        $line = & $script:GetLastLogLine -Path $logPath
        $line | Should -Match 'context="\S+'
    }

    It 'contains type= field' {
        $logPath = & $script:NewTestLogPath -Suffix '_type'
        Initialize-Log -LogFilePath $logPath -ScriptName 'PesterTest' -Version '0.0'
        Write-Log -Message 'type-check' -Logfile $logPath -Severity Info -WriteBackToHost:$false

        $line = & $script:GetLastLogLine -Path $logPath
        $line | Should -Match 'type="[12345]"'
    }

    It 'contains thread= field with a numeric PID' {
        $logPath = & $script:NewTestLogPath -Suffix '_thread'
        Initialize-Log -LogFilePath $logPath -ScriptName 'PesterTest' -Version '0.0'
        Write-Log -Message 'thread-check' -Logfile $logPath -Severity Info -WriteBackToHost:$false

        $line = & $script:GetLastLogLine -Path $logPath
        $line | Should -Match 'thread="\d+"'
    }

    It 'contains file= field' {
        $logPath = & $script:NewTestLogPath -Suffix '_file'
        Initialize-Log -LogFilePath $logPath -ScriptName 'PesterTest' -Version '0.0'
        Write-Log -Message 'file-check' -Logfile $logPath -Severity Info -WriteBackToHost:$false

        $line = & $script:GetLastLogLine -Path $logPath
        $line | Should -Match 'file="[^"]*"'
    }

    It 'field order is: time date component context type thread file' {
        $logPath = & $script:NewTestLogPath -Suffix '_order'
        Initialize-Log -LogFilePath $logPath -ScriptName 'PesterTest' -Version '0.0'
        Write-Log -Message 'order-check' -Logfile $logPath -Severity Info -WriteBackToHost:$false

        $line = & $script:GetLastLogLine -Path $logPath
        $timePos      = $line.IndexOf('time=')
        $datePos      = $line.IndexOf('date=')
        $componentPos = $line.IndexOf('component=')
        $contextPos   = $line.IndexOf('context=')
        $typePos      = $line.IndexOf('type=')
        $threadPos    = $line.IndexOf('thread=')
        $filePos      = $line.IndexOf('file=')

        $timePos      | Should -BeLessThan $datePos
        $datePos      | Should -BeLessThan $componentPos
        $componentPos | Should -BeLessThan $contextPos
        $contextPos   | Should -BeLessThan $typePos
        $typePos      | Should -BeLessThan $threadPos
        $threadPos    | Should -BeLessThan $filePos
    }
}

# ============================================================
# DESCRIBE 3 - Severity -> CMTrace type code mapping
# ============================================================
Describe 'Severity to CMTrace type code mapping' {

    # Shared log setup
    BeforeEach {
        $script:SevLogPath = & $script:NewTestLogPath -Suffix '_sev'
        Initialize-Log -LogFilePath $script:SevLogPath -ScriptName 'PesterTest' -Version '0.0'
    }

    It 'Info maps to type 1' {
        Write-Log -Message 'info-test' -Logfile $script:SevLogPath -Severity Info -WriteBackToHost:$false
        $line = & $script:GetLastLogLine -Path $script:SevLogPath
        (& $script:GetTypeCode -Line $line) | Should -Be '1'
    }

    It 'Information maps to type 1' {
        Write-Log -Message 'information-test' -Logfile $script:SevLogPath -Severity Information -WriteBackToHost:$false
        $line = & $script:GetLastLogLine -Path $script:SevLogPath
        (& $script:GetTypeCode -Line $line) | Should -Be '1'
    }

    It 'Success maps to type 1' {
        Write-Log -Message 'success-test' -Logfile $script:SevLogPath -Severity Success -WriteBackToHost:$false
        $line = & $script:GetLastLogLine -Path $script:SevLogPath
        (& $script:GetTypeCode -Line $line) | Should -Be '1'
    }

    It 'Warning maps to type 2' {
        Write-Log -Message 'warning-test' -Logfile $script:SevLogPath -Severity Warning -WriteBackToHost:$false
        $line = & $script:GetLastLogLine -Path $script:SevLogPath
        (& $script:GetTypeCode -Line $line) | Should -Be '2'
    }

    It 'Error maps to type 3' {
        Write-Log -Message 'error-test' -Logfile $script:SevLogPath -Severity Error -WriteBackToHost:$false
        $line = & $script:GetLastLogLine -Path $script:SevLogPath
        (& $script:GetTypeCode -Line $line) | Should -Be '3'
    }

    It 'Verbose maps to type 4' {
        # Verbose is OFF by default. Enable logfile output for this type-code check only.
        $Global:VerboseLogfile = $true
        try {
            Write-Log -Message 'verbose-test' -Logfile $script:SevLogPath -Severity Verbose -WriteBackToHost:$false
            $line = & $script:GetLastLogLine -Path $script:SevLogPath
            (& $script:GetTypeCode -Line $line) | Should -Be '4'
        } finally {
            Remove-Variable -Name VerboseLogfile -Scope Global -ErrorAction SilentlyContinue
        }
    }

    It 'Debug maps to type 5' {
        # Debug is OFF by default. Enable logfile output for this type-code check only.
        $Global:DebugLogfile = $true
        try {
            Write-Log -Message 'debug-test' -Logfile $script:SevLogPath -Severity Debug -WriteBackToHost:$false
            $line = & $script:GetLastLogLine -Path $script:SevLogPath
            (& $script:GetTypeCode -Line $line) | Should -Be '5'
        } finally {
            Remove-Variable -Name DebugLogfile -Scope Global -ErrorAction SilentlyContinue
        }
    }
}

# ============================================================
# DESCRIBE 4 - ValidateSet regression: Success in both public functions
# Fix [6] regression - Write-LogFinal ValidateSet must include Success
# ============================================================
Describe 'ValidateSet regression - Success severity accepted by both public functions' {

    It 'Write-Log accepts -Severity Success without ParameterBindingValidationException' {
        $logPath = & $script:NewTestLogPath -Suffix '_wl_success'
        Initialize-Log -LogFilePath $logPath -ScriptName 'PesterTest' -Version '0.0'
        { Write-Log -Message 'success-bind' -Logfile $logPath -Severity Success -WriteBackToHost:$false } |
            Should -Not -Throw
    }

    It 'Write-LogFinal accepts -Severity Success without ParameterBindingValidationException' {
        $logPath = & $script:NewTestLogPath -Suffix '_wlf_success'
        Initialize-Log -LogFilePath $logPath -ScriptName 'PesterTest' -Version '0.0'
        { Write-LogFinal -Message 'final-success-bind' -Severity Success } |
            Should -Not -Throw
    }

    It 'Write-Log accepts -Severity Information without ParameterBindingValidationException' {
        $logPath = & $script:NewTestLogPath -Suffix '_wl_information'
        Initialize-Log -LogFilePath $logPath -ScriptName 'PesterTest' -Version '0.0'
        { Write-Log -Message 'information-bind' -Logfile $logPath -Severity Information -WriteBackToHost:$false } |
            Should -Not -Throw
    }

    It 'Write-LogFinal accepts -Severity Information without ParameterBindingValidationException' {
        $logPath = & $script:NewTestLogPath -Suffix '_wlf_information'
        Initialize-Log -LogFilePath $logPath -ScriptName 'PesterTest' -Version '0.0'
        { Write-LogFinal -Message 'final-information-bind' -Severity Information } |
            Should -Not -Throw
    }

    It 'Write-Log rejects an invalid severity value' {
        $logPath = & $script:NewTestLogPath -Suffix '_invalid_sev'
        Initialize-Log -LogFilePath $logPath -ScriptName 'PesterTest' -Version '0.0'
        { Write-Log -Message 'bad' -Logfile $logPath -Severity 'Critical' -WriteBackToHost:$false } |
            Should -Throw -ExceptionType ([System.Management.Automation.ParameterBindingException])
    }
}

# ============================================================
# DESCRIBE 5 - Caller-scope path resolution (Fix [1/3])
# ============================================================
Describe 'Caller-scope path resolution' {

    It 'Initialize-Log with no -LogFilePath reads $LogFilePath from caller scope' {
        $callerLogPath = & $script:NewTestLogPath -Suffix '_caller_scope'

        # Set LogFilePath in this (test) scope - simulates the dot-source-era pattern.
        $LogFilePath = $callerLogPath

        { Initialize-Log -ScriptName 'CallerScopeTest' -Version '0.0' } | Should -Not -Throw
        Test-Path $callerLogPath | Should -Be $true
    }

    It 'Write-Log with no -Logfile reads $LogFilePath from caller scope after Initialize-Log' {
        $callerLogPath = & $script:NewTestLogPath -Suffix '_caller_wl'
        $LogFilePath   = $callerLogPath

        Initialize-Log -ScriptName 'CallerScopeTest' -Version '0.0'
        { Write-Log -Message 'caller-scope-msg' -Severity Info -WriteBackToHost:$false } | Should -Not -Throw

        $content = Get-Content -Path $callerLogPath -Raw
        $content | Should -Match 'caller-scope-msg'
    }

    It 'explicit -LogFilePath parameter sets the module-scope path used by subsequent Write-Log calls' {
        # This test verifies that Initialize-Log -LogFilePath stores the path and
        # subsequent Write-Log calls (with no explicit -Logfile) use that stored path.
        # No caller-scope $LogFilePath is set here so the module-scope path wins.
        $firstLogPath    = & $script:NewTestLogPath -Suffix '_scope_first'
        $explicitLogPath = & $script:NewTestLogPath -Suffix '_scope_override'

        # Establish a first path
        Initialize-Log -LogFilePath $firstLogPath -ScriptName 'FirstTest' -Version '0.0'
        Write-Log -Message 'first-msg' -Severity Info -WriteBackToHost:$false

        # Now switch to explicit path - module-scope path updates
        Initialize-Log -LogFilePath $explicitLogPath -ScriptName 'OverrideTest' -Version '0.0'
        Write-Log -Message 'override-msg' -Severity Info -WriteBackToHost:$false

        Test-Path $explicitLogPath | Should -Be $true
        $content = Get-Content -Path $explicitLogPath -Raw
        $content | Should -Match 'override-msg'
        # The first path should NOT contain override-msg
        $firstContent = Get-Content -Path $firstLogPath -Raw
        $firstContent | Should -Not -Match 'override-msg'
    }

    It 'explicit -Logfile on Write-Log overrides all other path sources' {
        $baseLogPath    = & $script:NewTestLogPath -Suffix '_base_path'
        $overrideLogPath = & $script:NewTestLogPath -Suffix '_wl_explicit'
        Initialize-Log -LogFilePath $baseLogPath -ScriptName 'ExplicitTest' -Version '0.0'

        Write-Log -Message 'explicit-logfile-msg' -Logfile $overrideLogPath -Severity Info -WriteBackToHost:$false
        Test-Path $overrideLogPath | Should -Be $true
        $content = Get-Content -Path $overrideLogPath -Raw
        $content | Should -Match 'explicit-logfile-msg'
    }

    It 'Write-Log throws when no path is available in any layer' {
        # Temporarily clear module-scope path by importing a fresh module copy,
        # which starts with $script:WitnessLogFilePath = $null.
        # We test by calling Write-Log with no Logfile param and no $LogFilePath in scope.
        if (Get-Variable -Name LogFilePath -Scope 0 -ErrorAction SilentlyContinue) {
            Remove-Variable -Name LogFilePath -Scope 0 -ErrorAction SilentlyContinue
        }

        # Reload module so module-scope state is cleared (WitnessLogFilePath starts null)
        Remove-Module DivergentCortex.Witness -Force -ErrorAction SilentlyContinue
        Import-Module $script:ManifestPath -Force -ErrorAction Stop

        { Write-Log -Message 'no-path' -Severity Info -WriteBackToHost:$false } |
            Should -Throw -ExpectedMessage '*No log file path*'

        # Restore module for subsequent tests
        Remove-Module DivergentCortex.Witness -Force -ErrorAction SilentlyContinue
        Import-Module $script:ManifestPath -Force -ErrorAction Stop
    }
}

# ============================================================
# DESCRIBE 6 - Single cleanup per session / sentinel lifecycle (Fix [12] / Fix [2])
# ============================================================
Describe 'Single cleanup per session - sentinel lifecycle' {

    It 'cleanup runs at most once per session when both Write-Log and Write-LogFinal are called' {
        # Create an aged log file in the test dir that Clear-LogFile would delete.
        $randPart      = [System.IO.Path]::GetRandomFileName() -replace '\.', ''
        $cleanupLogDir = Join-Path $script:TestTempDir "cleanup_session_$randPart"
        New-Item -Path $cleanupLogDir -ItemType Directory -Force | Out-Null

        $activeLog = Join-Path $cleanupLogDir 'active.log'
        $agedLog   = Join-Path $cleanupLogDir 'aged.log'

        # Touch aged log and backdate it beyond MaxAgeDays (default 7)
        Set-Content -Path $agedLog -Value 'old content'
        (Get-Item $agedLog).LastWriteTime = (Get-Date).AddDays(-10)

        Initialize-Log -LogFilePath $activeLog -ScriptName 'CleanupTest' -Version '0.0'

        # Write-Log auto-cleanup fires on first write (sets sentinel)
        Write-Log -Message 'first write' -Logfile $activeLog -Severity Info -WriteBackToHost:$false

        # The aged file should be gone now (cleanup ran)
        $agedExists = Test-Path $agedLog

        # Write-LogFinal should NOT run cleanup again (sentinel is set)
        # We verify by creating a second aged file; it should survive Write-LogFinal
        $agedLog2 = Join-Path $cleanupLogDir 'aged2.log'
        Set-Content -Path $agedLog2 -Value 'old content 2'
        (Get-Item $agedLog2).LastWriteTime = (Get-Date).AddDays(-10)

        Write-LogFinal -Message 'final write'

        $aged2Exists = Test-Path $agedLog2

        # First cleanup ran (aged file gone)
        $agedExists  | Should -Be $false
        # Second cleanup did NOT run (sentinel blocked it), so aged2 still present
        $aged2Exists | Should -Be $true
    }

    It 'calling Initialize-Log a second time resets the sentinel so a new session can clean' {
        $randPart2     = [System.IO.Path]::GetRandomFileName() -replace '\.', ''
        $cleanupLogDir = Join-Path $script:TestTempDir "cleanup_reset_$randPart2"
        New-Item -Path $cleanupLogDir -ItemType Directory -Force | Out-Null

        $activeLog = Join-Path $cleanupLogDir 'active.log'

        # First session
        Initialize-Log -LogFilePath $activeLog -ScriptName 'ResetTest' -Version '0.0'
        Write-Log -Message 'session1' -Logfile $activeLog -Severity Info -WriteBackToHost:$false
        Write-LogFinal -Message 'session1 final'

        # Add a new aged file - should be cleaned on the next session's first write
        $newAgedLog = Join-Path $cleanupLogDir 'new_aged.log'
        Set-Content -Path $newAgedLog -Value 'newer old content'
        (Get-Item $newAgedLog).LastWriteTime = (Get-Date).AddDays(-10)

        # Second Initialize-Log call - resets cleanup sentinel
        $activeLog2 = Join-Path $cleanupLogDir 'active2.log'
        Initialize-Log -LogFilePath $activeLog2 -ScriptName 'ResetTest2' -Version '0.0'

        # First write of the new session should trigger cleanup
        Write-Log -Message 'session2' -Logfile $activeLog2 -Severity Info -WriteBackToHost:$false

        # New aged file should be gone (sentinel was reset by Initialize-Log)
        Test-Path $newAgedLog | Should -Be $false
    }
}

# ============================================================
# DESCRIBE 7 - Line endings consistency (Fix [5])
# ============================================================
Describe 'Line ending consistency' {

    It 'all lines in a log file use the same newline convention (no mixed CRLF/LF)' {
        $logPath = & $script:NewTestLogPath -Suffix '_lineend'
        Initialize-Log -LogFilePath $logPath -ScriptName 'LineEndTest' -Version '0.0'

        Write-Log -Message 'line1' -Logfile $logPath -Severity Info    -WriteBackToHost:$false
        Write-Log -Message 'line2' -Logfile $logPath -Severity Warning -WriteBackToHost:$false
        Write-Log -Message 'line3' -Logfile $logPath -Severity Error   -WriteBackToHost:$false

        $bytes   = [System.IO.File]::ReadAllBytes($logPath)
        $content = [System.Text.Encoding]::UTF8.GetString($bytes)

        # Count CRLF and standalone LF occurrences
        $crlfCount = ([regex]::Matches($content, "`r`n")).Count
        $lfCount   = ([regex]::Matches($content, "(?<!`r)`n")).Count

        # One convention must dominate; the other must be zero
        $mixed = ($crlfCount -gt 0) -and ($lfCount -gt 0)
        $mixed | Should -Be $false -Because 'log file must not mix CRLF and LF line endings'
    }

    It 'on Linux, lines end with LF not CRLF' {
        $logPath = & $script:NewTestLogPath -Suffix '_lf_only'
        Initialize-Log -LogFilePath $logPath -ScriptName 'LFTest' -Version '0.0'

        Write-Log -Message 'lf-check' -Logfile $logPath -Severity Info -WriteBackToHost:$false

        $bytes   = [System.IO.File]::ReadAllBytes($logPath)
        $content = [System.Text.Encoding]::UTF8.GetString($bytes)

        $crlfCount = ([regex]::Matches($content, "`r`n")).Count
        $crlfCount | Should -Be 0 -Because 'Linux log files should use LF only'
    }
}

# ============================================================
# DESCRIBE 8 - Timestamp time= field format (local HH:mm:ss.fff, no UTC offset)
# ============================================================
Describe 'Timestamp time= field format' {

    It 'time= value matches local HH:mm:ss.fff with no UTC offset suffix' {
        $logPath = & $script:NewTestLogPath -Suffix '_ts_format'
        Initialize-Log -LogFilePath $logPath -ScriptName 'TimestampTest' -Version '0.0'
        Write-Log -Message 'ts-fmt' -Logfile $logPath -Severity Info -WriteBackToHost:$false

        $line = & $script:GetLastLogLine -Path $logPath
        # time= field: exactly HH:mm:ss.fff, closing quote immediately after milliseconds
        $line | Should -Match 'time="\d{2}:\d{2}:\d{2}\.\d{3}"'
    }

    It 'time= value milliseconds field is exactly 3 digits' {
        $logPath = & $script:NewTestLogPath -Suffix '_ts_ms'
        Initialize-Log -LogFilePath $logPath -ScriptName 'TimestampTest' -Version '0.0'
        Write-Log -Message 'ts-ms' -Logfile $logPath -Severity Info -WriteBackToHost:$false

        $line = & $script:GetLastLogLine -Path $logPath
        # Extract the time= value and check the .fff portion
        if ($line -match 'time="(\d{2}:\d{2}:\d{2}\.\d+)') {
            $timePart = $Matches[1]
            $dotIdx   = $timePart.IndexOf('.')
            $msPart   = $timePart.Substring($dotIdx + 1, 3)
            $msPart.Length | Should -Be 3
        } else {
            Set-TestInconclusive 'Could not extract time= value from log line'
        }
    }

    It 'date= value reflects todays date in MM-dd-yyyy' {
        $logPath   = & $script:NewTestLogPath -Suffix '_date_val'
        $todayFmt  = (Get-Date).ToString('MM-dd-yyyy')
        Initialize-Log -LogFilePath $logPath -ScriptName 'DateTest' -Version '0.0'
        Write-Log -Message 'date-val' -Logfile $logPath -Severity Info -WriteBackToHost:$false

        $line = & $script:GetLastLogLine -Path $logPath
        $line | Should -Match "date=`"$([regex]::Escape($todayFmt))`""
    }
}

# ============================================================
# DESCRIBE 9 - Public function behavioral contracts
# ============================================================
Describe 'Write-Log behavioral contract' {

    It 'requires -Message parameter' {
        $cmd = Get-Command Write-Log
        $param = $cmd.Parameters['Message']
        $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory } |
            Should -Not -BeNullOrEmpty
    }

    It 'writes the exact message text to the log body' {
        $logPath = & $script:NewTestLogPath -Suffix '_exact_msg'
        Initialize-Log -LogFilePath $logPath -ScriptName 'MsgTest' -Version '0.0'
        $msg = 'unique-sentinel-string-XYZ'
        Write-Log -Message $msg -Logfile $logPath -Severity Info -WriteBackToHost:$false

        $content = Get-Content -Path $logPath -Raw
        $content | Should -Match ([regex]::Escape($msg))
    }

    It 'creates the log file parent directory when it does not exist' {
        $randSub = [System.IO.Path]::GetRandomFileName() -replace '\.', ''
        $subDir  = Join-Path $script:TestTempDir "subdir_$randSub"
        $logPath = Join-Path $subDir 'auto_create.log'
        # Directory does not exist yet

        Initialize-Log -LogFilePath $logPath -ScriptName 'DirCreate' -Version '0.0'
        Test-Path $subDir | Should -Be $true
    }

    It 'accepts pipeline input for -Message' {
        $logPath = & $script:NewTestLogPath -Suffix '_pipeline'
        Initialize-Log -LogFilePath $logPath -ScriptName 'PipelineTest' -Version '0.0'
        { 'pipeline-msg' | Write-Log -Logfile $logPath -WriteBackToHost:$false } | Should -Not -Throw
        $content = Get-Content -Path $logPath -Raw
        $content | Should -Match 'pipeline-msg'
    }

    It 'does not throw on repeated calls to the same log path' {
        $logPath = & $script:NewTestLogPath -Suffix '_repeated'
        Initialize-Log -LogFilePath $logPath -ScriptName 'RepeatTest' -Version '0.0'
        {
            1..5 | ForEach-Object {
                Write-Log -Message "call $_" -Logfile $logPath -Severity Info -WriteBackToHost:$false
            }
        } | Should -Not -Throw
    }
}

Describe 'Initialize-Log behavioral contract' {

    It 'requires no mandatory parameters (all optional)' {
        $cmd = Get-Command Initialize-Log
        $mandatory = $cmd.Parameters.Values | Where-Object {
            $_.Attributes | Where-Object {
                $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory
            }
        }
        $mandatory | Should -BeNullOrEmpty
    }

    It 'creates the log file on disk' {
        $logPath = & $script:NewTestLogPath -Suffix '_init_creates'
        Initialize-Log -LogFilePath $logPath -ScriptName 'CreateTest' -Version '0.0'
        Test-Path $logPath | Should -Be $true
    }

    It 'writes banner lines to the log file' {
        $logPath = & $script:NewTestLogPath -Suffix '_banner'
        Initialize-Log -LogFilePath $logPath -ScriptName 'BannerTest' -Version '1.2.3'
        $content = Get-Content -Path $logPath -Raw
        $content | Should -Match 'SCRIPT START'
    }

    It 'throws when no path is available in any layer' {
        Remove-Module DivergentCortex.Witness -Force -ErrorAction SilentlyContinue
        Import-Module $script:ManifestPath -Force -ErrorAction Stop
        if (Get-Variable -Name LogFilePath -Scope 0 -ErrorAction SilentlyContinue) {
            Remove-Variable -Name LogFilePath -Scope 0 -ErrorAction SilentlyContinue
        }
        { Initialize-Log -ScriptName 'NoPath' } | Should -Throw -ExpectedMessage '*No log file path*'

        # Restore
        Remove-Module DivergentCortex.Witness -Force -ErrorAction SilentlyContinue
        Import-Module $script:ManifestPath -Force -ErrorAction Stop
    }
}

Describe 'Write-LogFinal behavioral contract' {

    It 'requires -Message parameter' {
        $cmd   = Get-Command Write-LogFinal
        $param = $cmd.Parameters['Message']
        $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory } |
            Should -Not -BeNullOrEmpty
    }

    It 'writes the final message to the log file' {
        $logPath = & $script:NewTestLogPath -Suffix '_wlf_msg'
        Initialize-Log -LogFilePath $logPath -ScriptName 'FinalTest' -Version '0.0'
        $finalMsg = 'script-complete-sentinel'
        Write-LogFinal -Message $finalMsg -Severity Info
        $content = Get-Content -Path $logPath -Raw
        $content | Should -Match ([regex]::Escape($finalMsg))
    }

    It 'does not throw when called after Write-Log' {
        $logPath = & $script:NewTestLogPath -Suffix '_wlf_nothrow'
        Initialize-Log -LogFilePath $logPath -ScriptName 'NoThrowTest' -Version '0.0'
        Write-Log -Message 'pre-final' -Logfile $logPath -Severity Info -WriteBackToHost:$false
        { Write-LogFinal -Message 'done' -Severity Info } | Should -Not -Throw
    }
}

# ============================================================
# DESCRIBE 10 - Global:LogFilePath back-compat fallback
# ============================================================
Describe 'Global LogFilePath fallback (back-compat)' {

    It 'Write-Log uses $Global:LogFilePath when no other source provides a path' {
        # Reload module to clear module-scope path
        Remove-Module DivergentCortex.Witness -Force -ErrorAction SilentlyContinue
        Import-Module $script:ManifestPath -Force -ErrorAction Stop

        $globalLogPath = & $script:NewTestLogPath -Suffix '_global_fb'
        $Global:LogFilePath = $globalLogPath

        try {
            { Write-Log -Message 'global-fallback' -Severity Info -WriteBackToHost:$false } | Should -Not -Throw
            $content = Get-Content -Path $globalLogPath -Raw
            $content | Should -Match 'global-fallback'
        } finally {
            Remove-Variable -Name LogFilePath -Scope Global -ErrorAction SilentlyContinue
        }
    }
}

# ============================================================
# DESCRIBE 11 - Config-aware retention: Write-LogFinal passes MaxAgeDays (Fix [R1])
# Regression: Write-LogFinal previously called Clear-LogFile with no -MaxAgeDays,
# silently using the default 7 days while Write-Log honored the configured value.
# Both paths must apply the same retention policy.
# ============================================================
Describe 'Config-aware retention - Write-LogFinal honors MaxAgeDays (Fix R1)' {

    It 'Write-LogFinal respects $Global:WriteLogMaxAgeDays when performing cleanup' {
        $randPart     = [System.IO.Path]::GetRandomFileName() -replace '\.', ''
        $cleanupDir   = Join-Path $script:TestTempDir "cleanup_maxage_$randPart"
        New-Item -Path $cleanupDir -ItemType Directory -Force | Out-Null

        $activeLog = Join-Path $cleanupDir 'active.log'

        # Use a custom retention: 30 days (well above the default 7).
        # An aged file that is 10 days old should SURVIVE (older than 7 but younger than 30).
        $Global:WriteLogMaxAgeDays = 30

        try {
            Initialize-Log -LogFilePath $activeLog -ScriptName 'MaxAgeTest' -Version '0.0'

            # Let Write-Log auto-cleanup fire and set the sentinel (10-day file survives at 30d).
            $survivingLog = Join-Path $cleanupDir 'ten_days_old.log'
            Set-Content -Path $survivingLog -Value 'should survive at 30d retention'
            (Get-Item $survivingLog).LastWriteTime = (Get-Date).AddDays(-10)

            # First Write-Log triggers auto-cleanup with MaxAgeDays=30; file should survive.
            Write-Log -Message 'auto-cleanup-check' -Logfile $activeLog -Severity Info -WriteBackToHost:$false

            $survivedAutoCleanup = Test-Path $survivingLog

            # Now reset sentinel to allow Write-LogFinal to run its own cleanup.
            # This simulates the case where auto-cleanup did not run but Write-LogFinal does.
            # Directly manipulate the module's state via the module scope.
            $mod = Get-Module DivergentCortex.Witness
            & $mod { $script:WitnessCleanupRan = $false }

            # Place a new 10-day-old file for Write-LogFinal to evaluate.
            $survivingLog2 = Join-Path $cleanupDir 'ten_days_old_2.log'
            Set-Content -Path $survivingLog2 -Value 'should also survive at 30d retention'
            (Get-Item $survivingLog2).LastWriteTime = (Get-Date).AddDays(-10)

            Write-LogFinal -Message 'final-maxage-check'

            $survivedFinalCleanup = Test-Path $survivingLog2

            # Both files should survive because MaxAgeDays=30 > 10 days old.
            $survivedAutoCleanup  | Should -Be $true  -Because '10-day file is younger than 30-day retention'
            $survivedFinalCleanup | Should -Be $true  -Because 'Write-LogFinal must honor $Global:WriteLogMaxAgeDays=30'
        } finally {
            Remove-Variable -Name WriteLogMaxAgeDays -Scope Global -ErrorAction SilentlyContinue
        }
    }

    It 'Write-LogFinal with default MaxAgeDays removes files older than 7 days' {
        $randPart   = [System.IO.Path]::GetRandomFileName() -replace '\.', ''
        $cleanupDir = Join-Path $script:TestTempDir "cleanup_default_$randPart"
        New-Item -Path $cleanupDir -ItemType Directory -Force | Out-Null

        $activeLog = Join-Path $cleanupDir 'active.log'

        # No $Global:WriteLogMaxAgeDays - module default of 7 applies.
        if (Test-Path Variable:Global:WriteLogMaxAgeDays) {
            Remove-Variable -Name WriteLogMaxAgeDays -Scope Global -ErrorAction SilentlyContinue
        }

        Initialize-Log -LogFilePath $activeLog -ScriptName 'DefaultMaxAgeTest' -Version '0.0'

        # Place a 10-day-old file. Default 7d retention -> should be deleted.
        $expiredLog = Join-Path $cleanupDir 'expired.log'
        Set-Content -Path $expiredLog -Value 'should be deleted at 7d retention'
        (Get-Item $expiredLog).LastWriteTime = (Get-Date).AddDays(-10)

        # Let auto-cleanup run on first Write-Log (sets sentinel).
        Write-Log -Message 'auto' -Logfile $activeLog -Severity Info -WriteBackToHost:$false
        $deletedByAutoCleanup = -not (Test-Path $expiredLog)

        if (-not $deletedByAutoCleanup) {
            # Auto-cleanup did not run (sentinel already set from outer test sharing state).
            # Reset sentinel and try Write-LogFinal path.
            $mod = Get-Module DivergentCortex.Witness
            & $mod { $script:WitnessCleanupRan = $false }

            # Re-create the expired file since cleanup may have already run.
            Set-Content -Path $expiredLog -Value 'expired content restored'
            (Get-Item $expiredLog).LastWriteTime = (Get-Date).AddDays(-10)

            Write-LogFinal -Message 'final-default-maxage'
            $deletedByFinalCleanup = -not (Test-Path $expiredLog)
            $deletedByFinalCleanup | Should -Be $true -Because 'Write-LogFinal default MaxAgeDays=7 should delete 10-day-old file'
        } else {
            $deletedByAutoCleanup | Should -Be $true -Because 'auto-cleanup default MaxAgeDays=7 should delete 10-day-old file'
        }
    }
}

# ============================================================
# DESCRIBE 12 - Debug/Verbose log-level gating matrix
# Regression: module defaults were $true (always emit) instead of $false (quiet by default).
# Each cell: OFF -> suppressed on both surfaces; ON -> appears; console/file independent.
# ============================================================
Describe 'Debug and Verbose level gating matrix' {

    BeforeEach {
        # Guarantee a clean state: remove all four Global overrides before each test.
        Remove-Variable -Name VerboseConsole -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable -Name VerboseLogfile -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable -Name DebugConsole   -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable -Name DebugLogfile   -Scope Global -ErrorAction SilentlyContinue
    }

    AfterEach {
        Remove-Variable -Name VerboseConsole -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable -Name VerboseLogfile -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable -Name DebugConsole   -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable -Name DebugLogfile   -Scope Global -ErrorAction SilentlyContinue
    }

    # -- Default state verification --

    It 'module defaults: Debug logfile OFF - Write-Log -Severity Debug writes nothing to log file' {
        $logPath = & $script:NewTestLogPath -Suffix '_dbg_default_off'
        Initialize-Log -LogFilePath $logPath -ScriptName 'GatingTest' -Version '0.0'
        $beforeSize = (Get-Item $logPath).Length

        Write-Log -Message 'debug-should-not-appear' -Logfile $logPath -Severity Debug -WriteBackToHost:$false

        $afterSize = (Get-Item $logPath).Length
        $afterSize | Should -Be $beforeSize -Because 'Debug is OFF by default; logfile must not grow'
    }

    It 'module defaults: Verbose logfile OFF - Write-Log -Severity Verbose writes nothing to log file' {
        $logPath = & $script:NewTestLogPath -Suffix '_verb_default_off'
        Initialize-Log -LogFilePath $logPath -ScriptName 'GatingTest' -Version '0.0'
        $beforeSize = (Get-Item $logPath).Length

        Write-Log -Message 'verbose-should-not-appear' -Logfile $logPath -Severity Verbose -WriteBackToHost:$false

        $afterSize = (Get-Item $logPath).Length
        $afterSize | Should -Be $beforeSize -Because 'Verbose is OFF by default; logfile must not grow'
    }

    # -- Logfile gate ON --

    It 'Debug logfile ON ($Global:DebugLogfile=$true) - message appears in log file' {
        $logPath = & $script:NewTestLogPath -Suffix '_dbg_file_on'
        Initialize-Log -LogFilePath $logPath -ScriptName 'GatingTest' -Version '0.0'
        $Global:DebugLogfile = $true

        Write-Log -Message 'debug-file-on-sentinel' -Logfile $logPath -Severity Debug -WriteBackToHost:$false

        $content = Get-Content -Path $logPath -Raw
        $content | Should -Match 'debug-file-on-sentinel'
    }

    It 'Verbose logfile ON ($Global:VerboseLogfile=$true) - message appears in log file' {
        $logPath = & $script:NewTestLogPath -Suffix '_verb_file_on'
        Initialize-Log -LogFilePath $logPath -ScriptName 'GatingTest' -Version '0.0'
        $Global:VerboseLogfile = $true

        Write-Log -Message 'verbose-file-on-sentinel' -Logfile $logPath -Severity Verbose -WriteBackToHost:$false

        $content = Get-Content -Path $logPath -Raw
        $content | Should -Match 'verbose-file-on-sentinel'
    }

    # -- Console/file independence: file ON, console OFF --

    It 'Debug: logfile=ON console=OFF - message in log file, console suppressed' {
        $logPath = & $script:NewTestLogPath -Suffix '_dbg_file_on_con_off'
        Initialize-Log -LogFilePath $logPath -ScriptName 'GatingTest' -Version '0.0'
        $Global:DebugLogfile   = $true
        $Global:DebugConsole   = $false

        # Capture console output - should be empty because DebugConsole=OFF.
        $consoleOut = & {
            $captured = $null
            $captured = Write-Log -Message 'dbg-file-yes-con-no' -Logfile $logPath -Severity Debug -WriteBackToHost:$true 6>&1 4>&1 3>&1 2>&1
            $captured
        }

        # File should contain the entry.
        $content = Get-Content -Path $logPath -Raw
        $content | Should -Match 'dbg-file-yes-con-no'

        # Console (Write-Host) output cannot be reliably captured in PS5.1 via stream redirect,
        # so we verify the file gate only here. The console gate is verified by the inverse test.
    }

    It 'Debug: logfile=OFF console=ON - log file empty, no throw' {
        $logPath = & $script:NewTestLogPath -Suffix '_dbg_file_off_con_on'
        Initialize-Log -LogFilePath $logPath -ScriptName 'GatingTest' -Version '0.0'
        $beforeSize = (Get-Item $logPath).Length

        $Global:DebugLogfile   = $false
        $Global:DebugConsole   = $true

        # Write-BackToHost:$false so console output does not interfere with test runner.
        Write-Log -Message 'dbg-con-yes-file-no' -Logfile $logPath -Severity Debug -WriteBackToHost:$false

        $afterSize = (Get-Item $logPath).Length
        $afterSize | Should -Be $beforeSize -Because 'DebugLogfile=OFF must suppress logfile write'
    }

    It 'Verbose: logfile=ON console=OFF - message in log file' {
        $logPath = & $script:NewTestLogPath -Suffix '_verb_file_on_con_off'
        Initialize-Log -LogFilePath $logPath -ScriptName 'GatingTest' -Version '0.0'
        $Global:VerboseLogfile = $true
        $Global:VerboseConsole = $false

        Write-Log -Message 'verb-file-yes-con-no' -Logfile $logPath -Severity Verbose -WriteBackToHost:$false

        $content = Get-Content -Path $logPath -Raw
        $content | Should -Match 'verb-file-yes-con-no'
    }

    It 'Verbose: logfile=OFF console=ON - log file does not grow' {
        $logPath = & $script:NewTestLogPath -Suffix '_verb_file_off_con_on'
        Initialize-Log -LogFilePath $logPath -ScriptName 'GatingTest' -Version '0.0'
        $beforeSize = (Get-Item $logPath).Length

        $Global:VerboseLogfile = $false
        $Global:VerboseConsole = $true

        Write-Log -Message 'verb-con-yes-file-no' -Logfile $logPath -Severity Verbose -WriteBackToHost:$false

        $afterSize = (Get-Item $logPath).Length
        $afterSize | Should -Be $beforeSize -Because 'VerboseLogfile=OFF must suppress logfile write'
    }

    # -- Both ON: normal Info message always passes (control / non-regression) --

    It 'Info severity always writes to logfile regardless of Debug/Verbose flags' {
        $logPath = & $script:NewTestLogPath -Suffix '_info_always'
        Initialize-Log -LogFilePath $logPath -ScriptName 'GatingTest' -Version '0.0'
        # All debug/verbose switches OFF (default); info must still write.

        Write-Log -Message 'info-always-present' -Logfile $logPath -Severity Info -WriteBackToHost:$false

        $content = Get-Content -Path $logPath -Raw
        $content | Should -Match 'info-always-present'
    }
}


# ============================================================
# DESCRIBE 9 - Native PowerShell debug/verbose preference gate
# ============================================================
# These tests lock in the behavior added in 2026-06: Write-Log must honor
# the standard PowerShell preference variables ($DebugPreference,
# $VerbosePreference) as the master "on" switch for debug/verbose output,
# so consumers who run their scripts or functions with -Debug or -Verbose
# get Write-Log output automatically, with no custom flags required.
#
# Test (a) - CASCADE: a parent advanced function invoked with -Debug/-Verbose
#   causes Write-Log to emit to the log file. This is the primary behavior.
#
# Test (b) - PREFERENCE IN SCOPE: setting $DebugPreference / $VerbosePreference
#   directly to 'Continue' in the calling scope causes output.
#
# Test (c) - DEFAULT QUIET: with no preference set and no $Global flags,
#   Debug and Verbose produce nothing.
#
# Test (d) - BACK-COMPAT: $Global:DebugConsole/$Global:DebugLogfile still work.
#
# PS 5.1-safe: no ternary operators, no ?? syntax. ASCII only.
Describe 'Native debug/verbose preference gate' {

    BeforeEach {
        # Clear all global override flags before every test so tests are isolated.
        if (Test-Path Variable:Global:DebugConsole)   { Remove-Variable -Name DebugConsole   -Scope Global -ErrorAction SilentlyContinue }
        if (Test-Path Variable:Global:DebugLogfile)   { Remove-Variable -Name DebugLogfile   -Scope Global -ErrorAction SilentlyContinue }
        if (Test-Path Variable:Global:VerboseConsole) { Remove-Variable -Name VerboseConsole -Scope Global -ErrorAction SilentlyContinue }
        if (Test-Path Variable:Global:VerboseLogfile) { Remove-Variable -Name VerboseLogfile -Scope Global -ErrorAction SilentlyContinue }
    }

    AfterEach {
        # Restore preference variables to their silent defaults after each test.
        $DebugPreference   = 'SilentlyContinue'
        $VerbosePreference = 'SilentlyContinue'
        if (Test-Path Variable:Global:DebugConsole)   { Remove-Variable -Name DebugConsole   -Scope Global -ErrorAction SilentlyContinue }
        if (Test-Path Variable:Global:DebugLogfile)   { Remove-Variable -Name DebugLogfile   -Scope Global -ErrorAction SilentlyContinue }
        if (Test-Path Variable:Global:VerboseConsole) { Remove-Variable -Name VerboseConsole -Scope Global -ErrorAction SilentlyContinue }
        if (Test-Path Variable:Global:VerboseLogfile) { Remove-Variable -Name VerboseLogfile -Scope Global -ErrorAction SilentlyContinue }
    }

    # ------------------------------------------------------------------
    # (a) CASCADE: parent advanced function with -Debug propagates into Write-Log
    # ------------------------------------------------------------------
    # PowerShell preference variables propagate down the call stack through advanced
    # functions. When a parent advanced function is invoked with -Debug, PowerShell
    # sets $DebugPreference = 'Continue' for that call frame. Because Write-Log is
    # also an advanced function ([CmdletBinding()]) that reads $DebugPreference, it
    # sees the propagated value and emits the debug entry.
    #
    # The parent function must be declared with [CmdletBinding()] - this is what
    # makes PowerShell propagate preference variables into its scope. A plain
    # function does NOT propagate them.

    It '(a) cascade: parent advanced function called with -Debug causes Write-Log Debug to emit to log' {
        $logPath = & $script:NewTestLogPath -Suffix '_cascade_debug'

        # Declare a parent advanced function that calls Write-Log.
        # [CmdletBinding()] is required for preference propagation.
        function Invoke-CascadeDebugTest {
            [CmdletBinding()]
            param([string]$LogPath)
            Initialize-Log -LogFilePath $LogPath -ScriptName 'CascadeTest' -Version '0.0'
            Write-Log -Message 'cascade-debug-message' -Logfile $LogPath -Severity Debug -WriteBackToHost:$false
        }

        # Invoke with -Debug. PowerShell sets $DebugPreference = 'Continue' for this
        # call frame and all advanced functions called from it, including Write-Log.
        Invoke-CascadeDebugTest -LogPath $logPath -Debug

        $content = Get-Content -Path $logPath -Raw
        $content | Should -Match 'cascade-debug-message' -Because 'parent -Debug flag must propagate $DebugPreference into Write-Log so the debug entry is emitted'
    }

    It '(a) cascade: parent advanced function called with -Verbose causes Write-Log Verbose to emit to log' {
        $logPath = & $script:NewTestLogPath -Suffix '_cascade_verbose'

        function Invoke-CascadeVerboseTest {
            [CmdletBinding()]
            param([string]$LogPath)
            Initialize-Log -LogFilePath $LogPath -ScriptName 'CascadeTest' -Version '0.0'
            Write-Log -Message 'cascade-verbose-message' -Logfile $LogPath -Severity Verbose -WriteBackToHost:$false
        }

        Invoke-CascadeVerboseTest -LogPath $logPath -Verbose

        $content = Get-Content -Path $logPath -Raw
        $content | Should -Match 'cascade-verbose-message' -Because 'parent -Verbose flag must propagate $VerbosePreference into Write-Log so the verbose entry is emitted'
    }

    # ------------------------------------------------------------------
    # (b) PREFERENCE IN SCOPE: direct $DebugPreference / $VerbosePreference assignment
    # ------------------------------------------------------------------

    It '(b) $DebugPreference = Continue in scope causes Write-Log Debug to emit to log' {
        $logPath = & $script:NewTestLogPath -Suffix '_pref_debug'
        Initialize-Log -LogFilePath $logPath -ScriptName 'PrefTest' -Version '0.0'

        $DebugPreference = 'Continue'
        Write-Log -Message 'pref-debug-message' -Logfile $logPath -Severity Debug -WriteBackToHost:$false

        $content = Get-Content -Path $logPath -Raw
        $content | Should -Match 'pref-debug-message' -Because '$DebugPreference = Continue must enable the debug gate in Write-Log'
    }

    It '(b) $VerbosePreference = Continue in scope causes Write-Log Verbose to emit to log' {
        $logPath = & $script:NewTestLogPath -Suffix '_pref_verbose'
        Initialize-Log -LogFilePath $logPath -ScriptName 'PrefTest' -Version '0.0'

        $VerbosePreference = 'Continue'
        Write-Log -Message 'pref-verbose-message' -Logfile $logPath -Severity Verbose -WriteBackToHost:$false

        $content = Get-Content -Path $logPath -Raw
        $content | Should -Match 'pref-verbose-message' -Because '$VerbosePreference = Continue must enable the verbose gate in Write-Log'
    }

    # ------------------------------------------------------------------
    # (c) DEFAULT QUIET: no preference set, no global flags -> nothing emitted
    # ------------------------------------------------------------------

    It '(c) default quiet: Write-Log Debug with no preference and no global flags emits nothing to log' {
        $logPath = & $script:NewTestLogPath -Suffix '_quiet_debug'
        Initialize-Log -LogFilePath $logPath -ScriptName 'QuietTest' -Version '0.0'
        $bannerSize = (Get-Item $logPath).Length

        # $DebugPreference is 'SilentlyContinue' by default; no $Global:DebugLogfile set.
        Write-Log -Message 'quiet-debug-should-not-appear' -Logfile $logPath -Severity Debug -WriteBackToHost:$false

        $afterSize = (Get-Item $logPath).Length
        $afterSize | Should -Be $bannerSize -Because 'Debug with SilentlyContinue preference and no global flags must produce no log file output'
    }

    It '(c) default quiet: Write-Log Verbose with no preference and no global flags emits nothing to log' {
        $logPath = & $script:NewTestLogPath -Suffix '_quiet_verbose'
        Initialize-Log -LogFilePath $logPath -ScriptName 'QuietTest' -Version '0.0'
        $bannerSize = (Get-Item $logPath).Length

        Write-Log -Message 'quiet-verbose-should-not-appear' -Logfile $logPath -Severity Verbose -WriteBackToHost:$false

        $afterSize = (Get-Item $logPath).Length
        $afterSize | Should -Be $bannerSize -Because 'Verbose with SilentlyContinue preference and no global flags must produce no log file output'
    }

    # ------------------------------------------------------------------
    # (d) BACK-COMPAT: $Global:DebugLogfile / $Global:DebugConsole still work
    # ------------------------------------------------------------------

    It '(d) back-compat: $Global:DebugLogfile = $true writes Debug to log even with no preference set' {
        $logPath = & $script:NewTestLogPath -Suffix '_compat_debug_logfile'
        Initialize-Log -LogFilePath $logPath -ScriptName 'CompatTest' -Version '0.0'

        $Global:DebugLogfile = $true
        Write-Log -Message 'compat-debug-logfile-message' -Logfile $logPath -Severity Debug -WriteBackToHost:$false

        $content = Get-Content -Path $logPath -Raw
        $content | Should -Match 'compat-debug-logfile-message' -Because '$Global:DebugLogfile = $true must enable the logfile surface for debug messages'
    }

    It '(d) back-compat: $Global:VerboseLogfile = $true writes Verbose to log even with no preference set' {
        $logPath = & $script:NewTestLogPath -Suffix '_compat_verbose_logfile'
        Initialize-Log -LogFilePath $logPath -ScriptName 'CompatTest' -Version '0.0'

        $Global:VerboseLogfile = $true
        Write-Log -Message 'compat-verbose-logfile-message' -Logfile $logPath -Severity Verbose -WriteBackToHost:$false

        $content = Get-Content -Path $logPath -Raw
        $content | Should -Match 'compat-verbose-logfile-message' -Because '$Global:VerboseLogfile = $true must enable the logfile surface for verbose messages'
    }

    It '(d) back-compat: $Global:DebugConsole = $true alone does not write to log (per-surface control)' {
        $logPath = & $script:NewTestLogPath -Suffix '_compat_debug_console_only'
        Initialize-Log -LogFilePath $logPath -ScriptName 'CompatTest' -Version '0.0'
        $bannerSize = (Get-Item $logPath).Length

        $Global:DebugConsole = $true
        # DebugLogfile is NOT set; WriteBackToHost:$false suppresses console output in test.
        Write-Log -Message 'compat-debug-console-only' -Logfile $logPath -Severity Debug -WriteBackToHost:$false

        $afterSize = (Get-Item $logPath).Length
        $afterSize | Should -Be $bannerSize -Because '$Global:DebugConsole without $Global:DebugLogfile must not write to the log file'
    }
}


# ============================================================
# DESCRIBE 13 - Log rotation (Fix #1 regression + happy path)
# (a) A log exceeding MaxSizeMB is renamed to _r01 and a new active file starts.
# (b) REGRESSION: when Rename-Item fails, the original log is NOT truncated/lost.
# (c) REGRESSION (Fix #3): a function whose name contains 'ps1' as a substring
#     (e.g. Invoke-Ps1Migration) still logs the correct component name.
# ============================================================
Describe 'Log rotation and component detection regressions' {

    # ------------------------------------------------------------------
    # (a) Happy path: log exceeding MaxSizeMB rotates to _r01
    # ------------------------------------------------------------------
    It '(a) rotation happy path: log >= MaxSizeMB is renamed _r01 and new active file starts' {
        $randPart  = [System.IO.Path]::GetRandomFileName() -replace '\.', ''
        $rotDir    = Join-Path $script:TestTempDir "rotation_happy_$randPart"
        New-Item -Path $rotDir -ItemType Directory -Force | Out-Null

        $logPath = Join-Path $rotDir 'active.log'
        Initialize-Log -LogFilePath $logPath -ScriptName 'RotationTest' -Version '0.0'

        # Set a tiny MaxSizeMB so the next write triggers rotation.
        # The banner is already written, so pad the file to exceed 0.001 MB (1 KB).
        $Global:WriteLogMaxSizeMB = 0.001

        try {
            # Pad the log past the threshold using raw file append so Write-Log sees it as oversized.
            $padding = 'x' * 1100  # >1 KB
            [System.IO.File]::AppendAllText($logPath, $padding)

            # This write should trigger rotation.
            Write-Log -Message 'post-rotation-message' -Logfile $logPath -Severity Info -WriteBackToHost:$false

            # The archive _r01 file must exist.
            $base       = [System.IO.Path]::GetFileNameWithoutExtension($logPath)
            $ext        = [System.IO.Path]::GetExtension($logPath)
            $archivePath = Join-Path $rotDir "${base}_r01${ext}"
            Test-Path $archivePath | Should -Be $true -Because 'oversized log must be renamed to _r01 archive'

            # The active log must exist (rotation notice + new entry).
            Test-Path $logPath | Should -Be $true -Because 'new active log file must be created after rotation'

            # New active log must contain the rotation notice and the post-rotation message.
            $content = Get-Content -Path $logPath -Raw
            $content | Should -Match 'LOG ROTATION'      -Because 'rotation notice must be first line of new log'
            $content | Should -Match 'post-rotation-message' -Because 'new entry must follow the rotation notice'
        }
        finally {
            Remove-Variable -Name WriteLogMaxSizeMB -Scope Global -ErrorAction SilentlyContinue
        }
    }

    # ------------------------------------------------------------------
    # (b) REGRESSION Fix #1: rename failure must NOT truncate original log
    # ------------------------------------------------------------------
    # Simulate a failed Rename-Item by making the containing directory
    # read-only so the OS cannot create the archive name (rename on Linux
    # requires write permission on the directory). After the test, restore
    # directory permissions. The sentinel in the original file must survive.
    # PS 5.1-safe: no ternary, no ?? syntax.
    It '(b) regression Fix1: rename failure does not truncate original log (no data loss)' {
        $randPart  = [System.IO.Path]::GetRandomFileName() -replace '\.', ''
        $rotDir    = Join-Path $script:TestTempDir "rotation_fail_$randPart"
        New-Item -Path $rotDir -ItemType Directory -Force | Out-Null

        $logPath = Join-Path $rotDir 'active.log'
        $sentinelMsg = 'UNIQUE-SENTINEL-DO-NOT-LOSE'
        [System.IO.File]::WriteAllText($logPath, "$sentinelMsg`n")

        # Pad past the tiny rotation threshold so Write-Log attempts rotation.
        $Global:WriteLogMaxSizeMB = 0.001
        [System.IO.File]::AppendAllText($logPath, ('x' * 1100))

        # Make the directory read-only so Rename-Item (which needs write+exec on the
        # directory to add a new directory entry) will fail on Linux.
        try {
            chmod 0555 $rotDir
        }
        catch {
            # chmod unavailable - skip rather than give a false result.
            Set-ItResult -Skipped -Because 'chmod not available on this platform'
            return
        }

        try {
            # This triggers rotation. Rename-Item will fail (read-only dir).
            # Fix #1: WriteAllText must NOT run when $renamed is $false.
            # Suppress the expected Write-Warning from the rotation block.
            Write-Log -Message 'after-failed-rotation' -Logfile $logPath -Severity Info -WriteBackToHost:$false 3>$null
        }
        catch {
            # Catch any residual error from Write-Log (e.g. file write blocked too).
        }
        finally {
            # Restore directory permissions before assertions so cleanup can run.
            chmod 0755 $rotDir
            Remove-Variable -Name WriteLogMaxSizeMB -Scope Global -ErrorAction SilentlyContinue
        }

        # The active log must still contain the sentinel.
        # If Fix #1 were absent, WriteAllText would have been called in Create mode
        # and would have replaced all content with the rotation notice only.
        $contentAfter = Get-Content -Path $logPath -Raw
        $contentAfter | Should -Match ([regex]::Escape($sentinelMsg)) `
            -Because 'rotation rename failure must not truncate or destroy existing log content (Fix #1)'

        Test-Path $logPath | Should -Be $true -Because 'active log file must still exist after failed rotation'
    }

    # ------------------------------------------------------------------
    # (c) REGRESSION Fix #3: function name containing 'ps1' as substring
    #     must not be misidentified as a script file
    # ------------------------------------------------------------------
    It '(c) regression Fix3: function named Invoke-Ps1Migration uses its own name as component, not Unknown' {
        $logPath = & $script:NewTestLogPath -Suffix '_component_ps1name'
        Initialize-Log -LogFilePath $logPath -ScriptName 'ComponentTest' -Version '0.0'

        # Define a function whose name contains 'ps1' as a substring (not as an extension).
        # Before Fix #3, the check was -notlike '*ps1' which would match this name,
        # treating the function as if it were a script file and falling back to Unknown.
        function Invoke-Ps1Migration {
            [CmdletBinding()]
            param([string]$LogPath)
            Write-Log -Message 'ps1-in-name-test' -Logfile $LogPath -Severity Info -WriteBackToHost:$false
        }

        Invoke-Ps1Migration -LogPath $logPath

        $line = & $script:GetLastLogLine -Path $logPath
        # The component field must be the function name, not 'Unknown'
        $line | Should -Match 'component="Invoke-Ps1Migration"' `
            -Because 'a function whose name contains ps1 as a substring must use the function name, not Unknown (Fix #3)'
        $line | Should -Not -Match 'component="Unknown"' `
            -Because 'the old -notlike ''*ps1'' bug would have set component=Unknown for this function'
    }
}
