# Changelog

## [2026.06.25.025] - 2026-06-25
### docs: Finalize .NOTES signature with staircase tagline across all functions

What changed:
- Synced final operator-authored .NOTES signature block to all 6 function files: wide =-=- border, fields (Created on, Author, Copyright, Organization, Version), broken divider, and cascading tagline: 'The witness is a ghost, / yet, somewhere, / a file is remembering you.'

Why:
- Operator-authored signature with cascading philosophical tagline reflecting the Witness module identity. Final version after iterative refinement in this session.


## [2026.06.25.024] - 2026-06-25
### docs: Final .NOTES signature block with =-=- border and tagline

What changed:
- Replaced .NOTES signature in all 6 function files with operator-authored block: =-=- border, Created on / Author / Copyright / Organization / Version fields, tagline ('Divergent Tools are built to survive in hostile environments')

Why:
- Operator-authored signature reflecting the style and personality they wanted. Previous iterations were too minimal -- this matches the visual weight and character of the original donor signature while adding Divergent Cortex branding.


## [2026.06.25.023] - 2026-06-25
### docs: Update .NOTES signature to match donor co-author line

What changed:
- Replaced 'Curt & Claude // Divergent Cortex' one-liner with proper framed signature block matching donor lineage: Curtis Leggett & S.Henry / Divergent Cortex, in all 6 function files

Why:
- Signature should reflect the actual co-author credit from the donor (Curtis Leggett & S.Henry) and the org (Divergent Cortex). S.Henry is Claude's pen name in the donor. No rot-prone fields (filename, version, date).


## [2026.06.25.022] - 2026-06-25
### docs: Add .NOTES signature block to all function CBH

What changed:
- Added .NOTES block with 'Curt & Claude // Divergent Cortex' to CBH in all 6 function files: Clear-LogFile.ps1, Resolve-WitnessLogPath.ps1, Get-PlatformContext.ps1, Write-Log.ps1, Initialize-Log.ps1, Write-LogFinal.ps1
- Removed old donor .NOTES box from Clear-LogFile.ps1 (contained rot-prone fields: Created on, Filename, Version)

Why:
- Operator preference: signature should reflect the human-AI collaboration (Curt & Claude) with the org. No filename, version, or date fields - those are git's job and rot in source.


## [2026.06.25.021] - 2026-06-25
### fix(DivergentCortex.Witness): Debug/Verbose log-level gating defaults corrected from ON to OFF; gating regression tests added

What changed:
- DivergentCortex.Witness.psm1: flipped all four verbose/debug module-scope defaults from $true to $false ($script:WitnessVerboseConsole, $script:WitnessVerboseLogfile, $script:WitnessDebugConsole, $script:WitnessDebugLogfile)
- tests/DivergentCortex.Witness.Tests.ps1 Describe 3: 'Verbose maps to type 4' and 'Debug maps to type 5' now set $Global:VerboseLogfile/$Global:DebugLogfile=$true in try/finally before writing, then restore; gate was correct but suppressed the write with proper defaults making the type-code assertions fail
- tests/DivergentCortex.Witness.Tests.ps1: added Describe 12 'Debug and Verbose level gating matrix' with 9 new It blocks covering defaults-are-off (both surfaces), logfile-ON appears, console/logfile independence (logfile-ON/console-OFF and logfile-OFF/console-ON), and Info-always-passes control; test count grows from 57 to 66

Why:
- Dogfood run showed Debug and Verbose lines appearing in logs. The gating logic in Write-Log.ps1 was structurally correct (checks $script:WitnessDebugLogfile etc., has early return when both surfaces disabled, has per-surface $shouldWriteConsole/$shouldWriteLogfile checks), but the psm1 module-scope defaults were all $true so the gate never suppressed anything. Operator requirement is default-quiet: debug and verbose must be off unless the operator explicitly enables them. The $Global: back-compat override surface (VerboseConsole, VerboseLogfile, DebugConsole, DebugLogfile) is preserved and tested. No logic changes to Write-Log.ps1 itself.


## [2026.06.25.020] - 2026-06-25
### chore: Remove redundant file-header comment blocks from all function files

What changed:
- Removed top-of-file comment headers (filename, description, Fix [N] reference lists) from all 6 function files: Clear-LogFile.ps1, Resolve-WitnessLogPath.ps1, Get-PlatformContext.ps1, Write-Log.ps1, Initialize-Log.ps1, Write-LogFinal.ps1
- Each file now starts directly with function keyword — all documentation lives in the CBH block inside the function body
- Inline comments within function bodies (explaining WHY specific code patterns exist) are preserved

