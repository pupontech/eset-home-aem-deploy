<#
.SYNOPSIS
    Standalone installer for ESET home products - run manually on a Windows
    machine, no Splashtop AEM needed. Double-click a .cmd launcher in this
    folder, or run directly:
        powershell -ExecutionPolicy Bypass -File .\Install-ESET-HOME.ps1 -Product Ultimate

.PARAMETER Product
    Which ESET product to install:
      Ultimate  -> ESET Security Ultimate (esu_nt64.exe)
      Essential -> ESET NOD32 Antivirus (eav_nt64.exe)
    Default: Ultimate.

.PARAMETER LicenseKey
    Optional activation key. If omitted, you are prompted. Pressing Enter
    with no key installs unactivated (activate later in ESET HOME).

.PARAMETER NoPause
    Skip the "press Enter to close" prompt at the end (useful when this
    script is itself called from another script).

.EXAMPLE
    .\Install-ESET-HOME.ps1 -Product Essential
    .\Install-ESET-HOME.ps1 -Product Ultimate -LicenseKey ABCD-EFGH-IJKL-MNOP-QRST

.NOTES
    - Requires elevation; the script re-launches itself as administrator
      if it isn't already (a UAC prompt appears once).
    - Idempotent: if ESET is already installed it reports that and exits 0.
    - Exit codes: 0 = success (installed, already installed, or 3010
      reboot-required). Non-zero = failure.
    - Log: C:\Windows\Temp\ESETDeploy\eset_standalone_<product>_install.log
#>

[CmdletBinding()]
param(
    [ValidateSet("Ultimate", "Essential")]
    [string]$Product = "Ultimate",
    [string]$LicenseKey = "",
    [switch]$NoPause
)

# ================= CONFIGURATION =================
# How the key is handed to the installer (only used when a real key is set).
# VERIFY on your build: run the downloaded exe manually with --help (or /?)
# and check the accepted parameters. ESET no longer publicly documents the
# key-at-install switch for current home bootstrappers, so adjust this to
# match your build if needed, e.g. "--license-key {0}" or
# "--msi-property-ehs ACTIVATION_DATA=key:{0}".
$LicenseArg = "--msi-property-ehs ADDLICENSE_LICENSE_KEY={0}"

$MinSizeBytes = 10MB          # sanity floor; real package is ~90 MB
$WorkDir      = "C:\Windows\Temp\ESETDeploy"

switch ($Product) {
    "Ultimate" {
        $ProductName   = "ESET Security Ultimate (ESET HOME Security Ultimate)"
        $InstallerURL  = "https://download.eset.com/com/eset/apps/home/esu/windows/latest/esu_nt64.exe"
        $InstallerName = "eset_home_ultimate_installer.exe"
        $LogFile       = Join-Path $WorkDir "eset_standalone_ultimate_install.log"
    }
    "Essential" {
        $ProductName   = "ESET HOME Security Essential (ESET NOD32 Antivirus)"
        $InstallerURL  = "https://download.eset.com/com/eset/apps/home/eav/windows/latest/eav_nt64.exe"
        $InstallerName = "eset_home_essential_installer.exe"
        $LogFile       = Join-Path $WorkDir "eset_standalone_essential_install.log"
    }
}
# ===================================================

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $LogFile -Append -Encoding utf8
    Write-Host $Message
}

function Test-IsAdmin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

