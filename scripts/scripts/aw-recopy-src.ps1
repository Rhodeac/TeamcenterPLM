# ============================================================
# aw-recopy-src.ps1
# Hot-reload loop: press R to robocopy src to AWS, Q to quit.
# ============================================================

. "$PSScriptRoot\PLM-Common.ps1"

Assert-Admin
Import-PLMConfig

# ── Paths ─────────────────────────────────────────────────────
$backupFile = Join-Path $PLM_HOME_ROOT "backups\src_backup.zip"
$srcLocal   = Join-Path $PLM_HOME_ROOT "src"
$awsSrcDir  = $env:AWS_SRC_DIR

# ── Guard: must be initialized first ─────────────────────────
if (-not (Test-Path $backupFile)) {
    Write-PLMError "Did not find: $backupFile"
    Write-PLMError "Repo has not been initialized. Please run 'plm-home-init.ps1' first."
    Read-Host "Press ENTER to exit"
    exit 1
}

# ── Interactive copy loop ─────────────────────────────────────
while ($true) {
    Write-Host ""
    $key = Read-Host "Press [R] to copy src to AWS, [Q] to quit"

    switch ($key.Trim().ToUpper()) {
        'R' {
            Write-PLMHeader "Copying configurations over to AWS"
            robocopy $srcLocal $awsSrcDir /E /COPY:DAT /R:0 /W:0 /IS /NFL /NDL /NP /NS /NC /XO
            Write-PLMSuccess "Copy complete."
        }
        'Q' {
            Remove-PLMLog
            exit 0
        }
        default {
            Write-Host "  Invalid input. Press R or Q." -ForegroundColor Yellow
        }
    }
}
