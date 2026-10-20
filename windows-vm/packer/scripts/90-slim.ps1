$ErrorActionPreference = "Continue"

# The installers and the archive they expanded from are build inputs, not part
# of the image the harness runs.
$paths = @(
  "C:\packages",
  "C:\Windows.old",
  "C:\Windows\Logs\CBS",
  "C:\Windows\SoftwareDistribution\Download",
  "C:\Windows\Temp",
  "C:\Users\vagrant\AppData\Local\Temp",
  "C:\Users\vagrant\AppData\Local\Microsoft\Windows\INetCache",
  "C:\Users\vagrant\AppData\Local\Microsoft\Windows\WebCache",
  "C:\Users\vagrant\AppData\Local\CrashDumps"
)
foreach ($path in $paths) {
  if (Test-Path $path) {
    Remove-Item -Recurse -Force $path -ErrorAction SilentlyContinue
  }
}

Get-ChildItem C:\Windows\Prefetch -Force -ErrorAction SilentlyContinue |
  Remove-Item -Force -ErrorAction SilentlyContinue
if (Test-Path C:\hiberfil.sys) {
  Remove-Item C:\hiberfil.sys -Force -ErrorAction SilentlyContinue
}

# Collapse the component store and hand the freed blocks back to the qcow2 so
# the exported image only carries what the guest actually uses.
Dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase /NoRestart |
  Out-Null
Optimize-Volume -DriveLetter C -ReTrim -ErrorAction SilentlyContinue

Write-Output "slim complete"
