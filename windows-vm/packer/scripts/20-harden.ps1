$ErrorActionPreference = "Continue"

# A disposable test device: anything that scans, indexes, uploads telemetry or
# downloads updates costs boot time and disk in every clone.
$services = @(
  "WSearch", "SysMain", "DiagTrack", "dmwappushservice", "WerSvc",
  "RemoteRegistry", "Fax", "SecurityHealthService", "MapsBroker",
  "RetailDemo", "WMPNetworkSvc", "XblAuthManager", "XblGameSave",
  "XboxGipSvc", "XboxNetApiSvc", "PhoneSvc", "TabletInputService"
)
foreach ($name in $services) {
  $service = Get-Service -Name $name -ErrorAction SilentlyContinue
  if ($service) {
    Stop-Service -Name $name -Force -ErrorAction SilentlyContinue
    Set-Service -Name $name -StartupType Disabled -ErrorAction SilentlyContinue
  }
}

# Keep Windows Update manual instead of disabled: the evaluation licence check
# and the servicing stack still run once in a while.
Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
Set-Service -Name wuauserv -StartupType Manual -ErrorAction SilentlyContinue

# Defender's real-time scanner is the largest source of I/O latency in a
# Windows test VM. The policy survives a reboot and leaves the service in
# place so servicing tools keep working.
Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction SilentlyContinue
Set-MpPreference -DisableIOAVProtection $true -ErrorAction SilentlyContinue
Set-MpPreference -DisableScriptScanning $true -ErrorAction SilentlyContinue
$defender = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
New-Item -Path $defender -Force | Out-Null
New-ItemProperty -Path $defender -Name DisableAntiSpyware -Value 1 `
  -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path "$defender\Real-Time Protection" -Name DisableRealtimeMonitoring `
  -Value 1 -PropertyType DWord -Force | Out-Null

powercfg.exe /hibernate off | Out-Null
powercfg.exe /setactive SCHEME_MIN | Out-Null
powercfg.exe /change standby-timeout-ac 0 | Out-Null
powercfg.exe /change hibernate-timeout-ac 0 | Out-Null

# Fast startup keeps a hybrid dump around and makes shutdown non-clean.
New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" `
  -Name HiberbootEnabled -Value 0 -PropertyType DWord -Force | Out-Null

# A fixed page file keeps disk usage predictable instead of letting Windows
# grow it to fill the image.
$cs = Get-CimInstance Win32_ComputerSystem
if ($cs.AutomaticManagedPagefile) {
  Set-CimInstance -InputObject $cs -Property @{ AutomaticManagedPagefile = $false }
  Get-CimInstance Win32_PageFileSetting -ErrorAction SilentlyContinue |
    ForEach-Object { Remove-CimInstance -InputObject $_ }
  New-CimInstance -ClassName Win32_PageFileSetting -Property @{
    Name = "C:\pagefile.sys"; InitialSize = 2048; MaximumSize = 2048
  } -ErrorAction SilentlyContinue | Out-Null
}

# Visual effects cost compositor time and make screen capture noisy.
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" `
  -Name VisualFXSetting -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue

# Nothing in a scenario needs Store apps, OneDrive or the tips they ship with.
$appx = "Microsoft.WindowsStore|Microsoft.StorePurchaseApp|Microsoft.Xbox*|" +
  "Microsoft.ZuneMusic|Microsoft.ZuneVideo|Microsoft.BingNews|Microsoft.BingWeather|" +
  "Microsoft.GetHelp|Microsoft.Getstarted|Microsoft.MicrosoftSolitaireCollection|" +
  "Microsoft.People|Microsoft.SkypeApp|Microsoft.YourPhone|Microsoft.MicrosoftOfficeHub|" +
  "Microsoft.Todos|Microsoft.WindowsFeedbackHub|Microsoft.WindowsMaps"
Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
  Where-Object { $_.DisplayName -match $appx } |
  Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Out-Null
Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -match $appx } |
  Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue

# Scheduled work that only matters on a user's daily driver.
$tasks = @(
  "\Microsoft\Windows\Application Experience\ProgramDataUpdater",
  "\Microsoft\Windows\Autochk\Proxy",
  "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
  "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip",
  "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector",
  "\Microsoft\Windows\Feedback\Siuf\DmClient",
  "\Microsoft\Windows\Windows Error Reporting\QueueReporting"
)
foreach ($task in $tasks) {
  schtasks.exe /Change /TN $task /Disable 2>$null | Out-Null
}

Write-Output "hardening complete"
