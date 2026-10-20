$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

New-Item -ItemType Directory -Force -Path C:\packages, C:\fastnet, C:\fastnet\app | Out-Null

# --- QEMU guest agent -------------------------------------------------------
# It comes from the same virtio-win media the installer used, so the runtime
# can query the guest without spawning a WinRM shell for every call.
$virtio = Get-Volume | Where-Object { $_.DriveType -eq "CD-ROM" } |
  ForEach-Object { "$($_.DriveLetter):" } |
  Where-Object { Test-Path "$_\guest-agent\qemu-ga-x86_64.msi" } |
  Select-Object -First 1
if ($virtio) {
  $ga = "$virtio\guest-agent\qemu-ga-x86_64.msi"
  Start-Process msiexec.exe -Wait -ArgumentList "/i `"$ga`" /qn /norestart"
  Set-Service -Name QEMU-GA -StartupType Automatic -ErrorAction SilentlyContinue
  Start-Service -Name QEMU-GA -ErrorAction SilentlyContinue
  Write-Output "qemu guest agent installed from $virtio"
} else {
  Write-Output "warning: virtio-win media not found; qemu guest agent not installed"
}

# --- WebView2 ---------------------------------------------------------------
# Tauri renders through WebView2, and LTSC media does not reliably ship the
# Evergreen runtime. Installing it explicitly is what makes the app render at
# all; a missing runtime shows up as a blank window, not as an error.
if (Test-Path C:\packages\WebView2Setup.exe) {
  Start-Process C:\packages\WebView2Setup.exe -Wait -ArgumentList "/silent /install"
  $runtime = Get-ItemProperty `
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}" `
    -ErrorAction SilentlyContinue
  if (-not $runtime) {
    throw "WebView2 runtime did not register after the offline installer ran"
  }
  Write-Output "webview2 $($runtime.pv) installed"
} else {
  throw "C:\packages\WebView2Setup.exe is missing; the app cannot render"
}

# --- Npcap ------------------------------------------------------------------
# The Windows redirector captures through the WinPcap-compatible API.
if (Test-Path C:\packages\npcap-installer.exe) {
  Start-Process C:\packages\npcap-installer.exe -Wait `
    -ArgumentList "/S /winpcap_mode=yes /dot11_support=no"
  Write-Output "npcap installed"
} else {
  Write-Output "warning: npcap installer not uploaded; capture scenarios will fail"
}

# --- ffmpeg -----------------------------------------------------------------
# Screen recording is opt-in, so the download is opt-in as well.
if ($env:FFMPEG_URL) {
  $zip = "C:\packages\ffmpeg.zip"
  Invoke-WebRequest -Uri $env:FFMPEG_URL -OutFile $zip -UseBasicParsing
  Expand-Archive -Path $zip -DestinationPath C:\packages\ffmpeg -Force
  $exe = Get-ChildItem C:\packages\ffmpeg -Recurse -Filter ffmpeg.exe |
    Select-Object -First 1
  if (-not $exe) { throw "the ffmpeg archive holds no ffmpeg.exe" }
  New-Item -ItemType Directory -Force -Path C:\ffmpeg\bin | Out-Null
  Copy-Item $exe.FullName C:\ffmpeg\bin\ffmpeg.exe -Force
  $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
  if ($machinePath -notlike "*C:\ffmpeg\bin*") {
    [Environment]::SetEnvironmentVariable("Path", "$machinePath;C:\ffmpeg\bin", "Machine")
  }
  Write-Output "ffmpeg installed"
}

# --- Directories the harness reads -----------------------------------------
foreach ($dir in @("C:\Users\vagrant\Documents", "C:\Users\vagrant\Downloads")) {
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

# A long build should not race the guest clock against the evaluation clock.
Set-Service -Name W32Time -StartupType Manual -ErrorAction SilentlyContinue
Stop-Service -Name W32Time -ErrorAction SilentlyContinue

Write-Output "provisioning complete"
