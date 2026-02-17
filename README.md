# PowerVM - Hyper-V Virtual Machine Creator

An interactive PowerShell script that simplifies creating Hyper-V virtual machines. It walks you through ISO selection, VM configuration, network setup, and creation - all from the terminal.

## Features

- **ISO Browser** - Automatically scans `D:\ISOs` and presents a numbered list to choose from
- **Full VM Configuration** - Set VM name, generation, CPU cores, RAM, disk size, network switch, and TPM
- **Network Configuration** - Choose DHCP or Static IP with full IPv4 settings (IP, subnet, gateway, DNS)
- **PowerShell Direct** - Optionally apply static IP to Windows guests immediately after OS install
- **Saved Network Script** - Static IP config is saved as a reusable `.ps1` script for later use
- **Input Validation** - Prevents duplicates, enforces valid ranges, validates IP addresses
- **Smart Defaults** - Auto-detects CPU cores and network switches; sets Linux Secure Boot template automatically
- **TPM Support** - One-key toggle for TPM (Generation 2 VMs)
- **Review Before Create** - Summary screen shows all settings including network before building the VM
- **Logging** - Every action is logged to a timestamped file in `Logs/`
- **Quick Launch** - Option to start the VM and open `vmconnect` immediately after creation

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

The script will guide you through these steps:

1. **Select ISO** - Pick an installation image from the list
2. **Configure VM** - Name, generation, CPU, RAM, disk, network switch, TPM, and IP settings
3. **Review** - Confirm the full summary including network configuration
4. **Create** - The VM is built, optionally started, and network settings can be applied

## Example Session

```
  +====================================================+
  |        P O W E R  V M   C R E A T O R             |
  |           Hyper-V Virtual Machine Builder          |
  +====================================================+

  --- STEP 1 - Select Installation ISO ---

  Found 3 ISO file(s) in D:\ISOs

    [1] ubuntu-24.04-live-server-amd64.iso  (2.63 GB)
    [2] Win11_23H2_English_x64.iso          (5.37 GB)
    [3] WindowsServer2025.iso               (4.81 GB)

  Select ISO (1-3): 3

  --- STEP 2 - VM Configuration ---

  VM Name: DC-01
  VM Generation [default: 2]: 2
  CPU cores (1-16) [default: 2]: 4
  RAM in GB [default: 4]: 8
  Virtual disk size in GB [default: 60]: 100
  Network switch (0-1) [default: 1]: 1
  Enable TPM module? (Y/N) [default: Y]: Y

    [1] DHCP        (Automatic IP from DHCP server)
    [2] Static IP   (Manually configure IP, gateway, DNS)

  IP configuration [default: 1]: 2
  IP address (e.g. 192.168.1.100): 10.0.0.10
  Subnet prefix length (e.g. 24 for 255.255.255.0) [default: 24]: 24
  Default gateway (e.g. 192.168.1.1): 10.0.0.1
  Primary DNS server (e.g. 8.8.8.8) [default: 8.8.8.8]: 10.0.0.1
  Secondary DNS server (leave blank to skip): 8.8.8.8

  --- STEP 3 - Review and Confirm ---

    VM Name ........... DC-01
    Generation ........ 2
    CPU Cores ......... 4
    RAM ............... 8 GB
    Disk Size ......... 100 GB
    Network Switch .... Default Switch
    TPM ............... Enabled
    ISO ............... WindowsServer2025.iso
    IP Mode ........... Static
    IP Address ........ 10.0.0.10/24
    Gateway ........... 10.0.0.1
    DNS Servers ....... 10.0.0.1, 8.8.8.8

  Create this VM? (Y/N): Y

  +====================================================+
  |   VM 'DC-01' created successfully!                 |
  +====================================================+
```

## Network Configuration

When you choose **Static IP**, the script:

1. **Collects** IP address, subnet prefix length, default gateway, primary DNS, and optional secondary DNS
2. **Validates** all addresses are proper IPv4 format
3. **Saves** a `Set-Network.ps1` script alongside the VM files for later use
4. **Offers to apply** the config immediately via PowerShell Direct (Windows guests only)

### Applying Network Settings

**Option A - Automatic (PowerShell Direct):**
After OS installation, the script can push the network config directly into the running Windows guest. It will prompt for guest VM credentials.

**Option B - Manual:**
Copy and run the saved `Set-Network.ps1` script inside the guest VM:
```powershell
# Path shown after VM creation, typically:
C:\Hyper-V\VMs\DC-01\Set-Network.ps1
```

> **Note:** PowerShell Direct requires Windows guest OS with integration services. For Linux guests, use the saved script as a reference and configure via `ip` / `nmcli` / `netplan`.

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