Why:
- File-header blocks duplicated information already captured in CBH (added in 2026.06.25.019) and the changelog. Fix reference lists are changelog/git-history concerns, not source-file concerns. Removing them reduces noise and eliminates a maintenance surface that drifts from reality.


## [2026.06.25.019] - 2026-06-25
### docs: Add comment-based help to private functions

What changed:
- Added <# .SYNOPSIS / .DESCRIPTION / .PARAMETER / .EXAMPLE #> blocks to Clear-LogFile (Private/Clear-LogFile.ps1), Resolve-WitnessLogPath (Private/Resolve-WitnessLogPath.ps1), and Get-PlatformContext (Private/Get-PlatformContext.ps1)
- Replaced inline parameter comment in Resolve-WitnessLogPath with a proper .PARAMETER block
- Public functions (Write-Log, Initialize-Log, Write-LogFinal) already had CBH; no changes needed

Why:
- Operator preference: help documentation should live inside the function body so Get-Help works and the help is co-located with the code. No logic changes.


## [2026.06.25.018] - 2026-06-25
### feat(Write-Log): Local time only in CMTrace time= field; test logs move to repo-local logs/ dir

What changed:
- Changed Write-Log.ps1 time= field from HH:mm:ss.fff+UTC_offset to plain HH:mm:ss.fff local time: removed UtcOffset computation ([TimeZoneInfo]::Local.GetUtcOffset().TotalMinutes), set LogTime = DateTime.ToString('HH:mm:ss.fff'). Applies to main log line, rotation notice, and contention/retry notice (all three reuse the same LogTime variable)
- Updated DivergentCortex.Witness/tests/DivergentCortex.Witness.Tests.ps1: changed TestTempDir from [System.IO.Path]::GetTempPath() to repo-local logs/ folder resolved via $PSScriptRoot (gitignored); updated $script:TimeFieldRegex to match HH:mm:ss.fff with no offset; updated It descriptions and match patterns in Describe 2 and Describe 8 to assert no offset suffix
- Updated DivergentCortex.Witness/docs/ARCHITECTURE.md: CMTrace format example updated to show HH:mm:ss.fff without offset; time= field description updated to state local time only with explicit note that this is a deliberate donor divergence per operator preference
- Updated README.md Quick Start example: replaced two-line Join-Path+Initialize-Log pattern with single-line Initialize-Log -LogFilePath "$PSScriptRoot/logs/MyScript.log" form, showing logs/ folder beside the script

Why:
- Operator directive: plain local time is always readable without timezone arithmetic. UTC offset suffix removed as deliberate divergence from donor behavior. Test logs moved off OS temp dir per operator directive (logs go to logs/ folder, not OS temp). Pester 57/57 green after changes.


## Background

DivergentCortex.Witness is the public, cross-platform rebuild of a Windows-only
Write-Log script originally written in April 2023 (donor version 2026.03.24.010)
and hardened over three years of real SCCM deployments, scheduled tasks, and remote
automation before this public release. The donor is preserved read-only at
DivergentCortex.Witness/donor-code/Write-Log.ps1 and was never modified; the module
re-implements its behavior with cross-platform support and a proper module structure
added on top.

## [2026.06.25.017] - 2026-06-25
### docs(repo): Add Background section documenting real lineage of DivergentCortex.Witness

What changed:
- Added Background section at top of CHANGELOG.md citing donor origin date April 2023 (version 2026.03.24.010) and three years of private SCCM deployment hardening before public release
- Added one-sentence lineage note to README.md describing the script's origin as a battle-tested Windows logger rebuilt cross-platform

Why:
- Coordinator directive: add honest background/heritage note anchored to real donor header data (Created on 4/23/2023, Version 2026.03.24.010) - no fabricated dates or history


## [2026.06.25.016] - 2026-06-25
### chore(repo): Public release prep: exclusions, test portability, CI workflow, security docs, history replacement

