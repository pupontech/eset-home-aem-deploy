<#
.SYNOPSIS
    Silently installs ESET HOME Security Ultimate (ESET Security Ultimate),
    optionally activating it with a license key at install time.
    Designed for deployment through Splashtop AEM (Script/Task deployment, run as SYSTEM).

.NOTES
    - x64 only. Downloads ESET's official offline installer (verified live, per KB2885).
    - Unattended base syntax is the ESET-confirmed bootstrapper form: --silent --accepteula
      (per ESET staff on forum.eset.com topic 13565).
    - LICENSE KEY: set $LicenseKey below. If it is still the XXXX placeholder, the product
      installs unactivated and you activate seats in ESET HOME (login.eset.com) per KB3419.
      If a real key is set, it is passed to the installer via $LicenseArg below.
      IMPORTANT: ESET no longer publicly documents the key-at-install switch for current
      home bootstrappers, so VERIFY the exact property name on your build BEFORE fleet push:
      run the downloaded exe once manually with --help (or /?) on a test VM and check the
      log line "installer accepted arguments" in TEST-CHECKLIST.txt. Adjust $LicenseArg to
      match whatever your build accepts; the script logs the full command it ran.
    - EXISTING ESET: if any ESET home product is already installed, the script first
      uninstalls it and then installs the pushed product, so a re-run always
      converges to whatever version this script is deploying. Uninstall uses ESET's
      own callmsi.exe when found (searched in the product's install location and
      every ESET folder under Program Files); if absent it falls back to the
      standard msiexec /x uninstall of the registered MSI product code.
    - Exit codes: 0 = success (installed, or 3010 reboot-required).
      Non-zero = failure (surfaces in AEM task status).
    - Log: C:\Windows\Temp\ESETDeploy\eset_ultimate_install.log
#>

# ================= CONFIGURATION =================
$ProductName    = "ESET Security Ultimate (ESET HOME Security Ultimate)"
$InstallerURL   = "https://download.eset.com/com/eset/apps/home/esu/windows/latest/esu_nt64.exe"
$InstallerName  = "eset_home_ultimate_installer.exe"

# Put your real license key here, or leave the placeholder to install unactivated
# (activation then happens in the ESET HOME portal).
$LicenseKey     = "XXXX-XXXX-XXXX-XXXX-XXXX"

# How the key is handed to the installer. Only used when $LicenseKey is not the
# placeholder. VERIFY on your build (see .NOTES) and adjust if your installer
# wants a different property name, e.g. "--license-key <key>" or
# "--msi-property-ehs ACTIVATION_DATA=key:<key>".
$LicenseArg     = "--msi-property-ehs ADDLICENSE_LICENSE_KEY={0}"

$MinSizeBytes   = 10MB          # sanity floor; real package is ~90 MB
$WorkDir        = "C:\Windows\Temp\ESETDeploy"
$LogFile        = Join-Path $WorkDir "eset_ultimate_install.log"
# ===================================================

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $LogFile -Append -Encoding utf8
    Write-Host "$timestamp - $Message"
}

function Get-ESETUninstallEntries {
    # Read uninstall registry keys WITHOUT Get-ItemProperty, which throws
    # "Specified cast is not valid" (InvalidCastException) on registry values
    # with unusual types (REG_NONE etc.) that exist on some machines. The
    # RegistryKey.GetValue() method returns raw objects and never casts.
    $entries = @()
    $bases = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    foreach ($base in $bases) {
        $subkeys = Get-ChildItem -Path $base -ErrorAction SilentlyContinue
        foreach ($sub in $subkeys) {
            if ($sub.PSChildName -notmatch '^\{[0-9A-Fa-f-]+\}$') { continue }
            try {
                $displayName = $sub.GetValue("DisplayName")
                $publisher   = $sub.GetValue("Publisher")
            } catch {
                continue
            }
            if ($displayName -like "ESET*" -and $publisher -like "*ESET*") {
                $entries += [pscustomobject]@{
                    DisplayName    = [string]$displayName
                    PSChildName    = $sub.PSChildName
                    InstallLocation = $sub.GetValue("InstallLocation")
                }
            }
        }
    }
    return $entries
}

