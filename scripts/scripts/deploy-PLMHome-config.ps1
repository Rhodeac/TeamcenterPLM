# ============================================================
# deploy-PLMHome-config.ps1
# Deploys all PLM_Home configurations in the correct order.
# ============================================================

. "$PSScriptRoot\PLM-Common.ps1"

Assert-Admin
Import-PLMConfig

# ── Refresh env vars exposed by Teamcenter profile ───────────
# Equivalent of: call tc_profilevars
$tcProfileVars = "C:\Apps\Siemens\TEAMCE~1\tc_data\tc_profilevars.bat"
if (Test-Path $tcProfileVars) {
    # Load vars into current process via cmd subshell
    $envDump = cmd.exe /c "call `"$tcProfileVars`" && set"
    foreach ($line in $envDump) {
        if ($line -match '^([^=]+)=(.*)$') {
            [System.Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], 'Process')
        }
    }
}

# ── Resolve paths from env ────────────────────────────────────
$backupFile  = Join-Path $env:FULL_BACKUP_LOC "aws_src_backup.7z"
$srcLocal    = Join-Path $PLM_HOME_ROOT "src"
$awsSrcDir   = $env:AWS_SRC_DIR
$awsBuildDir = Split-Path $awsSrcDir -Parent
$exportFile  = Join-Path $PLM_HOME_ROOT "deployment-config\admin_data_export.zip"

# ── Guard: must be initialized first ─────────────────────────
Write-PLMHeader "Deploying PLM_Home Configurations"

if (-not (Test-Path $backupFile)) {
    Write-PLMError "Did not find: $backupFile"
    Write-PLMError "Repo has not been initialized. Please run 'plm-home-init.ps1' first."
    exit 1
}

# ── 1. Copy src configurations to AWS ────────────────────────
Write-PLMHeader "Copying configurations over to AWS"
robocopy $srcLocal $awsSrcDir /E /COPY:DAT /R:0 /W:0 /IS /NFL /NDL /NP /NS /NC /XO

# ── 2. npm run clean ──────────────────────────────────────────
Write-PLMHeader "(~2 min) npm run clean"
Set-Location $awsBuildDir
& cmd.exe /c "call initenv.cmd && npm run clean"
if ($LASTEXITCODE -ne 0) { Write-PLMError "npm run clean failed (exit $LASTEXITCODE)"; exit $LASTEXITCODE }

# ── 3. npm run audit ──────────────────────────────────────────
Write-PLMHeader "(~2 min) npm run audit"
& cmd.exe /c "npm run audit"
if ($LASTEXITCODE -ne 0) { Write-PLMError "npm run audit failed (exit $LASTEXITCODE)"; exit $LASTEXITCODE }

# ── 4. npm run build ──────────────────────────────────────────
Write-PLMHeader "(~10 min) Building Active Workspace"
$env:ENDPOINT_GATEWAY = "http://localhost:3000"
& cmd.exe /c "npm run build"
if ($LASTEXITCODE -ne 0) { Write-PLMError "npm run build failed (exit $LASTEXITCODE)"; exit $LASTEXITCODE }

# ── 5. Delete client cache ────────────────────────────────────
Write-PLMHeader "Clearing Client Cache"
& bmide_generate_client_cache -u=infodba -p=infodba -g=dba -mode=delete -cache=all
if ($LASTEXITCODE -ne 0) { Write-PLMError "Cache delete failed (exit $LASTEXITCODE)"; exit $LASTEXITCODE }

# ── 6. Import admin data ──────────────────────────────────────
Write-PLMHeader "Importing Admin Data (Stylesheets, Projects, etc.)"

$mergeOptions = @(
    "AccessManager:override_with_source"
    "LogicalObjects:override_with_source"
    "Organization:override_with_source"
    "Projects:override_with_source"
    "Preferences:override_with_source"
    "RevisionRules:override_with_source"
    "SavedQueries:override_with_source"
    "Stylesheets:override_with_source"
    "Subscriptions:override_with_source"
    "WorkflowTemplates:override_with_source"
) -join ","

& admin_data_import `
    -u=infodba `
    -p=infodba `
    -g=dba `
    -skipPackageValidation `
    "-inputPackage=$exportFile" `
    -adminDataTypes=all `
    "-mergeOption=$mergeOptions"

if ($LASTEXITCODE -ne 0) { Write-PLMError "admin_data_import failed (exit $LASTEXITCODE)"; exit $LASTEXITCODE }

# ── 7. Regenerate client cache ────────────────────────────────
Write-PLMHeader "Regenerating Client Cache"
& bmide_generate_client_cache -u=infodba -p=infodba -g=dba -mode=generate -cache=all "-model_file=$env:TC_DATA\model\model.xml"
if ($LASTEXITCODE -ne 0) { Write-PLMError "Cache regeneration failed (exit $LASTEXITCODE)"; exit $LASTEXITCODE }

# ── 8. Import tile & workspace definitions ────────────────────
Write-PLMHeader "Importing Tile and Workspace Definitions"
& "$PSScriptRoot\helper\import-tile-definitions.ps1"
& "$PSScriptRoot\helper\import-workspace-config.ps1"

# ── Cleanup ───────────────────────────────────────────────────
Remove-PLMLog
Write-PLMSuccess "deploy-PLMHome-config completed successfully."
