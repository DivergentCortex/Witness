# Private/Clear-LogFile.ps1
# Renamed from donor's Cleanup-LogFiles. Identical behavior, approved PS verb (Clear).
# Called by Write-Log (auto-cleanup, once per session guard in module scope) and Write-LogFinal.
#
# Fix [9] (anti-slop): $ScriptFilter removed. It had zero callers in this module.

function Clear-LogFile {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [string]$LogFolder,

        [Parameter()]
        [int]$MaxAgeDays = 7
    )

    Write-Log "Starting log cleanup in: $LogFolder (keep last $MaxAgeDays days)" -Severity Debug

    $logFiles = Get-ChildItem -Path $LogFolder -Filter '*.log' -File -ErrorAction SilentlyContinue
    if (-not $logFiles) {
        Write-Log "No log files found in $LogFolder" -Severity Verbose
        return
    }

    $cutoff  = (Get-Date).AddDays(-$MaxAgeDays)
    $expired = $logFiles | Where-Object { $_.LastWriteTime -lt $cutoff }

    if (-not $expired -or @($expired).Count -eq 0) {
        Write-Log "No logs older than $MaxAgeDays days - nothing to delete" -Severity Verbose
        return
    }

    Write-Log "Deleting $(@($expired).Count) log(s) older than $MaxAgeDays days" -Severity Info
    foreach ($file in $expired) {
        try {
            Remove-Item -Path $file.FullName -Force -ErrorAction Stop
            Write-Log "Deleted: $($file.Name)" -Severity Verbose
        } catch {
            Write-Log "Failed to delete '$($file.Name)': $($_.Exception.Message)" -Severity Warning
        }
    }

    Write-Log "Log cleanup completed for: $LogFolder" -Severity Debug
}
