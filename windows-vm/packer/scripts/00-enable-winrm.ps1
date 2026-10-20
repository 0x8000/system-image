param()

# This script runs unattended during first logon, and nothing can report a
# failure: there is no WinRM yet, so a throw here is invisible and the build
# just times out 30 minutes later. Every step therefore logs and continues.
#
# `$ErrorActionPreference = "Stop"` is deliberately absent. `winrm set` returns
# a non-zero exit code before the service is configured, and under Stop that
# aborted the script before the very line that enables WinRM.
$log = "C:\winrm-setup.log"
function Write-Step {
  param([string]$Message)
  "$(Get-Date -Format o) $Message" | Out-File -FilePath $log -Append -Encoding utf8
}

Write-Step "bootstrap start"

# 1. The service has to exist and run before any configuration command means
#    anything.
Set-Service -Name WinRM -StartupType Automatic -ErrorAction SilentlyContinue
Start-Service -Name WinRM -ErrorAction SilentlyContinue
Write-Step "winrm service: $((Get-Service WinRM -ErrorAction SilentlyContinue).Status)"

# 2. quickconfig creates the listener and the firewall rule.
& winrm.cmd quickconfig -q -force 2>&1 | ForEach-Object { Write-Step "quickconfig: $_" }

# 3. Packer and the BDD harness both authenticate as a local account over
#    plain HTTP.
foreach ($pair in @(
  @("winrm/config/service", '@{AllowUnencrypted="true"}'),
  @("winrm/config/service/auth", '@{Basic="true"}'),
  @("winrm/config/client/auth", '@{Basic="true"}'),
  @("winrm/config/winrs", '@{MaxMemoryPerShellMB="2048"}'),
  @("winrm/config", '@{MaxTimeoutms="7200000"}')
)) {
  $output = & winrm.cmd set $pair[0] $pair[1] 2>&1
  Write-Step "set $($pair[0]): $output"
}

Enable-PSRemoting -Force -SkipNetworkProfileCheck -ErrorAction SilentlyContinue
Write-Step "psremoting: $($Error[0]?.Exception.Message)"

# 4. A network logon must be able to touch machine-wide state, and the guest
#    must not be firewalled off on the runner's network.
$token = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
New-ItemProperty -Path $token -Name LocalAccountTokenFilterPolicy -Value 1 `
  -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null

Get-NetConnectionProfile -ErrorAction SilentlyContinue |
  Set-NetConnectionProfile -NetworkCategory Private -ErrorAction SilentlyContinue
& netsh.exe advfirewall set allprofiles state off | Out-Null
Write-Step "firewall disabled"

# 5. Leave evidence that the guest reached this script, independent of WinRM.
Write-Step "bootstrap end; listeners:"
& winrm.cmd enumerate winrm/config/listener 2>&1 |
  ForEach-Object { Write-Step "listener: $_" }