What changed:
- Added Cortex-Write-Log/donor-code/ to .gitignore to exclude donor from public tree without modifying it (donor line 58 contains employer reference that must not ship)
- Added *.7z to .gitignore
- Deleted WriteLog_old.7z binary archive artifact from working tree
- Fixed Cortex-Write-Log/tests/DivergentCortex.Witness.Tests.ps1 line 21: replaced hardcoded absolute manifest path with Join-Path $PSScriptRoot '..' 'DivergentCortex.Witness.psd1'
- Scrubbed CHANGELOG.md of machine hostname, personal account reference, and PAT wiring details; technical module history preserved
- Updated Cortex-Write-Log/docs/DESIGN.md status line from DRAFT to reviewed-and-built (3 reviewers: huginn, muninn, Codex)
- Added .github/workflows/test.yml: Pester CI on ubuntu-latest (pwsh), windows-latest (pwsh + PS 5.1 via shell:powershell), macos-latest (pwsh)
- Added SECURITY.md: GitHub private vulnerability reporting instructions
- Added CONTRIBUTING.md: fork/PR workflow, test requirements, code standards
- Replaced all git history with single orphan commit on main; deleted master branch locally and remotely; GitHub default branch set to main

Why:
- Public release gate. The repo contained machine-specific paths, a personal GitHub account reference, and infrastructure details that must not ship. The hardcoded test path made CI impossible. History replacement removes all internal tooling artifacts from the public record.


## [2026.06.25.015] - 2026-06-25
### chore(repo): Gitignore .claude/ and untrack 25 internal agent state files from git index

What changed:
- Added .claude/ entry to .gitignore (appended after .vscode/ line, no duplicate created)
- Ran git rm -r --cached .claude to remove 25 files from the git index without deleting them from disk
- Committed the untracking as: chore: gitignore .claude internal agent state (exclude from public repo)
- Files removed from index span agent-memory (8 files), ai_forge hooks (8 files), ai_forge dashboard (4 files), and ai_forge state/archives (5 files)

Why:
- The .claude/ directory (internal agent tooling, ai_forge runtime state, and agent-memory with private notes) was previously committed and must not ship in the public repo. Gitignoring from the start prevents any future commit from re-adding these files.


## [2026.06.25.014] - 2026-06-25
### docs(ARCHITECTURE): Create ARCHITECTURE.md for DivergentCortex.Witness module

What changed:
- Created Cortex-Write-Log/docs/ARCHITECTURE.md covering module layout, loader behavior, and PS 5.1 platform probe
- Documented Get-PlatformContext adapter: field-by-field table showing Windows vs Linux/macOS behavior, called once in Initialize-Log, result held in local var only (not module scope)
- Documented per-write context= resolution: WindowsIdentity on Windows (impersonation-correct), Environment API on non-Windows
- Documented log path resolution order: explicit param, caller scope via PSCmdlet.SessionState, module scope, global scope
- Documented cleanup sentinel lifecycle: initialized false at load, set true on first cleanup trigger, reset by Initialize-Log, invariant that Write-LogFinal sets it on all return paths
- Documented CMTrace line format with field breakdown: time (HH:mm:ss.fff+UTC offset in minutes), date (MM-dd-yyyy), component, context, type, thread, file
- Documented severity-to-CMTrace-type mapping: Info/Information/Success=1, Warning=2, Error=3, Verbose=4, Debug=5
- Documented size-based rotation, SCCM drive handling, donor-as-read-only-spec relationship, and PS 5.1 syntax constraints

Why:
- Public release requires architecture documentation explaining module internals, the platform adapter design, and the design decisions behind the current structure. This was a missing mandatory doc.


## [2026.06.25.013] - 2026-06-25
### docs(README): Rewrite README for public release as DivergentCortex.Witness

What changed:
- Replaced pre-module Write-Log README with full DivergentCortex.Witness public-facing documentation
- Added platform support matrix (PS 5.1 Windows, PS 7.4+ Windows/Linux/macOS)
- Added complete Write-Log parameter table with types, defaults, and descriptions
- Added log path resolution chain documentation (explicit param, caller scope, module scope, global)
- Added configuration table for all global override variables with defaults
- Added honest cross-platform notes section covering LogonType, UserDomainName, SCCM, elevation, interactive user, and session type gaps
- Added install instructions (clone + import; PSGallery noted as planned but not live)
- Added quick start showing Initialize-Log, Write-Log at multiple severities, Write-LogFinal
- Added severity-to-CMTrace-type mapping table and console color reference
- Added How it works section explaining Get-PlatformContext adapter and per-write context resolution
- Linked to docs/ARCHITECTURE.md and docs/CROSS-PLATFORM.md for deep-dive references

