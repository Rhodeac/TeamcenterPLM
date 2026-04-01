# ============================================================
# PLM-Common.ps1
# Dot-source this file at the top of every PLM script:
#   . "$PSScriptRoot\PLM-Common.ps1"
# Created by:  Andrew C. Rhodes
# ============================================================

# ── Paths ────────────────────────────────────────────────────
$PLM_HOME_ROOT = Resolve-Path (Join-Path $PSScriptRoot "..\")
$LOG_FILE      = Join-Path $PLM_HOME_ROOT "log.txt"
$CONFIG_FILE   = Join-Path $PLM_HOME_ROOT "config.env"

# ── Self-elevate if not Administrator ────────────────────────
function Assert-Admin {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Start-Process powershell "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.ScriptName)`"" -Verb RunAs
        exit
    }
}

# ── Load config.env into process environment ─────────────────
function Import-PLMConfig {
    if (-not (Test-Path $CONFIG_FILE)) {
        Write-PLMError "Config file not found: $CONFIG_FILE"
        exit 1
    }
    Get-Content $CONFIG_FILE | ForEach-Object {
        if ($_ -match '^\s*([^#][^=]*?)\s*=\s*(.*)\s*$') {
            [System.Environment]::SetEnvironmentVariable($Matches[1].Trim(), $Matches[2].Trim(), 'Process')
        }
    }
}

# ── Cleanup log on exit ───────────────────────────────────────
function Remove-PLMLog {
    if (Test-Path $LOG_FILE) { Remove-Item -Force $LOG_FILE }
}

# ── Color helpers ─────────────────────────────────────────────
function Write-PLMError   { param([string]$msg) Write-Host $msg -ForegroundColor Red }
function Write-PLMInfo    { param([string]$msg) Write-Host $msg -ForegroundColor Cyan }
function Write-PLMSuccess { param([string]$msg) Write-Host $msg -ForegroundColor Green }
function Write-PLMHeader  {
    param([string]$msg)
    Write-Host ""
    Write-Host " $msg " -ForegroundColor White -BackgroundColor DarkGray
    Write-Host ""
}
