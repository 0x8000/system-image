$ErrorActionPreference = "Stop"

# Packer and the BDD harness both reach the guest over WinRM as `vagrant`.
# Both need basic auth over HTTP, and a network logon has to be able to touch
# machine-wide state.
winrm set winrm/config/service '@{AllowUnencrypted="true"}' | Out-Null
winrm set winrm/config/service/auth '@{Basic="true"}' | Out-Null
winrm set winrm/config/client/auth '@{Basic="true"}' | Out-Null
winrm set winrm/config/winrs '@{MaxMemoryPerShellMB="2048"}' | Out-Null
winrm set winrm/config '@{MaxTimeoutms="7200000"}' | Out-Null

Set-Service -Name WinRM -StartupType Automatic
Start-Service -Name WinRM

Enable-PSRemoting -Force -SkipNetworkProfileCheck
netsh advfirewall firewall set rule group="Windows Remote Management" new enable=yes | Out-Null

$tokenFilter = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
New-ItemProperty -Path $tokenFilter -Name LocalAccountTokenFilterPolicy -Value 1 `
  -PropertyType DWord -Force | Out-Null

# A clone starts on whatever network the runner provides, which Windows would
# classify as Public and firewall off. This image is a disposable test device.
Get-NetConnectionProfile -ErrorAction SilentlyContinue |
  Set-NetConnectionProfile -NetworkCategory Private -ErrorAction SilentlyContinue
netsh advfirewall set allprofiles state off | Out-Null

Write-Output "winrm ready"