Why:
- Old README predated the module rebuild and described the monolithic donor script. Public release requires accurate documentation of the current module surface, cross-platform behavior, and install path.


## [2026.06.25.012] - 2026-06-25
### fix(DivergentCortex.Witness): Apply Muninn final-pass fixes: config-aware retention, rotation visibility, sentinel invariant, dead state removal

What changed:
- Fix R1 (config-aware retention): Write-LogFinal now resolves MaxAgeDays via module-scope/global-override chain (same as Write-Log) and passes -MaxAgeDays to Clear-LogFile; previously passed no arg, silently using the hard-coded default 7 days regardless of consumer configuration
- Fix R2 (rotation write visible): empty catch {} on [System.IO.File]::WriteAllText replaced with catch that calls Write-Warning; disk-full or permission errors on the rotation notice are now surfaced to the warning stream rather than silently swallowed
- Fix R3 (sentinel invariant): Write-LogFinal sets $script:WitnessCleanupRan = $true on all early-return paths (no-path and folder-not-found) so no subsequent call can trigger cleanup after any of those exits
- Fix R4 (dead state removed): $script:WitnessContext removed from DivergentCortex.Witness.psm1 and Initialize-Log; Get-PlatformContext result now held in a local $ctx variable only; it was dead state - assigned in Initialize-Log but never read after the function returned since Write-Log resolves context= cheaply per write
- Fix R5 (doc notes): header comments in Write-Log.ps1, Write-LogFinal.ps1, and Initialize-Log.ps1 now document that caller-scope $LogFilePath resolution works for same-session-state callers and cannot cross a foreign-module boundary; under Import-Module the canonical path is Initialize-Log -LogFilePath or $Global:LogFilePath; also documents that calling Initialize-Log a second time resets the one-time cleanup guard
- New Pester Describe 11: two tests covering config-aware retention - one verifies $Global:WriteLogMaxAgeDays=30 causes a 10-day-old file to SURVIVE both Write-Log auto-cleanup and Write-LogFinal cleanup paths; the other verifies default 7-day retention deletes a 10-day-old file; module scope is manipulated via the module scriptblock to reset the sentinel between sub-tests

Why:
- Muninn found four real defects after Huginn PASS and Codex PASS on the previous round. Fix R1 is a genuine behavior bug (different retention policies on the two cleanup paths). Fix R4 removes a dead module-scope variable that was flagged by both ravens. Fixes R2 and R3 close silent-failure and sentinel-invariant gaps.


## [2026.06.25.011] - 2026-06-25
### test(DivergentCortex.Witness): Add Pester v5 test suite - 55 tests, all passing, covering public contract and 11 review-fix regressions

What changed:
- Created Cortex-Write-Log/tests/DivergentCortex.Witness.Tests.ps1 (55 tests, 11 Describe blocks, all pass on pwsh 7 / Pester 5.7.1 on Linux)
- Describe 1: module imports from .psd1 without error; exports exactly Write-Log, Initialize-Log, Write-LogFinal; Clear-LogFile/Get-PlatformContext/Resolve-WitnessLogPath NOT exported; zero cmdlets/variables/aliases
- Describe 2: CMTrace line shape - full regex, field order locked (time/date/component/context/type/thread/file), time=HH:mm:ss.fff+offset, date=MM-dd-yyyy
- Describe 3: Severity->type code mapping regression - Info/Information/Success=1, Warning=2, Error=3, Verbose=4, Debug=5
- Describe 4: ValidateSet regression - Write-Log and Write-LogFinal accept Success and Information; invalid severity rejected (ParameterBindingException)
- Describe 5: Caller-scope $LogFilePath resolution - Initialize-Log reads caller scope when no -LogFilePath given; explicit param overrides; no-path-anywhere throws
- Describe 6: Single-cleanup sentinel regression - cleanup runs once per session; re-calling Initialize-Log resets sentinel so new session can clean
- Describe 7: Line-ending consistency - no mixed CRLF/LF; Linux produces LF-only
- Describe 8: Timestamp format - HH:mm:ss.fff+offset, date=MM-dd-yyyy, milliseconds exactly 3 digits
- Describe 9: Write-Log/Initialize-Log/Write-LogFinal behavioral contracts (mandatory params, file creation, banner, pipeline input, repeated writes)
- Describe 10: Global:LogFilePath fallback back-compat
- PS 5.1-syntax-safe (no ternary, no ??, no ??=); ASCII only; helpers as $script: scriptblocks in BeforeAll to satisfy Pester v5 scoping; test files in OS temp under WitnessTests_$PID, cleaned in AfterAll