# Uninstall every installed ESET home product found, via ESET's own callmsi.exe
# (the vendor wrapper around msiexec). Aborts the script on failure: installing
# over a half-removed ESET is worse than stopping. Only called when an ESET
# install was detected, so "no product code found" is treated as fatal.
function Remove-ExistingESET {
    $entries = Get-ESETUninstallEntries

    if (-not $entries) {
        Write-Log "ERROR: ESET install detected but no MSI product code found in the registry;"
        Write-Log "       cannot uninstall cleanly. Aborting to avoid installing over it."
        exit 1
    }

    foreach ($entry in $entries) {
        $productCode = $entry.PSChildName
        $displayName = $entry.DisplayName
        Write-Log "Uninstalling existing $displayName ($productCode)..."

        # Locate ESET's callmsi.exe (its own msiexec wrapper): check the
        # product's InstallLocation and every ESET folder under Program Files,
        # not just one hardcoded path - the folder name varies by product/era.
        $callmsi = $null
        $searchDirs = @(
            "C:\Program Files\ESET",
            "C:\Program Files (x86)\ESET"
        )
        if ($entry.InstallLocation) {
            $searchDirs += $entry.InstallLocation
        }
        foreach ($dir in $searchDirs) {
            if (Test-Path $dir) {
                $found = Get-ChildItem -Path $dir -Recurse -Filter "callmsi.exe" -ErrorAction SilentlyContinue |
                    Select-Object -First 1
                if ($found) {
                    $callmsi = $found.FullName
                    break
                }
            }
        }

        if ($callmsi) {
            Write-Log "Uninstalling via ESET callmsi.exe: $callmsi"
            $p = Start-Process -FilePath $callmsi -ArgumentList @("/x", $productCode, "/qb!", "REBOOT=ReallySuppress") -Wait -PassThru -NoNewWindow
        } else {
            # Fallback: callmsi is itself a wrapper around msiexec; /x with the
            # registered MSI product code performs the same standard uninstall.
            Write-Log "callmsi.exe not found; falling back to msiexec /x for the registered product code."
            $msiexec = Join-Path $env:windir "System32\msiexec.exe"
            $p = Start-Process -FilePath $msiexec -ArgumentList @("/x", $productCode, "/qb!", "REBOOT=ReallySuppress") -Wait -PassThru -NoNewWindow
        }
        $code = $p.ExitCode
        # 0 = success, 3010 = success+reboot needed, 1605 = already gone
        if ($code -in 0, 3010, 1605) {
            Write-Log "Uninstall of $displayName finished (exit $code)."
        } else {
            Write-Log "ERROR: uninstall of $displayName failed with exit code $code. Aborting to avoid installing over it."
            exit $code
        }
    }

    # Give the removal a moment to fully clear services/files before reinstalling.
    $deadline = (Get-Date).AddSeconds(60)
    $stillThere = $true
    while ($stillThere -and (Get-Date) -lt $deadline) {
        $stillThere = [bool](Get-Service -Name "ekrn*" -ErrorAction SilentlyContinue) -or
                      (Test-Path "C:\Program Files\ESET\ESET Security\ekrn.exe")
        if ($stillThere) { Start-Sleep -Seconds 5 }
    }
    if ($stillThere) {
        Write-Log "WARNING: ESET services still present after uninstall (may clear on reboot). Continuing."
    } else {
        Write-Log "ESET removal confirmed: no ekrn service remaining."
    }
    return $true
}

