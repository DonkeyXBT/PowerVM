# PowerVM - Hyper-V Virtual Machine Creator

An interactive PowerShell script that simplifies creating Hyper-V virtual machines. It walks you through ISO selection, VM configuration, and creation — all from the terminal.

## Features

- **ISO Browser** — Automatically scans `D:\ISOs` and presents a numbered list to choose from
- **Full VM Configuration** — Set VM name, generation, CPU cores, RAM, disk size, network switch, and TPM
- **Input Validation** — Prevents duplicates, enforces valid ranges, offers sensible defaults
- **Smart Defaults** — Auto-detects available CPU cores and network switches; sets Linux Secure Boot template when a Linux ISO is detected
- **TPM Support** — One-key toggle for TPM (Generation 2 VMs)
- **Review Before Create** — Summary screen lets you confirm everything before the VM is built
- **Logging** — Every action is logged to a timestamped file in `Logs/`
- **Quick Launch** — Option to start the VM and open `vmconnect` immediately after creation

## Requirements

| Requirement | Details |
|---|---|
| OS | Windows 10/11 Pro, Enterprise, or Windows Server with Hyper-V enabled |
| PowerShell | 5.1 or later |
| Privileges | **Run as Administrator** |
| ISO Folder | Place `.iso` files in `D:\ISOs` (configurable at the top of the script) |

## Quick Start

```powershell
# Open an elevated PowerShell prompt, then:
.\New-HyperVVM.ps1
```

The script will guide you through four steps:

1. **Select ISO** — Pick an installation image from the list
2. **Configure VM** — Name, generation, CPU, RAM, disk, network, TPM
3. **Review** — Confirm the summary
4. **Create** — The VM is built and optionally started

## Example Session

```
  ╔══════════════════════════════════════════════════╗
  ║        ⚡  P O W E R  V M   C R E A T O R  ⚡   ║
  ║           Hyper-V Virtual Machine Builder        ║
  ╚══════════════════════════════════════════════════╝

  ── STEP 1 — Select Installation ISO ──

  Found 3 ISO file(s) in D:\ISOs

    [1] ubuntu-24.04-live-server-amd64.iso  (2.63 GB)
    [2] Win11_23H2_English_x64.iso          (5.37 GB)
    [3] WindowsServer2025.iso               (4.81 GB)

  Select ISO (1-3): 1

  ── STEP 2 — VM Configuration ──

  VM Name: Ubuntu-Web-01
  VM Generation [default: 2]: 2
  CPU cores (1-16) [default: 2]: 4
  RAM in GB [default: 4]: 8
  Virtual disk size in GB [default: 60]: 100
  Network switch (0-1) [default: 1]: 1
  Enable TPM module? (Y/N) [default: Y]: Y

  ── STEP 3 — Review & Confirm ──

    VM Name ........... Ubuntu-Web-01
    Generation ........ 2
    CPU Cores ......... 4
    RAM ............... 8 GB
    Disk Size ......... 100 GB
    Network Switch .... Default Switch
    TPM ............... Enabled
    ISO ............... ubuntu-24.04-live-server-amd64.iso

  Create this VM? (Y/N): Y

  ╔══════════════════════════════════════════════════╗
  ║   VM 'Ubuntu-Web-01' created successfully!      ║
  ╚══════════════════════════════════════════════════╝
```

## Configuration

Edit the variables at the top of `New-HyperVVM.ps1` to change defaults:

```powershell
$IsoFolder = "D:\ISOs"          # Where to look for ISO files
```

VM storage paths are read from your Hyper-V host settings (`Get-VMHost`).

## Logs

Each run creates a timestamped log file:

```
Logs/PowerVM_20260217_143052.log
```

Log entries include timestamps, severity levels (`INFO`, `WARN`, `ERROR`, `SUCCESS`), and details for every action taken.

## License

MIT
