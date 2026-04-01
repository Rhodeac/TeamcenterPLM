# ================================================================
#  ARCHIVE SIGNING & VERIFICATION  —  7-ZIP ULTIMATE MENU ADD-ON
#  Certificate-based tamper detection for compressed archives
#  Version 1.0  |  Compatible with 7-Zip Ultimate Menu v2.2+
#  Created by Andrew C. Rhodes 
#  HOW IT WORKS:
#   1. After creating an archive, a SHA-256 hash of the archive
#      file is computed and then digitally signed using an RSA
#      private key stored in the Windows Certificate Store.
#   2. The signature + certificate thumbprint are saved as a
#      small sidecar file: <archive>.sig.json  next to the archive.
#   3. On verification, the archive is re-hashed, the original
#      signing certificate is retrieved from the store (by
#      thumbprint), and the RSA signature is validated.
#      Any tampering with the archive bytes changes the hash
#      and breaks the signature — instantly detectable.
#
#  SIGNING FLOW:
#   Archive file  →  SHA-256 hash  →  RSA-sign with private key
#                                         ↓
#                               .sig.json sidecar saved
#
#  VERIFY FLOW:
#   Archive file  →  SHA-256 hash  →  RSA-verify with public key
#   .sig.json     →  cert thumbprint → look up cert in store
#                                         ↓
#                               VALID / INVALID / CERT-MISSING
#
#  CERTIFICATE OPTIONS:
#   A) Self-signed (built-in, zero dependencies) — good for
#      personal or internal use; you trust yourself.
#   B) Existing cert from Windows Certificate Store — use any
#      cert that has a private key (code-signing, personal, etc.)
#   C) Import a .pfx file — bring your own cert from another
#      machine or a CA.
#
#  SIDECAR FILE FORMAT  (<archive>.sig.json):
#   {
#     "archive"     : "data_2025-06-01.7z",
#     "signed_at"   : "2025-06-01 14:32:10",
#     "signer"      : "CN=7ZipMenu Signing, O=Sabel Sys",
#     "thumbprint"  : "A1B2C3D4...",
#     "algorithm"   : "SHA256withRSA",
#     "hash"        : "abc123...",   ← SHA-256 of the archive
#     "signature"   : "base64..."   ← RSA signature of the hash
#   }
#
#  INTEGRATION:
#   1. Paste this file's functions into your main script BEFORE
#      Show-MainMenu (or dot-source it:  . .\7ZipMenu_ArchiveSigning.ps1)
#   2. Add menu items [29] [30] [31] [32] as shown at the bottom
#   3. Add the switch cases to your do/while loop
#   4. Optionally: call  Auto-SignAfterCompress  at the end of
#      Invoke-7ZipBrowser / Invoke-7ZipManualPath / Invoke-BatchCompress
#      to sign automatically after every compression job
# ================================================================


# ================================================================
#  CERT STORE HELPERS
# ================================================================

function Get-SigningCerts {
    <#
    .SYNOPSIS
        Returns all certificates in the current user's Personal store
        that have an RSA private key available.
    #>
    Get-ChildItem Cert:\CurrentUser\My |
        Where-Object {
            $_.HasPrivateKey -and
            $_.PublicKey.Oid.FriendlyName -eq "RSA" -and
            $_.NotAfter -gt (Get-Date)
        } |
        Select-Object Thumbprint, Subject, NotAfter,
            @{ N="KeySize"; E={ $_.PublicKey.Key.KeySize } }
}

function Show-CertTable {
    param([array]$Certs)
    if (-not $Certs -or $Certs.Count -eq 0) { return }
    $i = 0
    foreach ($c in $Certs) {
        $i++
        Write-Host ("  [{0}] {1}" -f $i, $c.Subject) -ForegroundColor White
        Write-Host ("      Thumbprint : {0}" -f $c.Thumbprint) -ForegroundColor DarkGray
        Write-Host ("      Expires    : {0}  |  Key: {1}-bit RSA" -f $c.NotAfter.ToString("yyyy-MM-dd"), $c.KeySize) -ForegroundColor DarkGray
        Write-Host ""
    }
}

function Get-CertByThumbprint {
    param([string]$Thumbprint)
    # Search CurrentUser\My first, then LocalMachine\My
    $cert = Get-ChildItem Cert:\CurrentUser\My\$Thumbprint -ErrorAction SilentlyContinue
    if (-not $cert) {
        $cert = Get-ChildItem Cert:\LocalMachine\My\$Thumbprint -ErrorAction SilentlyContinue
    }
    # For verification we also accept certs without a private key
    if (-not $cert) {
        $cert = Get-ChildItem Cert:\CurrentUser\TrustedPeople\$Thumbprint -ErrorAction SilentlyContinue
    }
    return $cert
}

