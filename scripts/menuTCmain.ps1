#Requires -RunAsAdministrator

# ============================================================
# PLM Home Dir - Script Launcher Menu
# ============================================================

$PLM_HOME_DIR_ROOT = Resolve-Path (Join-Path $PSScriptRoot "..\")
$LOG_FILE          = Join-Path $PLM_HOME_DIR_ROOT "log.txt"
$CONFIG_FILE       = Join-Path $PLM_HOME_DIR_ROOT "config.env"

# ── Color helpers ────────────────────────────────────────────
function Print-Error   { param([string]$msg) Write-Host $msg -ForegroundColor Red     -NoNewline }
function Print-Info    { param([string]$msg) Write-Host $msg -ForegroundColor Cyan    -NoNewline }
function Print-Success { param([string]$msg) Write-Host $msg -ForegroundColor Green   -NoNewline }
function Print-Header  { param([string]$msg) Write-Host $msg -ForegroundColor White -BackgroundColor DarkGray -NoNewline }
function Print-Plain   { param([string]$msg) Write-Host $msg -NoNewline }

# ── Load config.env ──────────────────────────────────────────
if (Test-Path $CONFIG_FILE) {
    Get-Content $CONFIG_FILE | ForEach-Object {
        if ($_ -match '^\s*([^#][^=]*?)\s*=\s*(.*)\s*$') {
            [System.Environment]::SetEnvironmentVariable($Matches[1].Trim(), $Matches[2].Trim(), 'Process')
        }
    }
}

# ── Script definitions  (Name | RelativePath | Description) ──
$scripts = @(
    [pscustomobject]@{ Name = "TC Command Prompt";                File = "start-tc-console.bat";                        Desc = "Starts the Teamcenter Command Console" }
    [pscustomobject]@{ Name = "Backup Teamcenter Data";           File = "full-backup.bat";                             Desc = "Does full backup" }
    [pscustomobject]@{ Name = "Backup Admin Data";                File = "helper/backup-tc-configs.bat";                Desc = "Backs up Workflows, Organization, etc." }
    [pscustomobject]@{ Name = "Deploy DC Scripts";                File = "deploy-dc-scripts.bat";                       Desc = "Runs the deployment center changes and files" }
    [pscustomobject]@{ Name = "Deploy tc.war to Tomcat";          File = "deploy-tcwar.bat";                            Desc = "Moves tc.war to Tomcat's environment" }
    [pscustomobject]@{ Name = "Deploy All PLM_Home_Dir Changes";  File = "deploy-plm-home-dir-config.bat";              Desc = "Runs many scripts in the order needed" }
    [pscustomobject]@{ Name = "Deploy AWS /src";                  File = "aw-recopy-src.bat";                           Desc = "Allows a user to redeploy changes on a loop while developing" }
    [pscustomobject]@{ Name = "Send Configuration to DC";         File = "send-config-to-dc.bat";                       Desc = "Sends the PLM_Home_Dir configuration to deployment center" }
    [pscustomobject]@{ Name = "Send TEM Config to DC";            File = "send-tem-to-dc.bat";                          Desc = "Runs send_configuration_to_dc to sync TEM and Deployment Center" }
    [pscustomobject]@{ Name = "Initialize PLM_Home_Dir";          File = "plm-home-dir-init.bat";                       Desc = "Initializes the PLM_Home_Dir environment" }
    [pscustomobject]@{ Name = "Migrate Volume Data";              File = "migrate-volume-data.bat";                     Desc = "Transfers data between ArchiveVolume and DefaultVolume" }
    [pscustomobject]@{ Name = "Start & Stop Services";            File = "start-stop-services.bat";                     Desc = "Starts and stops services for user automatically" }
    [pscustomobject]@{ Name = "Start AWS Dev Environment";        File = "aw-start-dev.bat";                            Desc = "Starts the development environment" }
    [pscustomobject]@{ Name = "Import Tile XML";                  File = "helper/import-tile-definitions.bat";          Desc = "Uploads a .xml file to Teamcenter's database" }
    [pscustomobject]@{ Name = "Import Workspace XML";             File = "helper/import-workspace-config.bat";          Desc = "Uploads a .xml file to Teamcenter's database" }
    [pscustomobject]@{ Name = "Remove Workspace Config";          File = "helper/remove-workspace-config.bat";          Desc = "Removes the workspace .xml from Teamcenter" }
    [pscustomobject]@{ Name = "Show Console Colors";              File = "helper/DEBUG-console-colors.bat";             Desc = "Prints color codes to console" }
)

# ── State ─────────────────────────────────────────────────────
$showDesc      = $false
$lastElapsed   = $null

# ── Main menu loop ────────────────────────────────────────────
:menuLoop while ($true) {

    Clear-Host

    if ($lastElapsed) {
        Print-Info "Time Elapsed on Last Function: $lastElapsed"
        Write-Host ""
    }

    Write-Host "============================================"
    Write-Host "Select a script to run: (i to toggle descriptions)"
    Write-Host "============================================"
    Write-Host "   0. Exit"

    for ($i = 0; $i -lt $scripts.Count; $i++) {
        $num     = ($i + 1).ToString().PadLeft(2)
        $entry   = $scripts[$i]
        Write-Host "  $num. $($entry.Name)"
        if ($showDesc) {
            Write-Host "         - $($entry.Desc)" -ForegroundColor DarkGray
        }
    }

    Write-Host "============================================"
    $choice = Read-Host "Enter your choice"

    # Exit
    if ($choice -eq '0') { break menuLoop }

    # Toggle descriptions
    if ($choice -eq 'i') {
        $showDesc = -not $showDesc
        continue menuLoop
    }

    # Validate numeric input
    $idx = 0
    if (-not [int]::TryParse($choice, [ref]$idx) -or $idx -lt 1 -or $idx -gt $scripts.Count) {
        Write-Host "Invalid choice. Try again." -ForegroundColor Red
        Read-Host "Press ENTER to continue"
        continue menuLoop
    }

    $entry    = $scripts[$idx - 1]
    $fullPath = Join-Path $PSScriptRoot $entry.File

    Write-Host ""
    Print-Plain  "You selected: "
    Print-Info   "$($entry.Name)"
    Write-Host ""
    Write-Host ""

    # Verify the target file exists
    if (-not (Test-Path $fullPath)) {
        Write-Host "ERROR: Script not found: $fullPath" -ForegroundColor Red
        Read-Host "Press ENTER to continue"
        continue menuLoop
    }

    # ── Time the call ─────────────────────────────────────────
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    & cmd.exe /c `"$fullPath`"

    $sw.Stop()
    $ts          = $sw.Elapsed
    $lastElapsed = '{0}:{1:mm}:{1:ss},{2:ff}' -f [int]$ts.TotalHours, $ts, $ts

    # ── Post-run feedback ─────────────────────────────────────
    Write-Host ""
    Print-Success "Time Elapsed: $lastElapsed"
    Write-Host ""
    Write-Host ""
    Read-Host "Press ENTER to continue"
}

# ── Cleanup ───────────────────────────────────────────────────
if (Test-Path $LOG_FILE) { Remove-Item -Force $LOG_FILE }
