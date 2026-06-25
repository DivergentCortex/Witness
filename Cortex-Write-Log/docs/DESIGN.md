# DivergentCortex.Witness - Design Spec (DRAFT for review)

Status: Reviewed (3 reviewers: huginn, muninn, Codex) and built. Module ships as DivergentCortex.Witness v1.0.1.

## Goal

Rebuild the Windows-only, monolithic `Write-Log.ps1` (the "donor") into a proper,
public, cross-platform PowerShell module named `DivergentCortex.Witness`, supporting
Windows PowerShell 5.1 and PowerShell 7.4+ on Windows, Linux, and macOS.

Tagline: "There is always a Witness."

## Hard constraints

1. The donor `Cortex-Write-Log/donor-code/Write-Log.ps1` is NEVER edited. It is the
   read-only behavioral spec. It is "the best PowerShell Write-Log ever" per the owner;
   4 years of hardening. We re-implement from it, we do not mutate it.
2. Public function names are unchanged: `Write-Log`, `Initialize-Log`, `Write-LogFinal`.
   Existing consumer scripts must keep working with zero changes. The module ID is
   branded (`DivergentCortex.Witness`) but the cmdlets stay plain.
3. CMTrace line format and severity/color behavior must match the donor exactly on Windows.

## Donor architecture (from recon)

- Public: `Write-Log` (core CMTrace logger), `Initialize-Log` (run-header),
  `Write-LogFinal` (final entry + cleanup trigger).
- Private: `Cleanup-LogFiles` (age-based cleanup; rename to `Clear-LogFile`),
  `Get-ExecutionContextInfo` (identity/admin/host - Windows-specific, needs rewrite).
- Portable as-is: `Get-PSCallStack` caller/component detection, `[System.IO.*]`
  file streaming, `[TimeZoneInfo]` UTC offset.

## Verified cross-platform research

See docs/CROSS-PLATFORM.md for full per-mechanism detail with sources. Outcome: all 7
Windows-specific mechanisms have verified Linux equivalents; 0 rejected.

- current_user: guard `[WindowsIdentity]::GetCurrent().Name` with `$IsWindows`; Linux uses
  `[System.Environment]::UserName`. (Donor lines 258/351/399 throw PlatformNotSupportedException on Linux as-is.)
- elevation: Windows -> WindowsPrincipal; PS7.4+ -> `[Environment]::IsPrivilegedProcess`;
  PS7.2/7.3 -> `id -u` fallback.
- hostname: `[Environment]::MachineName` cross-platform.
- domain_user: Linux has no AD domain semantics; `[Environment]::UserDomainName` returns hostname. Surface honestly.
- interactive_user / session_type / service_context: corrected idioms per research (loginctl/XDG/SSH; systemd INVOCATION_ID/JOURNAL_STREAM; no controlling TTY).

## Proposed module layout

```
DivergentCortex.Witness/            (rename of Cortex-Write-Log module folder)
  DivergentCortex.Witness.psd1      manifest; exports the 3 functions; tags Windows/Linux/MacOS; PSEdition Core+Desktop
  DivergentCortex.Witness.psm1      loader; dot-source Private then Public
  Public/
    Write-Log.ps1
    Initialize-Log.ps1
    Write-LogFinal.ps1
  Private/
    Clear-LogFile.ps1               renamed from Cleanup-LogFiles
    Get-ExecutionContextInfo.ps1    rewritten cross-platform (consumes the adapter)
    Get-PlatformContext.ps1         NEW - the platform adapter
  tests/                            Pester (Windows + Linux paths)
  docs/                             CROSS-PLATFORM.md, ARCHITECTURE.md, DESIGN.md
```

## The platform adapter: Get-PlatformContext

Single private function returning a normalized object:
`{ Platform, UserName, UserDomainName, IsElevated, HostName, InteractiveUser, SessionType, IsService }`.

- Each field implemented per the verified research, with `$IsWindows` (or a 5.1-safe
  platform probe) branching INSIDE the adapter only.
- Public functions (`Write-Log` etc.) call the adapter and never branch on OS inline.
  This kills the donor's duplicated inline WindowsIdentity calls (3 sites) and centralizes
  all OS logic in one testable place.
- SCCM/CMSite drive detection + `Set-Location C:` stays, but `$IsWindows`-guarded;
  no Linux equivalent (out of scope by owner decision).

## Compatibility matrix

- Windows PowerShell 5.1 (Windows) - preserves donor's SCCM/5.1 heritage.
- PowerShell 7.4+ on Windows / Linux / macOS.
- 5.1 has no `$IsWindows` automatic variable; the adapter defines a safe platform probe
  (treat absence of `$IsWindows` as Windows).
- Elevation API version gate handled in adapter (IsPrivilegedProcess on 7.4+, id -u below).

## Parity policy (evidence-backed)

Native best-effort for every field. Nothing dropped that has a real equivalent (research
proved they all do). Documented honest gaps only: Linux "domain" = hostname (no AD);
SCCM is Windows-only.

## Deliverables (definition of done)

- Module code (manifest, loader, 3 public + 3 private functions).
- Pester tests covering Windows and Linux adapter paths.
- docs/CROSS-PLATFORM.md (done), docs/ARCHITECTURE.md, refreshed README with tagline + cross-platform install.
- Green huginn + muninn review pass on the implementation.
- Actual cross-platform test run (Windows + Linux) before "done".

## Proposed build team

- powershell-module-architect: structure, manifest, loader, adapter shape.
- powershell-7-expert: Get-PlatformContext + Write-Log port (cross-platform).
- powershell-5-expert: 5.1 compatibility verification.
- quality-engineer: Pester tests.
- documentation-engineer: ARCHITECTURE.md + README.
File ownership partitioned so no two teammates edit the same file.

## Open questions for review

- Is the single-adapter shape right, or should identity vs session vs service be separate private helpers?
- Folder rename Cortex-Write-Log -> DivergentCortex.Witness: any downside?
- Any risk to exact CMTrace parity from the username-source change on Windows (WindowsIdentity retained on Windows, so should be none)?
- 5.1 platform-probe approach: safest pattern?
