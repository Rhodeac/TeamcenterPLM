# ============================================================
# send-tem-to-dc.ps1
# Syncs the TEM configuration with the Deployment Center.
# ============================================================

. "$PSScriptRoot\PLM-Common.ps1"

Assert-Admin
Import-PLMConfig
Import-TCProfileVars

# ── Resolve tool path ─────────────────────────────────────────
$toolDir = "C:\Apps\Siemens\DeploymentCenter\webserver\additional_tools\internal\send_configuration_to_dc"

if (-not (Test-Path $toolDir)) {
    Write-PLMError "send_configuration_to_dc tool not found at: $toolDir"
    exit 1
}

# ── Run send_configuration_to_dc ─────────────────────────────
Set-Location $toolDir

& cmd.exe /c "send_configuration_to_dc.bat" `
    "-dcurl=http://anthonysandbox.sabelgov.us:8085/deploymentcenter" `
    -dcusername=dcadmin `
    -dcpassword=dcadmin `
    -environment=TcEnv1

if ($LASTEXITCODE -ne 0) { Write-PLMError "send_configuration_to_dc failed (exit $LASTEXITCODE)"; exit $LASTEXITCODE }

# To see the report, check: C:\Apps\Siemens\DeploymentCenter\repository\report

Remove-PLMLog
Write-PLMSuccess "send-tem-to-dc completed successfully."
