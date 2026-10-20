packer {
  required_version = ">= 1.10.0"
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = "~> 1"
    }
  }
}

# Every input is explicit. The caller verifies the ISO and the installers
# before the build starts, so this template never trusts a file it has not
# hashed itself.
variable "iso_url" {
  type        = string
  description = "Local path or URL of the Windows 11 Enterprise LTSC 2024 evaluation ISO."
}

variable "iso_checksum" {
  type        = string
  description = "Checksum of iso_url in Packer's <type>:<hex> form."
}

variable "guest_agent_msi" {
  type        = string
  description = "Path to the virtio-win QEMU guest agent MSI uploaded into the guest."
  default     = ""
}

variable "webview2_installer" {
  type        = string
  description = "Path to the offline Evergreen WebView2 installer."
}

variable "npcap_installer" {
  type        = string
  description = "Path to the Npcap installer."
}

variable "image_name" {
  type        = string
  description = "The /IMAGE/NAME edition inside the ISO's install image."
  default     = "Windows 11 Enterprise LTSC 2024 Evaluation"
}

variable "vm_name" {
  type    = string
  default = "windows-ltsc-2024"
}

variable "output_directory" {
  type    = string
  default = "output"
}

variable "cpus" {
  type    = number
  default = 4
}

variable "memory_mb" {
  type    = number
  default = 6144
}

# The disk is sparse, so its virtual size costs nothing in the published image.
variable "disk_size_mb" {
  type    = number
  default = 40960
}

variable "disk_interface" {
  type        = string
  description = "virtio needs the injected viostor driver; sata needs none."
  default     = "virtio"
}

variable "net_device" {
  type        = string
  description = "virtio-net needs NetKvm injected with the disk driver."
  default     = "virtio-net"
}

variable "accelerator" {
  type        = string
  description = "kvm when the runner exposes /dev/kvm, tcg otherwise."
  default     = "kvm"
}

variable "headless" {
  type    = bool
  default = true
}

variable "ffmpeg_url" {
  type        = string
  description = "Optional ffmpeg zip; empty skips the screen recorder."
  default     = ""
}

variable "shutdown_command" {
  type    = string
  default = "shutdown /s /t 5 /f"
}

locals {
  # The answer file and the virtio drivers share one small ISO. Setup finds
  # Autounattend.xml at the root of any removable drive, so the driver layout
  # can live beside it without a second CD-ROM whose drive letter would shift.
  cd_root     = "${path.root}/generated/cd"
  answer_file = "${local.cd_root}/Autounattend.xml"
}

source "qemu" "windows_ltsc" {
  accelerator      = var.accelerator
  machine_type     = "q35"
  cpus             = var.cpus
  memory           = var.memory_mb
  disk_size        = var.disk_size_mb
  format           = "qcow2"
  disk_interface   = var.disk_interface
  net_device       = var.net_device
  headless         = var.headless
  iso_url          = var.iso_url
  iso_checksum     = var.iso_checksum
  vm_name          = var.vm_name
  output_directory = var.output_directory
  shutdown_command = var.shutdown_command

  # Windows 11 only installs in UEFI mode. Secure Boot is not used: setup's
  # hardware checks are bypassed, so a clone boots on any runner. A runtime
  # that needs Windows Hello or BitLocker adds an emulated TPM to its domain.
  efi_boot          = true
  efi_firmware_code = "/usr/share/OVMF/OVMF_CODE_4M.fd"
  efi_firmware_vars = "/usr/share/OVMF/OVMF_VARS_4M.fd"

  # Setup always sees the virtual floppy at A:, which is the one location it
  # reliably looks for Autounattend.xml. The driver tree is too large for a
  # floppy, so it goes on a small CD-ROM instead.
  # Setup searches removable media for Autounattend.xml. It is placed on the
  # floppy and on the driver CD, because which media a UEFI machine enumerates
  # under A: is not stable; the same file on both costs nothing.
  floppy_files = [local.answer_file]

  # The WinRM bootstrap is embedded in the answer file, so the only thing on
  # the CD is the driver tree.
  cd_files = [
    local.answer_file,
    "${local.cd_root}/drivers",
  ]
  cd_label = "FASTNET"

  # Setup reads Autounattend.xml from removable media by itself.
  boot_wait = "5s"

  communicator   = "winrm"
  winrm_username = "vagrant"
  winrm_password = "vagrant"
  # A correct unattended install reaches WinRM in about 10-20 minutes. A
  # longer wait only hides a hung setup screen behind a long silence, so the
  # build gives up while someone is still watching.
  winrm_timeout  = "30m"
  winrm_use_ssl  = false
  winrm_insecure = true

  # No qemuargs: setting it replaces Packer's whole default argument list
  # (including the disk and NIC), which makes qemu fail to start. The image is
  # headless, so the default display device is enough.
}

build {
  sources = ["source.qemu.windows_ltsc"]

  provisioner "file" {
    source      = var.webview2_installer
    destination = "C:/packages/WebView2Setup.exe"
    direction   = "upload"
  }

  provisioner "file" {
    source      = var.npcap_installer
    destination = "C:/packages/npcap-installer.exe"
    direction   = "upload"
  }

  provisioner "file" {
    source      = var.guest_agent_msi
    destination = "C:/packages/qemu-ga.msi"
    direction   = "upload"
  }

  provisioner "powershell" {
    environment_vars = ["FFMPEG_URL=${var.ffmpeg_url}"]
    scripts = [
      "${path.root}/scripts/10-provision.ps1",
      "${path.root}/scripts/20-harden.ps1",
    ]
    elevated_user     = "vagrant"
    elevated_password = "vagrant"
  }

  provisioner "powershell" {
    script            = "${path.root}/scripts/90-slim.ps1"
    elevated_user     = "vagrant"
    elevated_password = "vagrant"
  }
}
