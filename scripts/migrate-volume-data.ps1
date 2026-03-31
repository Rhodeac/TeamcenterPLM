# ============================================================
# migrate-volume-data.ps1
# Archives stale files and un-archives recently touched files.
# ============================================================

. "$PSScriptRoot\PLM-Common.ps1"

Assert-Admin
Import-PLMConfig

# Load Teamcenter profile vars
Import-TCProfileVars

# ── Compute cutoff date ───────────────────────────────────────
$pastDate = (Get-Date).AddDays(-[int]$env:DAYS_TIL_FILE_IS_STALE).ToString("dd-MMM-yyyy")

# ── Archive stale files ───────────────────────────────────────
Write-PLMHeader "Archiving files not touched for $($env:DAYS_TIL_FILE_IS_STALE) days."
Write-PLMInfo   "Before: $pastDate"

& move_volume_files `
    -u=infodba -p=infodba -g=dba `
    -f=move `
    -srcvol=DefaultVolume `
    "-destvol=$($env:ARCHIVE_VOLUME_NAME)" `
    -after=03-Feb-2008 `
    "-before=$pastDate" `
    "-output_file=$PLM_HOME_ROOT\volume-move-archived.txt"

if ($LASTEXITCODE -ne 0) { Write-PLMError "Archive step failed (exit $LASTEXITCODE)"; exit $LASTEXITCODE }

# ── Un-archive recently active files ─────────────────────────
Write-PLMHeader "Un-archiving relevant files."

& move_volume_files `
    -u=infodba -p=infodba -g=dba `
    -f=move `
    "-srcvol=$($env:ARCHIVE_VOLUME_NAME)" `
    -destvol=DefaultVolume `
    "-after=$pastDate" `
    "-output_file=$PLM_HOME_ROOT\volume-move-unarchived.txt"

if ($LASTEXITCODE -ne 0) { Write-PLMError "Un-archive step failed (exit $LASTEXITCODE)"; exit $LASTEXITCODE }

Remove-PLMLog
Write-PLMSuccess "migrate-volume-data completed successfully."
