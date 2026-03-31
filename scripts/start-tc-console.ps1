# ============================================================
# start-tc-console.ps1
# Opens an interactive PowerShell console pre-loaded with
# Teamcenter environment variables, rooted at PLM_Home.
# ============================================================

$env:TC_ROOT = "C:\Apps\Siemens\TEAMCE~1\tc_root"
$env:TC_DATA = "C:\Apps\Siemens\TEAMCE~1\tc_data"

# Load Teamcenter profile vars into current process
$tcProfileVars = "$env:TC_DATA\tc_profilevars.bat"
if (Test-Path $tcProfileVars) {
    $envDump = cmd.exe /c "call `"$tcProfileVars`" && set"
    foreach ($line in $envDump) {
        if ($line -match '^([^=]+)=(.*)$') {
            [System.Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], 'Process')
        }
    }
}

# Open a new interactive PowerShell window rooted at PLM_Home
$plmHomeRoot = Resolve-Path (Join-Path $PSScriptRoot "..\")

Start-Process powershell -ArgumentList `
    "-NoExit", `
    "-NoProfile", `
    "-ExecutionPolicy Bypass", `
    "-Command `"Set-Location '$plmHomeRoot'; Write-Host 'Teamcenter Console Ready' -ForegroundColor Green`""
