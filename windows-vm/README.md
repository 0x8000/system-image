# Windows 11 LTSC 2024 golden VM

Builds the Windows disk the FastNet BDD suite drives through WebView2 CDP, and
publishes it to GitHub Container Registry as a split-layer OCI image.

## Why LTSC

`Windows 11 Enterprise LTSC 2024` is the same kernel generation as the Windows
Server 2025 image the harness used before (build 26100), but it is a client
edition: no Store, no Copilot, no Widgets, no OneDrive, and no consumer app
inventory to strip. That makes the image smaller and keeps desktop behaviour
closer to a user's machine.

It is **not** what makes a scenario fast. A cold Windows boot costs minutes; a
restored running domain costs seconds. Use the published disk as a backing file
and keep a warm worker (see "Speed").

The image deliberately does not ship Edge or assume WebView2 is present. Tauri
renders through WebView2, so the build installs the offline Evergreen runtime
explicitly and fails if it does not register.

## Layout

| Path | Purpose |
| --- | --- |
| `packer/windows-ltsc.pkr.hcl` | QEMU builder: UEFI, virtio, WinRM, qcow2 output |
| `packer/answer_files/Autounattend.xml.tpl` | UEFI layout, edition selection, vagrant user, WinRM |
| `packer/scripts/` | WinRM bootstrap, prerequisites, hardening, slim |
| `scripts/build-image.sh` | End-to-end build: verify ISO, render, fetch, packer |
| `scripts/inspect-iso.sh` | Hash the ISO and list its editions |
| `scripts/render-answer.py` | Render the answer file for the verified edition |
| `scripts/check-answer.py` | Assert the answer file matches the edition |
| `scripts/make-oci-context.sh` | Split the qcow2 and generate the OCI Dockerfile |
| `scripts/fetch-image.sh` | Pull the image and reassemble the disk |
| `tests/test_scripts.py` | Unit tests for the renderer and the split/reassemble path |
| `../.github/workflows/windows-image.yml` | CI: lint, probe for KVM, build, publish |

## Build

```sh
windows-vm/scripts/build-image.sh \
  --work-dir /mnt/windows-vm \
  --compress
```

The script verifies the ISO, reads the edition names out of `install.wim`,
refuses to continue if the requested edition is not there, renders the answer
file from that name, stages only the `w11/amd64` virtio trees onto the driver
CD-ROM, and then runs Packer.

Useful overrides:

- `--iso-url`, `--iso-sha256` — a different LTSC media or a pinned hash.
- `--image-name "Windows 11 IoT Enterprise LTSC Evaluation"` — the IoT edition,
  which has a 10-year lifecycle instead of 90 days of evaluation.
- `--disk-interface sata` — fall back if virtio injection fails during setup.
- `--accelerator tcg` — CPU emulation, only for a smoke test of the pipeline.

## Publish and consume

The workflow pushes `ghcr.io/<owner>/windows-vm:ltsc2024`,
`ltsc2024-<date>` and `ltsc2024-sha-<commit>`. The disk is split into 1800 MiB
parts, one per image layer, because GHCR rejects layers over 10 GiB.

```sh
docker login ghcr.io
windows-vm/scripts/fetch-image.sh \
  --image ghcr.io/0x8000/windows-vm:ltsc2024 \
  --output-dir /mnt/windows-vm
```

Then use the disk directly, or as the read-only backing file for a per-worker
overlay:

```sh
qemu-img create -f qcow2 -b /mnt/windows-vm/disk.qcow2 -F qcow2 worker-1.qcow2
```

## CI

`Windows LTSC image` has three jobs:

1. `lint` — shellcheck, the renderer tests, and a real `packer validate`. A typo
   fails in about a minute.
2. `probe` — unlocks `/dev/kvm` with the udev rule GitHub's own Android tooling
   uses, reports which mount has the most free space, and decides whether the
   build is worth starting. Without KVM it skips the build unless `tcg=true`.
3. `build` — only when the probe found a workable machine. Builds the disk,
   splits it, and pushes to GHCR; pull requests build but do not push.

## Speed

Image size is not the bottleneck. Cold Windows boot costs minutes; restoring a
saved running domain costs seconds. Keep one worker domain per parallel suite,
start the app once, then `virsh save` / `virsh restore` around each scenario.

## Deliberate trade-offs

- **No TPM during the build.** Windows 11 setup checks are bypassed through
  `LabConfig`. A runtime that needs Windows Hello adds an emulated TPM to its
  libvirt domain.
- **No sysprep.** Generalising makes every clone re-run OOBE, which is exactly
  the cost the warm pool avoids. Clones share a machine SID and hostname.
- **Defender is disabled, not removed.** Servicing tools keep working and the
  image does not pay for real-time scanning.
- **Evaluation media expires.** The Enterprise LTSC evaluation runs for 90 days;
  the IoT LTSC evaluation runs longer. Rebuild on a schedule instead of treating
  a cached image as permanent.