# ================================================================
#  CERTIFICATE MANAGEMENT MENU
# ================================================================

function Invoke-ManageCerts {
    Write-Header "CERTIFICATE MANAGER  —  Archive Signing"

    Write-Host "  [1] List available signing certificates"          -ForegroundColor White
    Write-Host "  [2] Create a new self-signed signing certificate" -ForegroundColor White
    Write-Host "  [3] Import a certificate from .pfx file"          -ForegroundColor White
    Write-Host "  [4] Export a certificate to .cer (public key)"    -ForegroundColor White
    Write-Host "  [5] Delete / remove a certificate"                -ForegroundColor White
    Write-Host "  [6] Back to main menu"                            -ForegroundColor DarkGray
    Write-Host ""
    $choice = (Read-Host "  Choose [1-6]").Trim()

    switch ($choice) {

        # ── LIST ──────────────────────────────────────────────
        "1" {
            Write-Header "AVAILABLE SIGNING CERTIFICATES"
            $certs = Get-SigningCerts
            if (-not $certs -or $certs.Count -eq 0) {
                Write-Wrn "No usable RSA certificates with private keys found."
                Write-Inf "Use option [2] to create a self-signed certificate."
            } else {
                Write-Inf "Found $($certs.Count) usable certificate(s) in CurrentUser\My:"
                Write-Host ""
                Show-CertTable $certs
            }
        }

        # ── CREATE SELF-SIGNED ────────────────────────────────
        "2" {
            Write-Header "CREATE SELF-SIGNED SIGNING CERTIFICATE"
            Write-Inf "This creates a new RSA-4096 certificate stored in your"
            Write-Inf "Windows Certificate Store (CurrentUser\My).  It is"
            Write-Inf "trusted only on this machine unless you export and share it."
            Write-Host ""

            $defaultSubject = "CN=7ZipMenu Signing, O=$env:COMPUTERNAME, OU=Backup"
            $rawSubject = (Read-Host "  Certificate subject (Enter for default)").Trim()
            if (-not $rawSubject) { $rawSubject = $defaultSubject }

            $years = (Read-Host "  Valid for how many years? (default 10)").Trim()
            if (-not $years -or $years -notmatch '^\d+$') { $years = 10 }
            $expiry = (Get-Date).AddYears([int]$years)

            Write-Inf "Creating RSA-4096 self-signed certificate..."
            Write-Inf "Subject  : $rawSubject"
            Write-Inf "Expires  : $($expiry.ToString('yyyy-MM-dd'))"
            Write-Host ""

            try {
                $cert = New-SelfSignedCertificate `
                    -Subject         $rawSubject `
                    -CertStoreLocation "Cert:\CurrentUser\My" `
                    -KeyAlgorithm    RSA `
                    -KeyLength       4096 `
                    -HashAlgorithm   SHA256 `
                    -KeyUsage        DigitalSignature `
                    -Type            Custom `
                    -NotAfter        $expiry `
                    -KeyExportPolicy Exportable

                Write-OK "Certificate created!"
                Write-Host ""
                Write-Host "  Thumbprint : " -NoNewline; Write-Host $cert.Thumbprint -ForegroundColor Cyan
                Write-Host "  Subject    : " -NoNewline; Write-Host $cert.Subject    -ForegroundColor White
                Write-Host "  Expires    : " -NoNewline; Write-Host $cert.NotAfter.ToString("yyyy-MM-dd") -ForegroundColor White
                Write-Host ""
                Write-Wrn "The private key is stored in Windows Credential Manager."
                Write-Wrn "Export a .pfx backup now (option 4) to avoid losing it."
                Write-Log "Created self-signed cert: $($cert.Thumbprint) | $rawSubject | expires $($expiry.ToString('yyyy-MM-dd'))"

                if (Confirm-Action "Export this certificate as .pfx backup now?") {
                    Export-PfxCert -Cert $cert
                }
            } catch {
                Write-Err "Failed to create certificate: $_"
            }
        }

        # ── IMPORT PFX ────────────────────────────────────────
        "3" {
            Write-Header "IMPORT CERTIFICATE FROM .PFX"
            $pfxFile = Select-FileDialog -Title "Select .pfx certificate file" `
                -Filter "PFX Certificate (*.pfx)|*.pfx|All Files (*.*)|*.*"
            if (-not $pfxFile) { Write-Wrn "Cancelled."; Pause-Menu; return }

            $passS = Read-Host "  PFX password (leave blank if none)" -AsSecureString
            Write-Inf "Importing certificate from: $(Split-Path $pfxFile -Leaf)"

            try {
                $cert = Import-PfxCertificate `
                    -FilePath         $pfxFile `
                    -CertStoreLocation "Cert:\CurrentUser\My" `
                    -Password         $passS `
                    -Exportable

                Write-OK "Imported successfully!"
                Write-Host "  Thumbprint : $($cert.Thumbprint)" -ForegroundColor Cyan
                Write-Host "  Subject    : $($cert.Subject)"    -ForegroundColor White
                Write-Host "  Expires    : $($cert.NotAfter.ToString('yyyy-MM-dd'))" -ForegroundColor White
                Write-Log "Imported cert: $($cert.Thumbprint) | $($cert.Subject)"
            } catch {
                Write-Err "Import failed: $_"
            }
        }

        # ── EXPORT .CER / .PFX ────────────────────────────────
        "4" {
            Write-Header "EXPORT CERTIFICATE"
            $certs = Get-SigningCerts
            if (-not $certs -or $certs.Count -eq 0) {
                Write-Wrn "No exportable certificates found."
                Pause-Menu; return
            }
            Show-CertTable $certs
            $idx = (Read-Host "  Select certificate [1-$($certs.Count)]").Trim()
            if ($idx -notmatch '^\d+$' -or [int]$idx -lt 1 -or [int]$idx -gt $certs.Count) {
                Write-Wrn "Invalid selection."; Pause-Menu; return
            }
            $selected = $certs[[int]$idx - 1]
            $cert     = Get-Item "Cert:\CurrentUser\My\$($selected.Thumbprint)"

            Write-Host ""
            Write-Host "  Export as:" -ForegroundColor Yellow
            Write-Host "  [1] .cer  — Public key only (safe to share)"   -ForegroundColor White
            Write-Host "  [2] .pfx  — Full certificate with private key" -ForegroundColor White
            Write-Host ""
            $exportType = (Read-Host "  Choose [1-2]").Trim()

            $out = Select-FolderDialog -Description "Select destination folder for export"
            if (-not $out) { Write-Wrn "Cancelled."; Pause-Menu; return }

            $safeName = ($cert.Subject -replace '[^A-Za-z0-9_-]', '_') -replace '__+', '_'

            if ($exportType -eq "2") {
                Export-PfxCert -Cert $cert -DestFolder $out
            } else {
                $cerPath = Join-Path $out "$safeName.cer"
                $bytes   = $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
                [System.IO.File]::WriteAllBytes($cerPath, $bytes)
                Write-OK "Public certificate exported: $cerPath"
                Write-Inf "Share this .cer file with anyone who needs to VERIFY your archives."
                Write-Log "Exported .cer: $($cert.Thumbprint) → $cerPath"
            }
        }

        # ── DELETE ────────────────────────────────────────────
        "5" {
            Write-Header "REMOVE CERTIFICATE"
            $certs = Get-SigningCerts
            if (-not $certs -or $certs.Count -eq 0) {
                Write-Wrn "No certificates found."
                Pause-Menu; return
            }
            Show-CertTable $certs
            $idx = (Read-Host "  Select certificate to REMOVE [1-$($certs.Count)]").Trim()
            if ($idx -notmatch '^\d+$' -or [int]$idx -lt 1 -or [int]$idx -gt $certs.Count) {
                Write-Wrn "Invalid selection."; Pause-Menu; return
            }
            $selected = $certs[[int]$idx - 1]
            Write-Wrn "This will permanently delete the certificate AND its private key."
            if (Confirm-Action "Delete '$($selected.Subject)'?") {
                Remove-Item "Cert:\CurrentUser\My\$($selected.Thumbprint)" -Force
                Write-OK "Certificate removed."
                Write-Log "Removed cert: $($selected.Thumbprint) | $($selected.Subject)"
            } else {
                Write-Inf "Cancelled — certificate not removed."
            }
        }

        "6" { return }
        default { Write-Wrn "Invalid choice." }
    }
    Pause-Menu
}

function Export-PfxCert {
    param(
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Cert,
        [string]$DestFolder = ""
    )
    if (-not $DestFolder) {
        $DestFolder = Select-FolderDialog -Description "Select destination for .pfx export"
        if (-not $DestFolder) { Write-Wrn "Cancelled."; return }
    }
    $safeName = ($Cert.Subject -replace '[^A-Za-z0-9_-]', '_') -replace '__+', '_'
    $pfxPath  = Join-Path $DestFolder "$safeName.pfx"

    Write-Host ""
    Write-Host "  You MUST set a strong password for the .pfx file." -ForegroundColor Yellow
    Write-Host "  Anyone with the .pfx + password can sign archives as you." -ForegroundColor Yellow
    Write-Host ""
    $p1 = Read-Host "  Enter PFX password" -AsSecureString
    $p2 = Read-Host "  Confirm password"   -AsSecureString
    $plain1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                  [Runtime.InteropServices.Marshal]::SecureStringToBSTR($p1))
    $plain2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                  [Runtime.InteropServices.Marshal]::SecureStringToBSTR($p2))
    if ($plain1 -ne $plain2) { Write-Err "Passwords do not match."; $plain1=$null;$plain2=$null; return }

    try {
        $bytes = $Cert.Export(
            [System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx,
            $plain1)
        [System.IO.File]::WriteAllBytes($pfxPath, $bytes)
        Write-OK "PFX exported: $pfxPath"
        Write-Wrn "Keep this file safe — it contains your private signing key!"
        Write-Log "Exported .pfx: $($Cert.Thumbprint) → $pfxPath"
    } catch {
        Write-Err "Export failed: $_"
    }
    $plain1=$null; $plain2=$null
}

