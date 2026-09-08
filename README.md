# ESET Home Deployment for Splashtop AEM

PowerShell scripts that silently install ESET home security products on Windows machines via [Splashtop AEM](https://www.splashtop.com/aem) (Script Task deployment, run as SYSTEM).

Two variants, one per product:

| Script | Product | Installer |
|---|---|---|
| `Install-ESET-HOME-Ultimate.ps1` | ESET Security Ultimate | `esu_nt64.exe` |
| `Install-ESET-HOME-Essential.ps1` | ESET NOD32 Antivirus (Essential line) | `eav_nt64.exe` |

Both download from ESET's official "latest" offline-installer URLs (verified live, ~90 MB each, sourced from [ESET KB2885](https://support.eset.com/en/kb2885-download-and-install-eset-offline-or-install-older-versions-of-eset-products)) and install silently with the ESET-confirmed bootstrapper switches `--silent --accepteula`.

## How it works

1. **Converge** - if any ESET home product is already installed, the script uninstalls it first via ESET's own `callmsi.exe` (the vendor wrapper around msiexec, `callmsi.exe /x {product-code} /qb! REBOOT=ReallySuppress`), waits for removal to clear, then proceeds. A re-run always ends on whatever version this script deploys - no "already installed, skip" behavior. If no product code can be found for the detected install, the script aborts rather than install over a half-removed ESET.
2. **Download** - grabs the current offline installer (TLS 1.2 pinned, size-checked so a truncated file is never executed).
3. **Install** - runs silently as SYSTEM.
4. **Verify** - logs post-install status via `ecmd /getstatus` (informational).
5. Exit codes: `0` = success (installed or `3010` reboot-required). Non-zero = failure, surfaced in AEM task status.

Note: uninstalling ESET drops its activation. After a converge run, the license must be re-applied (the script's key at install time, or re-activate in ESET HOME).

Logs go to `C:\Windows\Temp\ESETDeploy\` (`eset_ultimate_install.log` / `eset_essential_install.log`).

## License key: two modes

Each script has a `$LicenseKey` placeholder near the top:

```powershell
$LicenseKey = "XXXX-XXXX-XXXX-XXXX-XXXX"
```

**Mode 1 - no key (ESET HOME portal):** leave the placeholder as-is. The product installs unactivated; activate the seat in ESET HOME at <https://login.eset.com> (Add protection) or per [KB2792](https://support.eset.com/en/kb2792-activate-my-eset-windows-home-product-using-my-username-password-or-license-key). An ESET HOME account is mandatory for subscriptions purchased after Nov 15, 2023 ([KB3419](https://support.eset.com/en/kb3419-download-and-install-eset-home-security-products-for-windows)).

**Mode 2 - license key at install time:** put your real key in `$LicenseKey`. The script hands it to the installer via `$LicenseArg` (default: `--msi-property-ehs ADDLICENSE_LICENSE_KEY=<key>`), logs the command with the key redacted, and reminds you to confirm activation actually landed.

> **Verify before fleet push.** ESET no longer publicly documents the key-at-install switch for current home bootstrappers, so the exact property name can vary by build. Test on one machine first: run the downloaded exe manually with `--help` (or `/?`), check what your build accepts, and adjust `$LicenseArg` in the script if needed. Exit code `0` alone does **not** prove the key activated - confirm in the product UI or in the `ecmd /getstatus` log output. The key is never written to the log in plaintext.

## Standalone version (no AEM)

Need to install on a machine you're sitting at, without Splashtop AEM? Use the `standalone/` folder:

```
standalone/
  Install-ESET-HOME-Ultimate.cmd    <- double-click (ESET Security Ultimate)
  Install-ESET-HOME-Essential.cmd   <- double-click (ESET NOD32 Antivirus)
  Install-ESET-HOME.ps1             <- shared logic behind both launchers
```

What's different from the AEM scripts:

- **Self-elevating** - one UAC prompt, then it runs as admin. No need to right-click "Run as administrator".
- **Interactive key prompt** - you're asked for the license key in the console; press Enter with no key to install unactivated (activate later in ESET HOME).
- **Existing ESET confirm** - if an ESET product is already installed you're asked "Uninstall existing ESET and continue? (Y/N)"; answering Y removes it via ESET's own `callmsi.exe` first, then installs the chosen product (converge behavior, same as the AEM scripts). N cancels with no changes.
- **Human-friendly output** - colored status lines and a "Press Enter to close" pause so the window doesn't vanish. Add `-NoPause` to skip that.
- Same download/install/verify logic, same converge behavior, same exit codes. Logs to `C:\Windows\Temp\ESETDeploy\eset_standalone_<product>_install.log`.

Direct usage:

```powershell
powershell -ExecutionPolicy Bypass -File .\standalone\Install-ESET-HOME.ps1 -Product Ultimate
powershell -ExecutionPolicy Bypass -File .\standalone\Install-ESET-HOME.ps1 -Product Essential -LicenseKey ABCD-EFGH-IJKL-MNOP-QRST
```

The same key-at-install caveat applies as above: verify `$LicenseArg` against your build before trusting a fleet of manual installs.

## Deployment checklist (Splashtop AEM)

- Task type: Script Task (PowerShell)
- Run as: **SYSTEM** (required for install permissions)
- Target: the device group
- Test on 1-2 machines before fleet push

Prerequisites:

- x64 Windows only (ARM64 and 32-bit are not handled).
- Prior antivirus should be removed first; ESET lists that as an install prerequisite ([KB3419](https://support.eset.com/en/kb3419-download-and-install-eset-home-security-products-for-windows)). The scripts do not uninstall other AV products.

## Testing on a VM

`TEST-RUN.bat` runs either script (or both back-to-back) from an elevated CMD and prints the exit code plus the full log. `TEST-CHECKLIST.txt` has the pass/fail criteria, including how to verify key-at-install activation and what to report back if a build rejects the key switch.

## Maintenance

The two scripts are near-identical by design. When changing shared logic, edit **both** files - they should differ only in product name, installer URL/filename, and log filename.

## Credits / requirements

- Uses only built-in Windows PowerShell (no third-party libraries).
- Installer URLs and unattended-switch behavior are per ESET's official KBs and ESET staff guidance on the [ESET Security Forum](https://forum.eset.com/topic/13565-v11-msi-silent-install-fails/) (topic 13565).
