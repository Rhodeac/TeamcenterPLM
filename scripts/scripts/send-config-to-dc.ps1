# ============================================================
# send-config-to-dc.ps1
# Sends the PLM_Home configuration to the Deployment Center.
# ============================================================

. "$PSScriptRoot\PLM-Common.ps1"

Assert-Admin
Import-PLMConfig

# ── Resolve paths ─────────────────────────────────────────────
$dcToolDir  = Join-Path $env:DEPLOY_WEBSERVER "additional_tools\internal\dc_quick_deploy"
$inputFile  = Join-Path $PLM_HOME_ROOT        "deployment-config\dc_envs\PLMHomeEnv_full_deploy_config.xml"

if (-not (Test-Path $dcToolDir)) {
    Write-PLMError "DC quick-deploy tool not found at: $dcToolDir"
    exit 1
}
if (-not (Test-Path $inputFile)) {
    Write-PLMError "Deploy config XML not found at: $inputFile"
    exit 1
}

# ── Run dc_quick_deploy ───────────────────────────────────────
Set-Location $dcToolDir

& cmd.exe /c "dc_quick_deploy.bat" `
    "-dcurl=http://anthonysandbox.sabelgov.us:8085/deploymentcenter" `
    -dcusername=dcadmin `
    -dcpassword=dcadmin `
    -environment=PLMHomeEnv `
    -mode=import `
    "-inputfile=$inputFile"

if ($LASTEXITCODE -ne 0) { Write-PLMError "dc_quick_deploy failed (exit $LASTEXITCODE)"; exit $LASTEXITCODE }

Remove-PLMLog
Write-PLMSuccess "send-config-to-dc completed successfully."
