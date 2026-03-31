# ============================================================
# aw-start-dev.ps1
# Initializes the Active Workspace development environment
# and starts the dev server.
# ============================================================

. "$PSScriptRoot\PLM-Common.ps1"

Assert-Admin
Import-PLMConfig

$awsBuildDir = Split-Path $env:AWS_SRC_DIR -Parent
Set-Location $awsBuildDir

# ── initenv ───────────────────────────────────────────────────
Write-PLMHeader "Initializing Environment: .\initenv.cmd"
& cmd.exe /c "call initenv.cmd"
if ($LASTEXITCODE -ne 0) { Write-PLMError "initenv failed (exit $LASTEXITCODE)"; exit $LASTEXITCODE }

# ── npm run clean ─────────────────────────────────────────────
Write-PLMHeader "(~5 min) npm run clean"
& cmd.exe /c "npm run clean"
if ($LASTEXITCODE -ne 0) { Write-PLMError "npm run clean failed (exit $LASTEXITCODE)"; exit $LASTEXITCODE }

# ── npm run audit ─────────────────────────────────────────────
Write-PLMHeader "(~5 min) npm run audit"
& cmd.exe /c "npm run audit"
if ($LASTEXITCODE -ne 0) { Write-PLMError "npm run audit failed (exit $LASTEXITCODE)"; exit $LASTEXITCODE }

# ── npm run start ─────────────────────────────────────────────
Write-PLMHeader "(~15 min) Starting Active Workspace Dev Environment"
$env:PORT             = "3001"
$env:ENDPOINT_GATEWAY = "http://localhost:$($env:PORT)"
& cmd.exe /c "npm run start"

Remove-PLMLog