Why:
- No test suite existed for DivergentCortex.Witness. Tests lock in the 11 code-review fixes so regressions surface immediately rather than silently shipping. The suite was requested as part of the quality gate for v1.0.1.


## [2026.06.25.010] - 2026-06-25
### docs(CROSS-PLATFORM.md): Fix Section 5 Tier-3 idiom to match implementation - use [Environment]::UserName not $env:USER

What changed:
- Section 5 Tier-3 code snippet changed from '$env:USER or id -un' to '[System.Environment]::UserName'
- Added inline comment explaining why [Environment]::UserName is preferred: it calls getpwuid_r() via the .NET PAL and cannot be unset or spoofed, unlike $env:USER which can be absent in non-login shells, containers, and service contexts

Why:
- The implementation in Get-PlatformContext already used [Environment]::UserName correctly per Fix [9] in the first build pass. The doc still showed the old $env:USER idiom, creating a mismatch that would confuse future maintainers reading the research doc against the code.


## [2026.06.25.009] - 2026-06-25
### fix(DivergentCortex.Witness): Apply consolidated review fixes from Huginn, Codex, and Muninn - all 11 items

What changed:
- Fix 1 (double-cleanup): Write-LogFinal now checks $script:WitnessCleanupRan before calling Clear-LogFile and sets the sentinel after; cleanup never runs twice in a session regardless of whether Write-Log auto-cleanup or Write-LogFinal fires first
- Fix 2 (sentinel lifecycle): Initialize-Log resets $script:WitnessCleanupRan = $false so a second Initialize-Log call (new log tree) triggers auto-cleanup again; guard is per-session not per-module-import
- Fix 3 (caller-scope path compat): new Private/Resolve-WitnessLogPath.ps1 helper encapsulates path resolution (module-scope and global layers); Write-Log and Initialize-Log both use $PSCmdlet.SessionState.PSVariable.GetValue('LogFilePath') to read caller-scope $LogFilePath before falling through to Resolve-WitnessLogPath; restores dot-source-era 'just set $LogFilePath' pattern under Import-Module
- Fix 4 (context= per write): removed ContextUser from cached Get-PlatformContext result; Write-Log now resolves context= per write: [WindowsIdentity]::GetCurrent().Name on Windows (impersonation-correct, donor-parity), [Environment]::UserDomainName\UserName on non-Windows; no loginctl or heavy adapter per line
- Fix 5 (line endings): rotation notice write changed from hardcoded `r`n to [System.Environment]::NewLine; StreamWriter.NewLine also set to [System.Environment]::NewLine; file is now consistent (CRLF on Windows, LF on Linux)
- Fix 6 (Write-LogFinal ValidateSet): added 'Success' and 'Information' to match Write-Log's accepted set; -Severity Success no longer throws a parameter binding exception
- Fix 7 (macOS detection): Get-PlatformContext Platform field now returns 'Windows'/'macOS'/'Linux'; $IsMacOS guarded with Test-Path Variable:IsMacOS for PS 5.1 safety
- Fix 8 (manifest ProjectUri): corrected to https://github.com/DivergentCortex/Witness; added LicenseUri; bumped ModuleVersion to 1.0.1
- Fix 9 (dead $ScriptFilter): removed from Clear-LogFile; it had zero callers anywhere in the module
- Fix 10 (double GetCurrent): Get-PlatformContext elevation block reuses $identity from the identity block above; no second [WindowsIdentity]::GetCurrent() call on Windows
- Private/Resolve-WitnessLogPath.ps1 created: two real callers (Write-Log and Write-LogFinal) justify the helper; resolution order is CallerResolved -> $script:WitnessLogFilePath -> $Global:LogFilePath
- DivergentCortex.Witness.psm1 updated: sources Resolve-WitnessLogPath.ps1 after Clear-LogFile.ps1 in Private load block

Why:
- Three independent reviewers (Huginn, Codex, Muninn) rejected the module. All 11 issues are now addressed in one pass before re-running the smoke test.


## [2026.06.25.008] - 2026-06-25
### feat(DivergentCortex.Witness): Complete module scaffold: Write-LogFinal, psm1 loader, psd1 manifest, stub removal, smoke test green

