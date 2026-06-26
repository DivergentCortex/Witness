function Clear-LogFile {
    <#
    .SYNOPSIS
        Removes log files older than a specified age from a folder.

    .DESCRIPTION
        Scans the target folder for *.log files whose LastWriteTime predates the
        MaxAgeDays cutoff and deletes them. Called automatically by Write-Log (once
        per session, gated by the cleanup sentinel) and by Write-LogFinal. The shared
        sentinel ensures this never runs twice in one session.

    .PARAMETER LogFolder
        Path to the folder containing log files to evaluate.

    .PARAMETER MaxAgeDays
        Retention window in days. Files older than this threshold are deleted.
        Default: 7.

    .OUTPUTS
        None.

    .EXAMPLE
        Clear-LogFile -LogFolder 'C:\Logs' -MaxAgeDays 14

        Delete all *.log files in C:\Logs older than 14 days.

    .NOTES
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
        -  Created on:    04/23/2023                                      -
        =  Author:        Curtis Leggett                                  =
        -  Copyright:     2026 Divergent Cortex                           -
        =  Organization:  Divergent Cortex                                =
        -  Version:       1.0.1                                           -
        =-=-                       =-=-=-=-=-=-=-=                     -=-=
        -       The witness is a ghost,                                   -
        =                      yet, somewhere,                            =
        -                             a file is remembering you.          -
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$LogFolder,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 365)]
        [int]$MaxAgeDays = 7
    )

    Write-Log "Starting log cleanup in: $LogFolder (keep last $MaxAgeDays days)" -Severity Debug

    $logFiles = Get-ChildItem -Path $LogFolder -Filter '*.log' -File -ErrorAction SilentlyContinue
    if (-not $logFiles) {
        Write-Log "No log files found in $LogFolder" -Severity Verbose
        return
    }

    $cutoff = (Get-Date).AddDays(-$MaxAgeDays)
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
        }
        catch {
            Write-Log "Failed to delete '$($file.Name)': $($_.Exception.Message)" -Severity Warning
        }
    }

    Write-Log "Log cleanup completed for: $LogFolder" -Severity Debug
}