# ================================================================
#  SIGNING CORE
# ================================================================

function Invoke-SignArchive {
    <#
    .SYNOPSIS
        Main menu entry — lets user pick an archive and a cert,
        then signs it, producing a .sig.json sidecar.
    #>
    Write-Header "SIGN ARCHIVE  —  RSA / SHA-256"

    # ── Pick archive ──────────────────────────────────────────
    Write-Inf "Select archive to sign..."
    $archiveFile = Select-FileDialog -Title "Select archive to sign" `
        -Filter "Archives (*.7z;*.zip;*.rar;*.tar;*.tar.gz;*.tar.lzma;*.tar.lz4)|*.7z;*.zip;*.rar;*.tar;*.tar.gz;*.tar.lzma;*.tar.lz4|All Files (*.*)|*.*"
    if (-not $archiveFile) { Write-Wrn "Cancelled."; Pause-Menu; return }

    # ── Pick certificate ──────────────────────────────────────
    $cert = Select-SigningCert
    if (-not $cert) { Pause-Menu; return }

    Write-Host ""
    Sign-Archive -ArchivePath $archiveFile -Cert $cert -Verbose
    Pause-Menu
}

function Select-SigningCert {
    <#
    .SYNOPSIS
        Presents a certificate picker and returns the chosen cert object.
        Returns $null if the user cancels or no certs are available.
    #>
    $certs = Get-SigningCerts
    if (-not $certs -or $certs.Count -eq 0) {
        Write-Wrn "No signing certificates found in CurrentUser\My."
        Write-Inf "Go to option [29] Certificate Manager → [2] to create one."
        return $null
    }

    Write-Host ""
    Write-Host "  Available signing certificates:" -ForegroundColor Yellow
    Write-Host ""
    Show-CertTable $certs
    $idx = (Read-Host "  Select certificate [1-$($certs.Count)]").Trim()
    if ($idx -notmatch '^\d+$' -or [int]$idx -lt 1 -or [int]$idx -gt $certs.Count) {
        Write-Wrn "Invalid selection."
        return $null
    }
    return Get-Item "Cert:\CurrentUser\My\$($certs[[int]$idx - 1].Thumbprint)"
}

function Sign-Archive {
    <#
    .SYNOPSIS
        Core signing function. Call directly after compression to auto-sign.
    .PARAMETER ArchivePath
        Full path to the archive file to sign.
    .PARAMETER Cert
        X509Certificate2 object with a private key.
    .PARAMETER Verbose
        If present, write detailed output to console.
    .OUTPUTS
        Path to the .sig.json sidecar, or $null on failure.
    #>
    param(
        [Parameter(Mandatory)][string]$ArchivePath,
        [Parameter(Mandatory)][System.Security.Cryptography.X509Certificates.X509Certificate2]$Cert,
        [switch]$Verbose
    )

    if (-not (Test-Path $ArchivePath)) {
        Write-Err "Archive not found: $ArchivePath"
        return $null
    }

    if (-not $Cert.HasPrivateKey) {
        Write-Err "Selected certificate has no private key — cannot sign."
        return $null
    }

    $sigPath = "$ArchivePath.sig.json"
    $archiveName = Split-Path $ArchivePath -Leaf

    if ($Verbose) {
        Write-Inf "Archive    : $archiveName"
        Write-Inf "Signer     : $($Cert.Subject)"
        Write-Inf "Thumbprint : $($Cert.Thumbprint)"
        Write-Inf "Key size   : $($Cert.PublicKey.Key.KeySize) bit RSA"
        Write-Host ""
        Write-Inf "Step 1/2 — Computing SHA-256 hash of archive..."
    }

    try {
        # ── Hash the archive ──────────────────────────────────
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $hashHex = (Get-FileHash $ArchivePath -Algorithm SHA256).Hash
        $hashBytes = [byte[]]( ($hashHex -split '(?<=\G..)' | Where-Object { $_ }) |
                        ForEach-Object { [Convert]::ToByte($_, 16) } )

        if ($Verbose) {
            Write-Inf "SHA-256    : $hashHex"
            Write-Inf "Step 2/2 — Signing hash with RSA private key..."
        }

        # ── Sign the hash ─────────────────────────────────────
        $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($Cert)
        if (-not $rsa) {
            # Fallback for older .NET / RSA CryptoServiceProvider
            $rsa = $Cert.PrivateKey
        }
        if (-not $rsa) { Write-Err "Cannot access RSA private key."; return $null }

        $sigBytes = $rsa.SignHash(
            $hashBytes,
            [System.Security.Cryptography.HashAlgorithmName]::SHA256,
            [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
        )
        $sw.Stop()

        $sigB64 = [Convert]::ToBase64String($sigBytes)

        # ── Write sidecar ─────────────────────────────────────
        $sidecar = [ordered]@{
            archive     = $archiveName
            signed_at   = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            signer      = $Cert.Subject
            thumbprint  = $Cert.Thumbprint
            algorithm   = "SHA256withRSA"
            key_size    = $Cert.PublicKey.Key.KeySize
            hash        = $hashHex
            signature   = $sigB64
        }
        $sidecar | ConvertTo-Json -Depth 3 | Set-Content $sigPath -Encoding UTF8

        Write-OK "Archive signed successfully!"
        Write-OK "Signature  : $sigPath"
        Write-Inf "Time       : $($sw.Elapsed.TotalSeconds.ToString('F2')) s"
        Write-Log "Signed '$archiveName' | cert=$($Cert.Thumbprint) | hash=$hashHex" "OK"
        return $sigPath

    } catch {
        Write-Err "Signing failed: $_"
        Write-Log "Sign FAILED '$archiveName' | $_" "ERROR"
        return $null
    }
}

# ================================================================
#  VERIFICATION CORE
# ================================================================

function Invoke-VerifySignature {
    <#
    .SYNOPSIS
        Main menu entry — lets user pick an archive (or its .sig.json)
        and verifies the RSA signature.
    #>
    Write-Header "VERIFY ARCHIVE SIGNATURE"

    Write-Host "  Select:" -ForegroundColor Yellow
    Write-Host "  [1] Archive file  (tool will look for <archive>.sig.json beside it)" -ForegroundColor White
    Write-Host "  [2] .sig.json sidecar directly"                                      -ForegroundColor White
    Write-Host ""
    $mode = (Read-Host "  Choose [1-2] (default=1)").Trim()

    if ($mode -eq "2") {
        $sigFile = Select-FileDialog -Title "Select .sig.json sidecar" `
            -Filter "Signature files (*.sig.json)|*.sig.json|All Files (*.*)|*.*"
        if (-not $sigFile) { Write-Wrn "Cancelled."; Pause-Menu; return }

        # Derive archive path from sidecar
        $archiveFile = $sigFile -replace '\.sig\.json$', ''
    } else {
        $archiveFile = Select-FileDialog -Title "Select signed archive" `
            -Filter "Archives (*.7z;*.zip;*.rar;*.tar;*.tar.gz;*.tar.lzma;*.tar.lz4)|*.7z;*.zip;*.rar;*.tar;*.tar.gz;*.tar.lzma;*.tar.lz4|All Files (*.*)|*.*"
        if (-not $archiveFile) { Write-Wrn "Cancelled."; Pause-Menu; return }

        $sigFile = "$archiveFile.sig.json"
    }

    Write-Host ""
    Verify-ArchiveSignature -ArchivePath $archiveFile -SigPath $sigFile -Verbose
    Pause-Menu
}

function Verify-ArchiveSignature {
    <#
    .SYNOPSIS
        Core verification function.
    .OUTPUTS
        $true if valid, $false otherwise.
    #>
    param(
        [Parameter(Mandatory)][string]$ArchivePath,
        [string]$SigPath = "",
        [switch]$Verbose
    )

    if (-not $SigPath) { $SigPath = "$ArchivePath.sig.json" }

    $archiveName = Split-Path $ArchivePath -Leaf

    # ── Load sidecar ──────────────────────────────────────────
    if (-not (Test-Path $SigPath)) {
        Write-Err "Signature file not found: $SigPath"
        Write-Inf "This archive has no signature — it was never signed, or the"
        Write-Inf ".sig.json sidecar was deleted or not transferred with the archive."
        return $false
    }

    try {
        $sidecar = Get-Content $SigPath -Raw | ConvertFrom-Json
    } catch {
        Write-Err "Signature file is corrupt or not valid JSON: $_"
        return $false
    }

    if ($Verbose) {
        Write-Section "SIGNATURE DETAILS"
        Write-Host "  Archive    : $archiveName"                 -ForegroundColor White
        Write-Host "  Signed at  : $($sidecar.signed_at)"        -ForegroundColor White
        Write-Host "  Signer     : $($sidecar.signer)"           -ForegroundColor White
        Write-Host "  Thumbprint : $($sidecar.thumbprint)"       -ForegroundColor White
        Write-Host "  Algorithm  : $($sidecar.algorithm)"        -ForegroundColor White
        Write-Host "  Key size   : $($sidecar.key_size) bit"     -ForegroundColor White
        Write-Host ""
    }

    # ── Check archive exists ──────────────────────────────────
    if (-not (Test-Path $ArchivePath)) {
        Write-Err "Archive file not found: $ArchivePath"
        Write-Wrn "The archive may have been moved, renamed, or deleted."
        return $false
    }

    # ── Re-hash the archive ───────────────────────────────────
    if ($Verbose) { Write-Inf "Step 1/3 — Re-computing SHA-256 of archive..." }
    $currentHash = (Get-FileHash $ArchivePath -Algorithm SHA256).Hash

    if ($Verbose) {
        Write-Inf "Stored hash  : $($sidecar.hash)"
        Write-Inf "Current hash : $currentHash"
    }

    # Fast-fail: if hashes don't match, no need to check the signature
    if ($currentHash -ne $sidecar.hash) {
        Write-Host ""
        Write-Err "═══════════════════════════════════════════════"
        Write-Err " INTEGRITY FAILURE — ARCHIVE HAS BEEN MODIFIED "
        Write-Err "═══════════════════════════════════════════════"
        Write-Host ""
        Write-Err "The archive's SHA-256 hash does not match the signed hash."
        Write-Wrn "The file may have been corrupted, partially overwritten,"
        Write-Wrn "or deliberately tampered with."
        Write-Log "Verify FAILED (hash mismatch) '$archiveName'" "ERROR"
        return $false
    }

    if ($Verbose) { Write-OK "Hash matches stored value."; Write-Inf "Step 2/3 — Locating signing certificate..." }

    # ── Look up the certificate ───────────────────────────────
    $cert = Get-CertByThumbprint $sidecar.thumbprint
    if (-not $cert) {
        Write-Host ""
        Write-Wrn "═══════════════════════════════════════════════"
        Write-Wrn " CERTIFICATE NOT FOUND IN LOCAL STORE          "
        Write-Wrn "═══════════════════════════════════════════════"
        Write-Host ""
        Write-Wrn "Thumbprint : $($sidecar.thumbprint)"
        Write-Wrn "Signer     : $($sidecar.signer)"
        Write-Host ""
        Write-Wrn "The signing certificate is not in your Certificate Store."
        Write-Inf "Options:"
        Write-Inf " A) Import the signer's .cer public key (option [29] → [3])"
        Write-Inf "    then re-run verification."
        Write-Inf " B) If you are the original signer, restore your .pfx backup"
        Write-Inf "    (option [29] → [3])."
        Write-Host ""
        Write-Inf "NOTE: The archive's SHA-256 hash DID match its stored value."
        Write-Inf "      The file has not been corrupted — only signature trust"
        Write-Inf "      cannot be established without the public key."
        Write-Log "Verify INCONCLUSIVE (cert missing) '$archiveName' thumbprint=$($sidecar.thumbprint)" "WARN"
        return $false
    }

    if ($Verbose) {
        Write-OK "Certificate found: $($cert.Subject)"
        Write-Inf "Step 3/3 — Verifying RSA signature..."
    }

    # ── Verify RSA signature ──────────────────────────────────
    try {
        $hashBytes = [byte[]]( ($currentHash -split '(?<=\G..)' | Where-Object { $_ }) |
                        ForEach-Object { [Convert]::ToByte($_, 16) } )
        $sigBytes  = [Convert]::FromBase64String($sidecar.signature)

        $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($cert)
        if (-not $rsa) { $rsa = $cert.PublicKey.Key }

        $valid = $rsa.VerifyHash(
            $hashBytes,
            $sigBytes,
            [System.Security.Cryptography.HashAlgorithmName]::SHA256,
            [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
        )

        Write-Host ""
        if ($valid) {
            Write-Host "  ╔═══════════════════════════════════════════════╗" -ForegroundColor Green
            Write-Host "  ║  ✔  SIGNATURE VALID — ARCHIVE IS AUTHENTIC   ║" -ForegroundColor Green
            Write-Host "  ╚═══════════════════════════════════════════════╝" -ForegroundColor Green
            Write-Host ""
            Write-OK "Archive     : $archiveName"
            Write-OK "Signed by   : $($sidecar.signer)"
            Write-OK "Signed at   : $($sidecar.signed_at)"
            Write-OK "Certificate : $($cert.Subject)"
            Write-Host ""
            Write-Inf "This archive has not been modified since it was signed."
            Write-Log "Verify PASSED '$archiveName' cert=$($cert.Thumbprint)" "OK"
            return $true
        } else {
            Write-Host "  ╔═══════════════════════════════════════════════╗" -ForegroundColor Red
            Write-Host "  ║  ✘  SIGNATURE INVALID — DO NOT TRUST FILE    ║" -ForegroundColor Red
            Write-Host "  ╚═══════════════════════════════════════════════╝" -ForegroundColor Red
            Write-Host ""
            Write-Err "The RSA signature is INVALID."
            Write-Wrn "The hash matched but the signature did not verify against"
            Write-Wrn "the public key — this may indicate the .sig.json was"
            Write-Wrn "replaced or that a different key was used to re-sign."
            Write-Log "Verify FAILED (bad signature) '$archiveName' cert=$($cert.Thumbprint)" "ERROR"
            return $false
        }
    } catch {
        Write-Err "Signature verification error: $_"
        Write-Log "Verify ERROR '$archiveName' | $_" "ERROR"
        return $false
    }
}

# ================================================================
#  BATCH VERIFICATION
# ================================================================

function Invoke-BatchVerify {
    Write-Header "BATCH VERIFY — Scan folder for signed archives"

    Write-Inf "Select folder to scan for signed archives..."
    $folder = Select-FolderDialog -Description "Select folder to scan"
    if (-not $folder) { Write-Wrn "Cancelled."; Pause-Menu; return }

    $recurse = Confirm-Action "Include sub-folders?"

    $getParams = @{ Path = $folder; Filter = "*.sig.json"; ErrorAction = "SilentlyContinue" }
    if ($recurse) { $getParams["Recurse"] = $true }

    $sigFiles = Get-ChildItem @getParams
    if (-not $sigFiles -or $sigFiles.Count -eq 0) {
        Write-Wrn "No .sig.json sidecar files found in: $folder"
        Write-Inf "Only signed archives have a corresponding .sig.json file."
        Pause-Menu; return
    }

    Write-Inf "Found $($sigFiles.Count) signed archive(s) to verify."
    Write-Host ""

    $passed   = 0
    $failed   = 0
    $missing  = 0
    $results  = @()

    foreach ($sigFile in $sigFiles) {
        $archivePath = $sigFile.FullName -replace '\.sig\.json$', ''
        $archiveName = Split-Path $archivePath -Leaf
        Write-Host "  Checking: $archiveName" -ForegroundColor Cyan -NoNewline

        if (-not (Test-Path $archivePath)) {
            Write-Host "  [ARCHIVE MISSING]" -ForegroundColor Yellow
            $missing++
            $results += [pscustomobject]@{ File=$archiveName; Status="ARCHIVE MISSING"; Detail="Archive file not found" }
            continue
        }

        # Suppress verbose output; capture result
        $valid = Verify-ArchiveSignature -ArchivePath $archivePath -SigPath $sigFile.FullName

        if ($valid) {
            Write-Host "  [VALID]"   -ForegroundColor Green
            $passed++
            $results += [pscustomobject]@{ File=$archiveName; Status="VALID"; Detail="Signature OK" }
        } else {
            Write-Host "  [FAILED]"  -ForegroundColor Red
            $failed++
            $results += [pscustomobject]@{ File=$archiveName; Status="FAILED"; Detail="See log for details" }
        }
    }

    Write-Host ""
    Write-Section "BATCH VERIFY SUMMARY"
    Write-Host "  Total checked : $($sigFiles.Count)" -ForegroundColor White
    Write-OK   "  Valid         : $passed"
    if ($failed  -gt 0) { Write-Err "  Failed        : $failed" }
    if ($missing -gt 0) { Write-Wrn "  Archive missing: $missing" }

    Write-Log "Batch verify: $passed passed, $failed failed, $missing missing in '$folder'" `
        $(if ($failed -gt 0) { "WARN" } else { "OK" })

    if (Confirm-Action "Export results to CSV?") {
        $csvPath = Join-Path $folder "verify_report_$(Get-Date -Format 'yyyy-MM-dd_HH-mm').csv"
        $results | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
        Write-OK "Report saved: $csvPath"
    }
    Pause-Menu
}