What changed:
- Created Public/Write-LogFinal.ps1: fixes donor bug (undefined $LogFile at line ~510) by resolving path from $script:WitnessLogFilePath then $Global:LogFilePath; calls Clear-LogFile not the old Cleanup-LogFiles name
- Created DivergentCortex.Witness.psm1: thin loader; sets $script:WitnessIsWindows once with 5.1-safe probe (absence of $IsWindows treated as Windows); initializes all module-scope state ($WitnessLogFilePath, $WitnessContext, $WitnessCleanupRan) and config defaults; dot-sources Private then Public in correct load order
- Created DivergentCortex.Witness.psd1: manifest with explicit FunctionsToExport listing exactly Write-Log/Initialize-Log/Write-LogFinal; CmdletsToExport/VariablesToExport/AliasesToExport all empty arrays; CompatiblePSEditions Desktop+Core; PowerShellVersion 5.1
- Deleted WriteLog.psm1 and WriteLog.psd1 stub files that were previously at the module root
- Smoke test on Linux/pwsh confirmed: Import-Module via .psd1 path succeeds; exactly 3 functions exported; Initialize-Log/Write-Log/Write-LogFinal all produce valid CMTrace lines; context= field shows expected platform values; type codes correct (Info=1, Warning=2, Verbose=4, Debug=5); exit code 0

Why:
- Completing the DivergentCortex.Witness module build. All 13 mandatory fixes from review are implemented and verified working on Linux/pwsh 7.


## [2026.06.25.007] - 2026-06-25
### feat(DivergentCortex.Witness): Build DivergentCortex.Witness PowerShell module from Write-Log donor script

What changed:
- Created Cortex-Write-Log/Public/ and Cortex-Write-Log/Private/ directories for module layout
- Created Private/Get-PlatformContext.ps1: cross-platform identity and context adapter; replaces Windows-only Get-ExecutionContextInfo; guards all [WindowsIdentity]::GetCurrent().Name calls with $script:WitnessIsWindows; elevation uses WindowsPrincipal on Windows and [Environment]::IsPrivilegedProcess with id -u fallback on non-Windows; interactive-user uses [Environment]::UserName not $env:USER; honest degradation for Linux (LogonType=N/A, UserDomainName=hostname)
- Created Private/Clear-LogFile.ps1: renamed from donor Cleanup-LogFiles; identical behavior; approved PS verb
- Created Public/Write-Log.ps1: CMTrace logger with identical API to donor; path resolved from $script:WitnessLogFilePath then $Global:LogFilePath back-compat; all three [WindowsIdentity]::GetCurrent().Name inline sites replaced with cached $script:WitnessContext.ContextUser; rotation notice and contention notice also use cached context; cleanup guard moved to $script:WitnessCleanupRan module scope; all Global config vars honored for back-compat; no PS7-only syntax; SCCM drive guard wrapped in $script:WitnessIsWindows check
- Created Public/Initialize-Log.ps1: stores -LogFilePath to $script:WitnessLogFilePath; calls Get-PlatformContext once and caches to $script:WitnessContext; no longer calls Get-ExecutionContextInfo; no longer uses Get-Variable that breaks under Import-Module

Why:
- Rebuilding the Windows-only monolithic Write-Log donor script into a proper cross-platform module (DivergentCortex.Witness) supporting PS 5.1 and PS 7.4+ on Windows/Linux/macOS. All 13 mandatory fixes from Huginn/Muninn/Codex review being implemented.


## [2026.06.25.006] - 2026-06-25
### chore(repo): Create private DivergentCortex/Witness GitHub repo and finish github MCP token wiring

What changed:
- Created private repo DivergentCortex/Witness on GitHub (home for the cross-platform module)
- GitHub MCP server configured with appropriate authentication for DivergentCortex org access
- Used a classic PAT scoped to repo and workflow permissions to enable GitHub API operations for the DivergentCortex organization

Why:
- The repo is the public home for the module and had to exist before build/push; the github MCP server was previously never fully configured (no token delivery mechanism), which blocked all API-driven GitHub work.


## [2026.06.25.005] - 2026-06-25
### docs(design): Draft DivergentCortex.Witness design spec and route for Codex + raven second-opinion review

What changed:
- Wrote docs/DESIGN.md draft: layout, Get-PlatformContext adapter, compatibility matrix (PS5.1 + 7.4+), parity policy, build team, open questions
- Dispatched parallel design review: huginn (inventor), muninn (skeptic), and Codex second opinion
- Build is gated on surviving review per operator standing rule (all plans get a second opinion)

