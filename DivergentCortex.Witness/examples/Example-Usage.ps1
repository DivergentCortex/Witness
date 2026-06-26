#Requires -Version 7.0
<#
.SYNOPSIS
    Demonstrates DivergentCortex.Witness logging across all severities with deliberate
    error capture that surfaces the auto-detected function name, script, and line number.

.DESCRIPTION
    Copy-paste template for correct Write-Log usage. Run it to see:
      - The session-start banner written by Initialize-Log
      - Color-coded console output for every severity (Info, Warning, Error, Success,
        Verbose, Debug)
      - A deliberate throw inside a try/catch, with the resulting ERROR entry showing
        the component (function name) and file:line where the failure occurred
      - Write-LogFinal closing the session

    The log file lands in examples/logs/ relative to this script.

.NOTES
    This is a public demo script. All names, paths, and operations are fictional.
    No real system interaction occurs.

    Module: DivergentCortex.Witness
    Version: 1.0.0
#>

[CmdletBinding()]
param()

# ---------------------------------------------------------------------------
# Helper load order: param block -> module import -> operational code
# ---------------------------------------------------------------------------
$ModuleManifest = Join-Path $PSScriptRoot '..' 'DivergentCortex.Witness.psd1'
Import-Module $ModuleManifest -Force -ErrorAction Stop

$LogDir     = Join-Path $PSScriptRoot 'logs'
$LogFile    = Join-Path $LogDir "Example-Usage_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

Initialize-Log -LogFilePath $LogFile -ScriptName 'Example-Usage' -Version '1.0.0'

# ---------------------------------------------------------------------------
# Demo functions - each exercises one or more severity levels
# ---------------------------------------------------------------------------

function Get-WidgetInventory {
    <#
    .SYNOPSIS
        Simulates reading a widget inventory from a fictional data source.
    #>
    [CmdletBinding()]
    param(
        [string]$WarehouseId = 'WH-01'
    )

    Write-Log -Message "Reading widget inventory for warehouse '$WarehouseId'." -Severity Info

    $inventory = @(
        [PSCustomObject]@{ SKU = 'WGT-100'; Qty = 42; Status = 'OK' }
        [PSCustomObject]@{ SKU = 'WGT-200'; Qty = 0;  Status = 'OutOfStock' }
        [PSCustomObject]@{ SKU = 'WGT-300'; Qty = 7;  Status = 'LowStock' }
    )

    foreach ($item in $inventory) {
        if ($item.Status -eq 'OutOfStock') {
            Write-Log -Message "SKU $($item.SKU) is out of stock in '$WarehouseId'." -Severity Warning
        }
        elseif ($item.Status -eq 'LowStock') {
            Write-Log -Message "SKU $($item.SKU) is low (Qty: $($item.Qty))." -Severity Verbose
        }
        else {
            Write-Log -Message "SKU $($item.SKU) OK (Qty: $($item.Qty))." -Severity Debug
        }
    }

    Write-Log -Message "Inventory read complete. $($inventory.Count) SKUs returned." -Severity Success
    return $inventory
}

function Invoke-WidgetReorder {
    <#
    .SYNOPSIS
        Simulates placing a reorder for out-of-stock widgets via a fictional API.
        Deliberately throws to demonstrate error capture with function name and line number.
    #>
    [CmdletBinding()]
    param(
        [string]$SKU,
        [int]$Quantity
    )

    Write-Log -Message "Placing reorder: SKU=$SKU  Qty=$Quantity." -Severity Info

    try {
        # This throw is intentional - it demonstrates the headline feature.
        # The ERROR entry in the log will show this function name (Invoke-WidgetReorder)
        # and the exact line number where the throw occurs.
        if ($SKU -eq 'WGT-200') {
            throw "Reorder API rejected SKU '$SKU': item discontinued."
        }

        Write-Log -Message "Reorder accepted for SKU=$SKU." -Severity Success
    }
    catch {
        Write-Log -Message "Reorder failed for SKU=$SKU. Detail: $($_.Exception.Message)" -Severity Error
    }
}

function Test-WarehouseConnectivity {
    <#
    .SYNOPSIS
        Simulates a connectivity probe against a fictional warehouse endpoint.
    #>
    [CmdletBinding()]
    param(
        [string]$Endpoint = 'warehouse-api.example.internal'
    )

    Write-Log -Message "Probing warehouse endpoint '$Endpoint'." -Severity Info

    # Simulate a latency check - no real network call.
    $simulatedLatencyMs = 38
    if ($simulatedLatencyMs -gt 100) {
        Write-Log -Message "Endpoint '$Endpoint' latency high: ${simulatedLatencyMs}ms." -Severity Warning
    }
    else {
        Write-Log -Message "Endpoint '$Endpoint' reachable. Latency: ${simulatedLatencyMs}ms." -Severity Info
    }
}

# ---------------------------------------------------------------------------
# Main orchestration
# ---------------------------------------------------------------------------

Write-Log -Message 'Example-Usage starting.' -Severity Info

# Step 1: connectivity check
Test-WarehouseConnectivity -Endpoint 'warehouse-api.example.internal'

# Step 2: read inventory - exercises Info, Warning, Verbose, Debug, Success
$Global:VerboseLogfile  = $true
$Global:VerboseConsole  = $true
$Global:DebugLogfile    = $true
$Global:DebugConsole    = $true

$inventory = Get-WidgetInventory -WarehouseId 'WH-01'

# Step 3: reorder out-of-stock items - exercises Error (deliberate throw)
$outOfStock = $inventory | Where-Object { $_.Status -eq 'OutOfStock' }
foreach ($item in $outOfStock) {
    Invoke-WidgetReorder -SKU $item.SKU -Quantity 50
}

Write-Log -Message 'Example-Usage finished.' -Severity Info

# Write-LogFinal closes the session and runs log cleanup.
Write-LogFinal -Message 'Session complete. Log cleanup scheduled.' -Severity Success
