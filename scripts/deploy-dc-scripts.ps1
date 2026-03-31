# ============================================================
# deploy-dc-scripts.ps1
# Extracts the latest Deployment Center zip and runs deploy.bat
# ============================================================

. "$PSScriptRoot\PLM-Common.ps1"

Assert-Admin
Import-PLMConfig

# ── Resolve paths from env ────────────────────────────────────
$base = $env:DEPLOY_ENV_FOLDER
$dest = $env:TEMP_BUILD_FOLDER

if ([string]::IsNullOrEmpty($base) -or -not (Test-Path $base)) {
    Write-PLMError "Unable to find DC directory at: $base"
    exit 1
}

# ── Find the most-recently-modified subfolder ─────────────────
$firstFolder = Get-ChildItem -Path $base -Directory |
               Sort-Object Name -Descending |
               Select-Object -First 1

if (-not $firstFolder) {
    Write-PLMError "No folders found in: $base"
    exit 1
}

# ── Find the zip inside that folder ──────────────────────────
$zipFile = Get-ChildItem -Path $firstFolder.FullName -Filter "*.zip" |
           Select-Object -First 1

if (-not $zipFile) {
    Write-PLMError "No zip file found in: $($firstFolder.Name)"
    exit 1
}

# ── Parse folder name as a timestamp (yyyyMMddHHmmss) ─────────
try {
    $ts            = [datetime]::ParseExact($firstFolder.Name.Substring(0, 14), 'yyyyMMddHHmmss', $null)
    $formattedTime = $ts.ToString("hh:mm tt")
} catch {
    $formattedTime = $firstFolder.Name
}

Write-Host ""
Write-PLMInfo "Newest zip file: $formattedTime"

# ── Ensure destination folder exists ─────────────────────────
if (-not (Test-Path $dest)) {
    New-Item -ItemType Directory -Path $dest | Out-Null
}

# ── Optionally skip re-extraction ────────────────────────────
$deployBat = Join-Path $dest "deploy.bat"
$doExtract = $true

if (Test-Path $deployBat) {
    Write-Host ""
    Write-Host "deploy.bat already exists in `"$dest`""
    $answer = Read-Host "Do you want to extract the zip file again? (Y/N)"
    if ($answer -notmatch '^[Yy]') {
        Write-PLMInfo "Skipping extraction. Re-attempting deploy.bat..."
        $doExtract = $false
    }
}

# ── Extract ───────────────────────────────────────────────────
if ($doExtract) {
    Write-PLMHeader "Extracting Deployment Center install files"
    Remove-Item "$dest\*" -Recurse -Force -ErrorAction SilentlyContinue
    Expand-Archive -Force -Path $zipFile.FullName -DestinationPath $dest
    Write-Host ""
}

# ── Run deploy.bat ────────────────────────────────────────────
Write-PLMHeader "Running deploy.bat"
Write-Host $dest
Write-Host "Check 'C:\Tmp\DeploymentCenterBuild\logs' for logs in deployment."
Set-Location $dest

& cmd.exe /c "deploy.bat -dcusername=dcadmin -dcpassword=dcadmin -softwareLocation=$env:SOFTWARE_LOCATION"
if ($LASTEXITCODE -ne 0) {
    Write-PLMError "deploy.bat failed (exit $LASTEXITCODE)"
    exit $LASTEXITCODE
}

# ── Cleanup ───────────────────────────────────────────────────
Remove-PLMLog
Write-PLMSuccess "deploy-dc-scripts completed successfully."
