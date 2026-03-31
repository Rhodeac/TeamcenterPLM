# ============================================================
# start-stop-services.ps1
# Interactively starts, stops, restarts, or queries grouped
# Teamcenter / Oracle / Deployment Center services.
#
# Optional args: start-stop-services.ps1 [groupChoice] [actionChoice]
#   groupChoice  : 1-4 (or combination like "12")
#   actionChoice : 1=Start  2=Stop  3=Restart  4=Query
# ============================================================

. "$PSScriptRoot\PLM-Common.ps1"

Assert-Admin
Import-PLMConfig

# ── Service group definitions ─────────────────────────────────
$groups = @{
    '1' = @(
        "Teamcenter FSC Service FSC_AnthonySandbox_SABELGOVanthonydalesandro"
        "Teamcenter Process Manager"
    )
    '2' = @(
        "Teamcenter_Vault_Service_PLMHomeEnv"
        "Teamcenter Suggestion Builder Service"
        "Active Workspace Indexing Service"
        "Teamcenter Global Search Indexing Service"
        "revision_config_accelerator"
        "am_read_expression_manager"
        "Tomcat9"
        "Teamcenter Dispatcher Module V2412.0006.2025061000"
        "Teamcenter Dispatcher Scheduler V2412.0006.2025061000"
        "Teamcenter Server Manager config1_PoolA"
    )
    '3' = @(
        "Teamcenter_DC_RepoService_Publisher"
        "Teamcenter_DC_RepoService"
        "Teamcenter_DC_Service"
        "Teamcenter_DC_Vault_Service"
    )
    '4' = @(
        "OracleOraDB19Home1TNSListener"
        "OracleServiceTC"
    )
}

# ── Service helpers ───────────────────────────────────────────
function Stop-PLMService {
    param([string]$name)
    $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
    if (-not $svc) { Write-Host "  Did not find: $name" -ForegroundColor DarkGray; return }

    Stop-Service -Name $name -Force -ErrorAction SilentlyContinue
    $svc.WaitForStatus('Stopped', (New-TimeSpan -Seconds 60))

    if ((Get-Service -Name $name).Status -ne 'Stopped') {
        Write-PLMError "  Failed to stop: $name"
    }
}

function Start-PLMService {
    param([string]$name)
    $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
    if (-not $svc) { Write-Host "  Did not find: $name" -ForegroundColor DarkGray; return }

    Start-Service -Name $name -ErrorAction SilentlyContinue
    $svc.WaitForStatus('Running', (New-TimeSpan -Seconds 60))

    if ((Get-Service -Name $name).Status -ne 'Running') {
        Write-PLMError "  Failed to start: $name"
    }
}

function Show-PLMService {
    param([string]$name)
    $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-Host "  ??      " -ForegroundColor Red   -NoNewline
        Write-Host " ------ $name"
        return
    }
    $status = $svc.Status.ToString().ToUpper()
    $color  = if ($svc.Status -eq 'Running') { 'Green' } else { 'Red' }
    Write-Host ("  {0,-12}" -f $status) -ForegroundColor $color -NoNewline
    Write-Host " ------ $name"
}

# ── Collect args or prompt ────────────────────────────────────
$groupArg  = if ($args.Count -gt 0) { $args[0] } else { $null }
$actionArg = if ($args.Count -gt 1) { $args[1] } else { $null }

if (-not $groupArg) {
    Write-Host ""
    Write-Host "  1 = Teamcenter FSC and Microservices"
    Write-Host "  2 = Teamcenter Other Services"
    Write-Host "  3 = Deployment Center Services"
    Write-Host "  4 = Oracle"
    Write-Host ""
    $groupArg = Read-Host "Enter choices (e.g. 1, 2, 13)"
}

# ── Build selected service list ───────────────────────────────
$selectedServices = @()
foreach ($key in $groups.Keys) {
    if ($groupArg -match [regex]::Escape($key)) {
        $selectedServices += $groups[$key]
    }
}

if ($selectedServices.Count -eq 0) {
    Write-PLMError "No valid group selected."
    exit 1
}

# ── Select action ─────────────────────────────────────────────
if (-not $actionArg) {
    Write-Host ""
    Write-Host "  1 = Start Services"
    Write-Host "  2 = Stop Services"
    Write-Host "  3 = Restart Services"
    Write-Host "  4 = Query Services"
    Write-Host ""
    $actionArg = Read-Host "Enter choice"
}

$doStop  = $actionArg -match '[23]'
$doStart = $actionArg -match '[13]'
$doQuery = $actionArg -match '4'

$total = $selectedServices.Count

# ── Stop ──────────────────────────────────────────────────────
if ($doStop) {
    Write-PLMHeader "Stopping $total Service(s)"
    $i = 0
    foreach ($svc in $selectedServices) {
        $i++
        Write-Host "Stopping service $i/$total`: $svc"
        Stop-PLMService $svc
    }
}

# ── Start ─────────────────────────────────────────────────────
if ($doStart) {
    Write-PLMHeader "Starting $total Service(s)"
    $i = 0
    foreach ($svc in $selectedServices) {
        $i++
        Write-Host "Starting service $i/$total`: $svc"
        Start-PLMService $svc
    }
}

# ── Query ─────────────────────────────────────────────────────
if ($doQuery) {
    Write-PLMHeader "Querying $total Service(s)"
    foreach ($svc in $selectedServices) {
        Show-PLMService $svc
    }
}

Remove-PLMLog
