# ============================================================
# deploy-tcwar.ps1
# Copies tc.war to Tomcat's webapps folder and restarts Tomcat.
# ============================================================

. "$PSScriptRoot\PLM-Common.ps1"

Assert-Admin
Import-PLMConfig

# ── Resolve paths from env ────────────────────────────────────
$source = $env:TC_WAR_LOC
$dest   = $env:TOMCAT_WEBAPP

# ── Guard: source must exist ──────────────────────────────────
if ([string]::IsNullOrEmpty($source) -or -not (Test-Path $source)) {
    Write-PLMError "tc.war source not found at: $source"
    exit 1
}

if ([string]::IsNullOrEmpty($dest) -or -not (Test-Path $dest)) {
    Write-PLMError "Tomcat webapps destination not found at: $dest"
    exit 1
}

# ── Copy tc.war ───────────────────────────────────────────────
Copy-Item -Path $source -Destination $dest -Force
Write-PLMSuccess "tc.war has been copied successfully."

# ── Restart Tomcat ────────────────────────────────────────────
Stop-Service -Name "Tomcat9" -ErrorAction Stop
Start-Service -Name "Tomcat9" -ErrorAction Stop
Write-PLMSuccess "Tomcat has been restarted successfully."

# ── Cleanup ───────────────────────────────────────────────────
Remove-PLMLog