try {
    if (-not (Test-Path $WorkDir)) {
        New-Item -Path $WorkDir -ItemType Directory -Force | Out-Null
    }

    Write-Log "=== $ProductName deployment started ==="

    # --- Existing ESET? Uninstall it first, then install whatever version is pushed ---
    $alreadyInstalled = (Test-Path "C:\Program Files\ESET\ESET Security\ecmd.exe") -or `
                        [bool](Get-Service -Name "ekrn*" -ErrorAction SilentlyContinue)
    if ($alreadyInstalled) {
        Write-Log "Existing ESET product detected - uninstalling it before installing $ProductName."
        Remove-ExistingESET | Out-Null
        Write-Log "Proceeding with fresh install of $ProductName."
    } else {
        Write-Log "No existing ESET installation detected - proceeding with fresh install."
    }

    # --- Download ---
    # TLS 1.2 pin: Windows PowerShell 5.1 as SYSTEM on older builds may not negotiate it by default.
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $InstallerPath = Join-Path $WorkDir $InstallerName
    Write-Log "Downloading installer from $InstallerURL"
    try {
        Invoke-WebRequest -Uri $InstallerURL -OutFile $InstallerPath -UseBasicParsing
    } catch {
        Write-Log "ERROR: Download failed - $($_.Exception.Message)"
        exit 1
    }

    if (-not (Test-Path $InstallerPath)) {
        Write-Log "ERROR: Installer not found after download."
        exit 1
    }

    # Guard against truncated/partial downloads being executed as SYSTEM.
    $fileSize = (Get-Item $InstallerPath).Length
    if ($fileSize -lt $MinSizeBytes) {
        Write-Log "ERROR: Downloaded file is only $fileSize bytes (expected > $MinSizeBytes). Aborting."
        exit 1
    }
    Write-Log "Download complete: $fileSize bytes."

    # --- Build install arguments ---
    $installArgs = @("--silent", "--accepteula")

    $useKey = -not ($LicenseKey -match '^X{4}')
    if ($useKey) {
        $keyArg = $LicenseArg -f $LicenseKey
        $installArgs += ($keyArg -split ' ')
        # Log the command WITHOUT the key itself (log files are readable by anyone on the box).
        $redacted = ($installArgs | ForEach-Object { $_ -replace [regex]::Escape($LicenseKey), '<KEY>' }) -join ' '
        Write-Log "License key supplied; running silent install with activation."
        Write-Log "Install command: $InstallerName $redacted"
    } else {
        Write-Log "No license key set (placeholder); installing unactivated."
        Write-Log "Install command: $InstallerName --silent --accepteula"
        Write-Log "Activate afterwards in ESET HOME (login.eset.com) or per KB2792."
    }

    # --- Silent install ---
    $process  = Start-Process -FilePath $InstallerPath -ArgumentList $installArgs -Wait -PassThru -NoNewWindow
    $exitCode = $process.ExitCode

    if ($exitCode -eq 0) {
        Write-Log "$ProductName installed successfully."
    } elseif ($exitCode -eq 3010) {
        Write-Log "$ProductName installed successfully; reboot required (exit code 3010). Counting as success."
    } else {
        Write-Log "ERROR: Installer exited with code $exitCode"
        if ($useKey) {
            Write-Log "HINT: if this build rejects the license switch, verify the exact"
            Write-Log "      property name (run the exe with --help) and update `$LicenseArg,"
            Write-Log "      or clear `$LicenseKey and activate via the ESET HOME portal."
        }
        exit $exitCode
    }

    # --- Post-install status (informational; does not change exit code) ---
    $ecmdPath = "C:\Program Files\ESET\ESET Security\ecmd.exe"
    if (Test-Path $ecmdPath) {
        Write-Log "Post-install status via ecmd (informational):"
        & "$ecmdPath" /getstatus | Out-File -FilePath $LogFile -Append -Encoding utf8
        if ($useKey) {
            Write-Log "REMINDER: check the ecmd output / product UI to CONFIRM the key actually"
            Write-Log "          activated. Exit code 0 alone does not prove activation landed."
        }
    }

    Write-Log "=== Deployment finished successfully ==="
    exit 0

} catch {
    Write-Log "FATAL ERROR: $($_.Exception.Message)"
    exit 1
}