try {
    # --- Self-elevate if needed ---
    if (-not (Test-IsAdmin)) {
        Write-Host ""
        Write-Host "ESET installer needs administrator rights." -ForegroundColor Yellow
        Write-Host "A UAC prompt will appear - please click Yes." -ForegroundColor Yellow
        $argList = @(
            "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-File", "`"$($MyInvocation.MyCommand.Path)`"",
            "-Product", $Product
        )
        if ($LicenseKey) { $argList += @("-LicenseKey", $LicenseKey) }
        if ($NoPause)    { $argList += "-NoPause" }
        Start-Process -FilePath (Join-Path $PSHOME "powershell.exe") -ArgumentList $argList -Verb RunAs -Wait
        exit 0
    }

    if (-not (Test-Path $WorkDir)) {
        New-Item -Path $WorkDir -ItemType Directory -Force | Out-Null
    }

    Write-Host ""
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "  $ProductName - standalone installer" -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Log "=== $ProductName standalone deployment started ==="

    # --- Already installed? Report and exit 0 (idempotent re-run) ---
    $alreadyInstalled = (Test-Path "C:\Program Files\ESET\ESET Security\ecmd.exe") -or `
                        [bool](Get-Service -Name "ekrn*" -ErrorAction SilentlyContinue)
    if ($alreadyInstalled) {
        Write-Log "ESET is already installed on this machine - nothing to do."
        Write-Host ""
        Write-Host "ESET is already installed on this machine." -ForegroundColor Green
        Write-Host "If it is not yet activated, add the key in ESET HOME (login.eset.com)" -ForegroundColor Yellow
        Write-Host "or in the product UI (Help and support -> Change license)." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Result: ESET already installed - no changes made." -ForegroundColor Green
        Write-Host "Log: $LogFile"
        if (-not $NoPause) { Read-Host "Press Enter to close" }
        exit 0
    }

    # --- License key: prompt if not given ---
    if (-not $LicenseKey) {
        $answer = Read-Host "Enter ESET license key, or press Enter to install unactivated (activate later in ESET HOME)"
        $LicenseKey = $answer.Trim()
    }
    $useKey = ($LicenseKey -ne "") -and -not ($LicenseKey -match '^X{4}')

    # --- Download ---
    # TLS 1.2 pin: Windows PowerShell 5.1 on older builds may not negotiate it by default.
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $InstallerPath = Join-Path $WorkDir $InstallerName
    Write-Host ""
    Write-Host "Downloading installer (~90 MB)... this can take a few minutes." -ForegroundColor Yellow
    Write-Log "Downloading installer from $InstallerURL"
    try {
        Invoke-WebRequest -Uri $InstallerURL -OutFile $InstallerPath -UseBasicParsing
    } catch {
        Write-Log "ERROR: Download failed - $($_.Exception.Message)"
        Write-Host ""
        Write-Host "FAILED: download error (see log)." -ForegroundColor Red
        if (-not $NoPause) { Read-Host "Press Enter to close" }
        exit 1
    }

    if (-not (Test-Path $InstallerPath)) {
        Write-Log "ERROR: Installer not found after download."
        Write-Host "FAILED: installer file missing after download." -ForegroundColor Red
        if (-not $NoPause) { Read-Host "Press Enter to close" }
        exit 1
    }

    # Guard against truncated/partial downloads being executed.
    $fileSize = (Get-Item $InstallerPath).Length
    if ($fileSize -lt $MinSizeBytes) {
        Write-Log "ERROR: Downloaded file is only $fileSize bytes (expected > $MinSizeBytes). Aborting."
        Write-Host "FAILED: downloaded file looks truncated ($fileSize bytes)." -ForegroundColor Red
        if (-not $NoPause) { Read-Host "Press Enter to close" }
        exit 1
    }
    Write-Host "Download complete: $([math]::Round($fileSize / 1MB, 1)) MB" -ForegroundColor Green

    # --- Build install arguments ---
    $installArgs = @("--silent", "--accepteula")
    if ($useKey) {
        $keyArg = $LicenseArg -f $LicenseKey
        $installArgs += ($keyArg -split ' ')
        # Log the command WITHOUT the key itself (log files are readable by anyone on the box).
        $redacted = ($installArgs | ForEach-Object { $_ -replace [regex]::Escape($LicenseKey), "<KEY>" }) -join " "
        Write-Log "License key supplied; running silent install with activation."
        Write-Log "Install command: $InstallerName $redacted"
    } else {
        Write-Log "No license key entered; installing unactivated."
        Write-Log "Activate afterwards in ESET HOME (login.eset.com) or per KB2792."
    }

    # --- Silent install ---
    Write-Host ""
    Write-Host "Installing $ProductName silently - please wait..." -ForegroundColor Yellow
    $process  = Start-Process -FilePath $InstallerPath -ArgumentList $installArgs -Wait -PassThru -NoNewWindow
    $exitCode = $process.ExitCode

    if ($exitCode -eq 0) {
        Write-Host "$ProductName installed successfully." -ForegroundColor Green
    } elseif ($exitCode -eq 3010) {
        Write-Host "$ProductName installed successfully - reboot required (exit code 3010)." -ForegroundColor Green
        Write-Log "$ProductName installed successfully; reboot required (exit code 3010). Counting as success."
    } else {
        Write-Log "ERROR: Installer exited with code $exitCode"
        if ($useKey) {
            Write-Log "HINT: if this build rejects the license switch, verify the exact"
            Write-Log "      property name (run the exe with --help) and update `$LicenseArg,"
            Write-Log "      or run again without a key and activate via the ESET HOME portal."
        }
        Write-Host ""
        Write-Host "FAILED: installer exited with code $exitCode" -ForegroundColor Red
        if (-not $NoPause) { Read-Host "Press Enter to close" }
        exit $exitCode
    }

    # --- Post-install status (informational; does not change exit code) ---
    $ecmdPath = "C:\Program Files\ESET\ESET Security\ecmd.exe"
    if (Test-Path $ecmdPath) {
        Write-Log "Post-install status via ecmd (informational):"
        & "$ecmdPath" /getstatus | Out-File -FilePath $LogFile -Append -Encoding utf8
        if ($useKey) {
            Write-Host ""
            Write-Host "Important: confirm the license actually activated" -ForegroundColor Yellow
            Write-Host "(check the product UI or the ecmd status above). Exit code 0 alone" -ForegroundColor Yellow
            Write-Host "does not prove the key was accepted." -ForegroundColor Yellow
        }
    }

    Write-Host ""
    Write-Host "Result: SUCCESS" -ForegroundColor Green
    Write-Host "Log: $LogFile"
    Write-Log "=== Deployment finished successfully ==="
    if (-not $NoPause) { Read-Host "Press Enter to close" }
    exit 0

} catch {
    Write-Log "FATAL ERROR: $($_.Exception.Message)"
    Write-Host ""
    Write-Host "FAILED with an unexpected error (see log)." -ForegroundColor Red
    if (-not $NoPause) { Read-Host "Press Enter to close" }
    exit 1
}