Why:
- The operator requires every plan to get a second opinion from Codex and the raven pair before execution; this records the design artifact and the review gate before any build team is spawned.


## [2026.06.25.004] - 2026-06-25
### docs(cross-platform): Create CROSS-PLATFORM.md preserving verified research for Windows-to-Linux identity mechanisms

What changed:
- Created Cortex-Write-Log/docs/CROSS-PLATFORM.md with per-mechanism sections for all 7 researched Windows APIs: process identity, elevation, hostname, domain user, interactive user, session type, service context
- Each section documents: what the donor does, the Windows API used (with donor line numbers), the verified Linux/PS7 idiom in a code block, the verifier verdict, caveats and edge cases, and all source URLs from the research
- Added summary table mapping each mechanism to its Linux equivalent status, one-liner idiom, and verdict
- Added Known Platform Gaps section covering: no AD domain semantics on Linux, SCCM out of scope, elevation API version gate (.NET 8/PS 7.4+) with id -u fallback, broken UserInteractive on Linux
- Added Critical Donor Finding callout: [WindowsIdentity]::GetCurrent().Name at donor lines 258/351/399 throws PlatformNotSupportedException on Linux

Why:
- Preserves the verified cross-platform research as a permanent reference artifact so the platform-adapter implementation is grounded in evidence, source URLs survive beyond the research session, and future contributors understand why specific idioms were chosen over alternatives.


## [2026.06.25.003] - 2026-06-25
### docs(research): Complete verified PS7-on-Linux equivalents research for all Windows-specific mechanisms

What changed:
- Researched and adversarially verified Linux equivalents for 7 Windows-specific mechanisms; 0 rejected (all portable)
- Confirmed as-is: elevation, hostname, domain-user, service-context
- Corrected by PS7 expert: current-user (use [Environment]::UserName, guard WindowsIdentity), interactive-user, session-type
- Identified critical donor defect for cross-platform: [WindowsIdentity]::GetCurrent().Name at donor lines 258/351/399 throws PlatformNotSupportedException on Linux
- Flagged version gate: [Environment]::IsPrivilegedProcess needs .NET8/PS7.4+, requires fallback (id -u) on PS7.2/7.3
- Noted Linux [Environment]::UserDomainName returns machine hostname, not AD domain

Why:
- Captures the verified cross-platform research with sources so the platform-adapter implementation is grounded in evidence and the findings persist beyond the session rather than being lost.


## [2026.06.25.002] - 2026-06-25
### chore(planning): Establish design direction for cross-platform DivergentCortex.Witness module rebuild

What changed:
- Mapped donor Write-Log.ps1 architecture: 5 functions (public: Write-Log, Initialize-Log, Write-LogFinal; private: Clear-LogFile, Get-ExecutionContextInfo); donor stays read-only and untouched
- Decided module name DivergentCortex.Witness (PSGallery-verified free; DivergentCortex namespace reserved as house brand); exported functions keep plain names Write-Log/Initialize-Log/Write-LogFinal
- Decided platform-adapter architecture: a private layer abstracts OS-specific identity/admin/host/session so public functions never branch on $IsWindows inline
- Scoped SCCM/CMSite handling as Windows-only ($IsWindows-guarded), no Linux equivalent pursued per operator
- Launched verified research into PowerShell-7-on-Linux equivalents for 7 Windows-specific mechanisms (identity, elevation, hostname, domain user, interactive user, session type, service context)

Why:
- Records the design decisions and constraints for the public cross-platform rebuild before implementation, so future work understands why the module is named DivergentCortex.Witness, why the donor is untouched, and why the platform-adapter pattern was chosen.


## [2026.06.25.001] - 2026-06-25
### feat(WriteLog): First public packaged release of the WriteLog PowerShell module

What changed:
- Split the original single-file logger into per-function files under Public/ and Private/
- Added module manifest (WriteLog.psd1) and loader (WriteLog.psm1) exporting Write-Log, Initialize-Log, Write-LogFinal
- Renamed internal cleanup helper Cleanup-LogFiles to Clear-LogFile (approved verb)
- Scrubbed employer-specific references from the source for public release
- Added README, MIT LICENSE, and .gitignore

Why:
- Packaging a logger maintained and hardened since 2023 as a standalone, shareable module for public release on GitHub.


All notable changes to this project are documented here.
