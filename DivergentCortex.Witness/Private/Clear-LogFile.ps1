function Clear-LogFile {
    <#
    .SYNOPSIS
        Removes log files older than a specified age from a folder.

    .DESCRIPTION
        Scans the target folder for *.log files whose LastWriteTime is older than
        MaxAgeDays and deletes them. Called automatically by Write-Log (once per
        session) and by Write-LogFinal. Both callers share a cleanup sentinel so
        this never runs twice in a single session.

    .PARAMETER LogFolder
        Path to the folder containing log files to evaluate.

    .PARAMETER MaxAgeDays
        Number of days to retain logs. Files older than this are deleted. Default: 7.

    .EXAMPLE
        Clear-LogFile -LogFolder "C:\Logs" -MaxAgeDays 14

    .NOTES
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
        -  Created on:    4/23/2023 2:15 PM                               -
        =  Author:        Curtis Leggett                                  =
        -  Copyright:     2026 Synapse Co.                                -
        =  Organization:  Divergent Cortex                                =
        -  Version:       2026.03.24.010                                  -
        =-=-                       =-=-=-=-=-=-=-=                     -=-=
        -       The witness is a ghost,                                   -
        =                      yet, somewhere,                            =
        -                             a file is remembering you.          -
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
    #>
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
