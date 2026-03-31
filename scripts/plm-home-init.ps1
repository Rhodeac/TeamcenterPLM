# ============================================================
# plm-home-init.ps1
# Initializes the PLM_Home environment:
#   1. Injects siteDir into the microservice gateway config
#   2. Creates a 7z backup of the AWS src directory
# ============================================================

. "$PSScriptRoot\PLM-Common.ps1"

Assert-Admin
Import-PLMConfig

# ── Resolve paths from env ────────────────────────────────────
$backupFile        = Join-Path $env:FULL_BACKUP_LOC "aws_src_backup.7z"
$gatewayConfigFile = Join-Path $env:TC_ROOT "microservices\gateway\config.json"
$tempFile          = "$gatewayConfigFile.tmp"
$siteDir           = (Join-Path $env:TC_ROOT "aws2\stage\out\site") -replace '\\', '/'

$zipExe  = "C:\Apps\7-Zip\7z.exe"
$addArgs = "-t7z -mx9 -mmt4 -stl -ssp -scrc=SHA256 -pinfodba -mhe=on"

# ── 1. Patch siteDir into gateway config.json ────────────────
Write-PLMHeader "Updating microservice siteDir value"

if (-not (Test-Path $gatewayConfigFile)) {
    Write-PLMError "Gateway config not found: $gatewayConfigFile"
    exit 1
}

$content = Get-Content $gatewayConfigFile -Raw
if ($content -match '"siteDir"') {
    Write-PLMInfo "siteDir already exists. Skipping update."
    Write-Host ""
} else {
    Write-Host "siteDir not found. Proceeding to update..."

    # Insert siteDir as the first key after the opening brace
    $updated = $content -replace '^\s*\{', "{`n    `"siteDir`": `"$siteDir`","
    $updated | Set-Content -Path $tempFile -Encoding UTF8
    Move-Item -Force -Path $tempFile -Destination $gatewayConfigFile

    Write-PLMSuccess "Added `"siteDir`" to $gatewayConfigFile"
    Write-Host ""
}

# ── 2. Backup the AWS src directory ──────────────────────────
Write-PLMHeader "Backing up AWS src directory"

if (-not (Test-Path $backupFile)) {
    Write-Host "Backing up `"$($env:AWS_SRC_DIR)`" to `"$backupFile`" ..."

    if (-not (Test-Path $zipExe)) {
        Write-PLMError "7-Zip not found at: $zipExe"
        exit 1
    }

    & $zipExe a $backupFile $env:AWS_SRC_DIR $addArgs.Split(' ')
    if ($LASTEXITCODE -ne 0) { Write-PLMError "7-Zip backup failed (exit $LASTEXITCODE)"; exit $LASTEXITCODE }

    Write-PLMSuccess "Backup complete."
} else {
    Write-PLMInfo "Backup already exists at `"$backupFile`". Skipping."
}

Remove-PLMLog
Write-PLMSuccess "plm-home-init completed successfully."