# ================================================================
#  AUTO-SIGN HELPER  (call from compression functions)
# ================================================================

function Auto-SignAfterCompress {
    <#
    .SYNOPSIS
        Prompts the user to sign a newly created archive.
        Designed to be called at the end of compression functions.
    .PARAMETER ArchivePath
        Full path to the archive that was just created.
    #>
    param([Parameter(Mandatory)][string]$ArchivePath)

    if (-not (Test-Path $ArchivePath)) { return }
    if (-not (Confirm-Action "Sign this archive with a certificate?")) { return }

    $cert = Select-SigningCert
    if (-not $cert) { return }

    Sign-Archive -ArchivePath $ArchivePath -Cert $cert -Verbose
}

# ================================================================
#  SIGN + VERIFY IMMEDIATELY  (trust-on-creation workflow)
# ================================================================

function Invoke-SignAndVerify {
    <#
    .SYNOPSIS
        Signs an archive and immediately verifies the signature —
        the fastest way to confirm the sign workflow is working.
    #>
    Write-Header "SIGN AND IMMEDIATELY VERIFY"

    Write-Inf "Select archive..."
    $archiveFile = Select-FileDialog -Title "Select archive" `
        -Filter "Archives (*.7z;*.zip;*.rar;*.tar;*.tar.gz)|*.7z;*.zip;*.rar;*.tar;*.tar.gz|All Files (*.*)|*.*"
    if (-not $archiveFile) { Write-Wrn "Cancelled."; Pause-Menu; return }

    $cert = Select-SigningCert
    if (-not $cert) { Pause-Menu; return }

    Write-Host ""
    Write-Section "SIGNING"
    $sigPath = Sign-Archive -ArchivePath $archiveFile -Cert $cert -Verbose
    if (-not $sigPath) { Pause-Menu; return }

    Write-Host ""
    Write-Section "IMMEDIATE VERIFICATION"
    Write-Inf "Verifying signature just created..."
    $valid = Verify-ArchiveSignature -ArchivePath $archiveFile -SigPath $sigPath -Verbose

    if ($valid) {
        Write-Host ""
        Write-OK "Sign + verify cycle completed successfully."
        Write-Inf "The .sig.json sidecar file should always travel with the archive."
    }
    Pause-Menu
}

# ================================================================
#  MAIN MENU ADDITIONS
# ================================================================
#
#  In Show-MainMenu, add a new SECURITY section:
#
#    Write-Section "SECURITY — ARCHIVE SIGNING"
#    Write-Host "  [29] Certificates  ► Manage signing certificates"     -ForegroundColor Magenta
#    Write-Host "  [30] Sign Archive  ► Sign an archive with a cert"     -ForegroundColor Magenta
#    Write-Host "  [31] Verify        ► Verify an archive signature"     -ForegroundColor Magenta
#    Write-Host "  [32] Batch Verify  ► Verify all signed archives in folder" -ForegroundColor Magenta
#    Write-Host "  [33] Sign+Verify   ► Sign then immediately verify"    -ForegroundColor Magenta
#
#  In the do/while switch, add:
#
#    "29" { Invoke-ManageCerts      }
#    "30" { Invoke-SignArchive       }
#    "31" { Invoke-VerifySignature   }
#    "32" { Invoke-BatchVerify       }
#    "33" { Invoke-SignAndVerify     }
#
#  Update Read-Host to [1-33] and Exit to "33" → "35" etc.
#
# ================================================================
#  AUTO-SIGN INTEGRATION (optional)
# ================================================================
#
#  To sign automatically after compression, add this at the end
#  of Invoke-7ZipBrowser and Invoke-7ZipManualPath, just before
#  Pause-Menu, inside the   if ($LASTEXITCODE -eq 0) { ... }   block:
#
#    # Optional: auto-sign after compression
#    if ($script:Config.AutoSign -eq $true) {
#        Auto-SignAfterCompress -ArchivePath $outFile
#    } else {
#        if (Confirm-Action "Sign this archive with a certificate?") {
#            Auto-SignAfterCompress -ArchivePath $outFile
#        }
#    }
#
# ================================================================
