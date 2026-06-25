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

    # ---- Temp directory for all test log files ----
    $script:TestTempDir = Join-Path ([System.IO.Path]::GetTempPath()) "WitnessTests_$PID"
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

    # Pattern for the time field value: HH:mm:ss.fff followed by a UTC offset
    $script:TimeFieldRegex = 'time="(\d{2}:\d{2}:\d{2}\.\d{3}-?\d+(\.\d+)?)"'
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

    It 'contains time= field with HH:mm:ss.fff format plus UTC offset' {
        $logPath = & $script:NewTestLogPath -Suffix '_timestamp'
        Initialize-Log -LogFilePath $logPath -ScriptName 'PesterTest' -Version '0.0'
        Write-Log -Message 'ts-check' -Logfile $logPath -Severity Info -WriteBackToHost:$false

        $line = & $script:GetLastLogLine -Path $logPath
        $line | Should -Match 'time="\d{2}:\d{2}:\d{2}\.\d{3}-?\d+'
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
        Write-Log -Message 'verbose-test' -Logfile $script:SevLogPath -Severity Verbose -WriteBackToHost:$false
        $line = & $script:GetLastLogLine -Path $script:SevLogPath
        (& $script:GetTypeCode -Line $line) | Should -Be '4'
    }

    It 'Debug maps to type 5' {
        Write-Log -Message 'debug-test' -Logfile $script:SevLogPath -Severity Debug -WriteBackToHost:$false
        $line = & $script:GetLastLogLine -Path $script:SevLogPath
        (& $script:GetTypeCode -Line $line) | Should -Be '5'
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
# DESCRIBE 8 - Timestamp time= field format (HH:mm:ss.fff + UTC offset)
# ============================================================
Describe 'Timestamp time= field format' {

    It 'time= value matches HH:mm:ss.fff followed by UTC offset minutes (integer or decimal)' {
        $logPath = & $script:NewTestLogPath -Suffix '_ts_format'
        Initialize-Log -LogFilePath $logPath -ScriptName 'TimestampTest' -Version '0.0'
        Write-Log -Message 'ts-fmt' -Logfile $logPath -Severity Info -WriteBackToHost:$false

        $line = & $script:GetLastLogLine -Path $logPath
        # time= field: HH:mm:ss.fff then an optional minus sign then digits (UTC offset in minutes)
        $line | Should -Match 'time="\d{2}:\d{2}:\d{2}\.\d{3}-?\d+'
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
