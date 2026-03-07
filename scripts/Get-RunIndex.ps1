#Requires -Version 5.1
<#
.SYNOPSIS
    Inspect and manage run history. Equivalent of orchestrate's run-index.sh.
.DESCRIPTION
    Reads .orchestrate\index\runs.jsonl and provides:
    - list: recent runs with status
    - show: details of a specific run
    - report: print the report of a run
    - stats: session statistics

.PARAMETER Command
    list | show | report | stats | files

.PARAMETER Ref
    Run reference: @latest, @last-failed, @last-completed, or run ID prefix.

.PARAMETER Session
    Filter by session ID.

.PARAMETER Failed
    Only show failed runs.

.PARAMETER N
    Number of runs to show. Default: 20.
#>
[CmdletBinding()]
param(
    [Parameter(Position=0)] [ValidateSet('list','show','report','stats','files','logs')]
    [string]$Command = 'list',
    [Parameter(Position=1)] [string]$Ref = "",
    [Parameter()] [string]$Session = "",
    [Parameter()] [switch]$Failed,
    [Parameter()] [int]$N = 20
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path $PSScriptRoot -Parent
$indexFile   = Join-Path $projectRoot ".orchestrate\index\runs.jsonl"

if (-not (Test-Path $indexFile)) {
    Write-Host "  No runs yet. Run-Agent.ps1 to create runs." -ForegroundColor Yellow
    exit 0
}

# ── Parse JSONL into run objects ────────────────────────────────────────────
$rows = Get-Content $indexFile -Encoding UTF8 | Where-Object { $_.Trim() } | ForEach-Object {
    try { $_ | ConvertFrom-Json } catch { $null }
} | Where-Object { $_ -ne $null }

# Group start + finalize rows by run_id
$runMap = @{}
foreach ($row in $rows) {
    $id = $row.run_id
    if (-not $runMap.ContainsKey($id)) { $runMap[$id] = @{} }
    if ($row.status -eq 'running') {
        $runMap[$id]['start'] = $row
    } else {
        $runMap[$id]['fin'] = $row
    }
}

# Build unified run records
$runs = $runMap.GetEnumerator() | ForEach-Object {
    $start = $_.Value['start']
    $fin   = $_.Value['fin']
    $base  = if ($start) { $start } else { $fin }
    [PSCustomObject]@{
        run_id     = $base.run_id
        status     = if ($fin) { $fin.status } else { 'running' }
        model      = $base.model
        harness    = $base.harness
        role       = $base.role
        yolo       = $base.yolo
        session_id = $base.session_id
        created_at = $base.created_at_utc
        duration   = if ($fin) { $fin.duration_seconds } else { $null }
        exit_code  = if ($fin) { $fin.exit_code } else { $null }
        log_dir    = $base.log_dir
        report     = if ($fin) { $fin.report_path } else { '' }
    }
} | Sort-Object created_at -Descending

# Apply filters
if ($Failed) { $runs = $runs | Where-Object { $_.status -eq 'failed' } }
if ($Session) { $runs = $runs | Where-Object { $_.session_id -eq $Session } }

# ── Resolve ref ─────────────────────────────────────────────────────────────
function Resolve-RunRef([string]$ref) {
    switch ($ref) {
        '@latest'         { return $runs | Select-Object -First 1 }
        '@last-failed'    { return $runs | Where-Object { $_.status -eq 'failed'    } | Select-Object -First 1 }
        '@last-completed' { return $runs | Where-Object { $_.status -eq 'completed' } | Select-Object -First 1 }
        default {
            $exact = $runs | Where-Object { $_.run_id -eq $ref } | Select-Object -First 1
            if ($exact) { return $exact }
            return $runs | Where-Object { $_.run_id.StartsWith($ref) } | Select-Object -First 1
        }
    }
}

# ════════════════════════════════════════════════════════════════
# COMMANDS
# ════════════════════════════════════════════════════════════════

switch ($Command) {

    'list' {
        Write-Host ""
        Write-Host "  ── RUN HISTORY ─────────────────────────────────────────────────" -ForegroundColor Cyan
        Write-Host ("  {0,-26} {1,-10} {2,-14} {3,-12} {4}" -f "RUN ID", "STATUS", "MODEL", "DURATION", "SESSION") -ForegroundColor DarkGray
        Write-Host ("  {0,-26} {1,-10} {2,-14} {3,-12} {4}" -f "------", "------", "-----", "--------", "-------") -ForegroundColor DarkGray

        $runs | Select-Object -First $N | ForEach-Object {
            $color = switch ($_.status) {
                'completed' { 'Green'  }
                'failed'    { 'Red'    }
                'running'   { 'Yellow' }
                default     { 'White'  }
            }
            $dur = if ($_.duration) { "${($_.duration)}s" } else { '...' }
            $modelShort = if ($_.model.Length -gt 14) { $_.model.Substring(0,13) + '…' } else { $_.model }
            $runShort   = $_.run_id.Substring(0, [Math]::Min(26, $_.run_id.Length))
            $sesShort   = if ($_.session_id -and $_.session_id -ne $_.run_id) { $_.session_id.Substring(0,[Math]::Min(20,$_.session_id.Length)) } else { '' }
            $yoloMark   = if ($_.yolo) { '⚡' } else { '' }
            Write-Host ("  {0,-26} {1,-10} {2,-14} {3,-12} {4}" -f $runShort, ($_.status + $yoloMark), $modelShort, $dur, $sesShort) -ForegroundColor $color
        }
        Write-Host ""
        Write-Host "  Commands: show @latest | report @latest | stats | show <run-id-prefix>" -ForegroundColor DarkGray
        Write-Host ""
    }

    'show' {
        $run = if ($Ref) { Resolve-RunRef $Ref } else { $runs | Select-Object -First 1 }
        if (-not $run) { Write-Host "Run not found: $Ref" -ForegroundColor Red; exit 1 }

        Write-Host ""
        Write-Host "  ── RUN: $($run.run_id) ──" -ForegroundColor Cyan
        Write-Host "  Status:   $($run.status)" -ForegroundColor $(if ($run.status -eq 'completed') { 'Green' } else { 'Red' })
        Write-Host "  Model:    $($run.model)  ($($run.harness))"
        Write-Host "  Role:     $(if ($run.role) { $run.role } else { '(none)' })"
        Write-Host "  YOLO:     $($run.yolo)" -ForegroundColor $(if ($run.yolo) { 'Red' } else { 'White' })
        Write-Host "  Session:  $($run.session_id)"
        Write-Host "  Created:  $($run.created_at)"
        Write-Host "  Duration: $(if ($run.duration) { "$($run.duration)s" } else { 'N/A' })"
        Write-Host "  Log dir:  $($run.log_dir)"

        if ($run.log_dir -and (Test-Path $run.log_dir)) {
            $files = Get-ChildItem $run.log_dir | ForEach-Object { "    $($_.Name) ($($_.Length) bytes)" }
            Write-Host "  Files:"
            $files | ForEach-Object { Write-Host $_ -ForegroundColor DarkGray }
        }
        Write-Host ""
    }

    'report' {
        $run = if ($Ref) { Resolve-RunRef $Ref } else { $runs | Select-Object -First 1 }
        if (-not $run) { Write-Host "Run not found: $Ref" -ForegroundColor Red; exit 1 }

        if ($run.report -and (Test-Path $run.report)) {
            Write-Host "  ── REPORT: $($run.run_id) ──" -ForegroundColor Cyan
            Get-Content $run.report -Encoding UTF8 | ForEach-Object { Write-Host "  $_" }
        } elseif ($run.log_dir) {
            $rp = Join-Path $run.log_dir "report.md"
            if (Test-Path $rp) {
                Get-Content $rp -Encoding UTF8 | ForEach-Object { Write-Host "  $_" }
            } else {
                Write-Host "  No report found for run $($run.run_id)" -ForegroundColor Yellow
            }
        }
    }

    'stats' {
        $filtered = if ($Session) { $runs | Where-Object { $_.session_id -eq $Session } } else { $runs }
        $completed = ($filtered | Where-Object { $_.status -eq 'completed' }).Count
        $failed    = ($filtered | Where-Object { $_.status -eq 'failed'    }).Count
        $running   = ($filtered | Where-Object { $_.status -eq 'running'   }).Count
        $totalDur  = ($filtered | Where-Object { $_.duration } | Measure-Object -Property duration -Sum).Sum

        Write-Host ""
        Write-Host "  ── STATS $(if ($Session) { "Session: $Session" } else { "(all runs)" }) ──" -ForegroundColor Cyan
        Write-Host "  Total:     $($filtered.Count)"
        Write-Host "  Completed: $completed" -ForegroundColor Green
        Write-Host "  Failed:    $failed"    -ForegroundColor $(if ($failed -gt 0) { 'Red' } else { 'White' })
        Write-Host "  Running:   $running"   -ForegroundColor $(if ($running -gt 0) { 'Yellow' } else { 'White' })
        if ($totalDur) { Write-Host "  Total time: ${totalDur}s" }
        Write-Host ""
    }

    'logs' {
        $run = if ($Ref) { Resolve-RunRef $Ref } else { $runs | Select-Object -First 1 }
        if (-not $run) { Write-Host "Run not found" -ForegroundColor Red; exit 1 }
        $outFile = Join-Path $run.log_dir "output.txt"
        if (Test-Path $outFile) {
            Get-Content $outFile -Encoding UTF8 | Select-Object -Last 50 | ForEach-Object { Write-Host $_ }
        } else {
            Write-Host "No output log for $($run.run_id)" -ForegroundColor Yellow
        }
    }

    'files' {
        $run = if ($Ref) { Resolve-RunRef $Ref } else { $runs | Select-Object -First 1 }
        if (-not $run) { Write-Host "Run not found" -ForegroundColor Red; exit 1 }
        $ft = Join-Path $run.log_dir "files-touched.txt"
        if (Test-Path $ft) {
            Write-Host "  Files touched by $($run.run_id):" -ForegroundColor Cyan
            Get-Content $ft | ForEach-Object { Write-Host "  $_" }
        } else {
            Write-Host "  No files-touched record for $($run.run_id)" -ForegroundColor Yellow
        }
    }
}
