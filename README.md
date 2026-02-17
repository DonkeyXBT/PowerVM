# PowerVM - Hyper-V Virtual Machine Creator

An interactive PowerShell script that simplifies creating Hyper-V virtual machines across standalone hosts or failover cluster nodes. It walks you through host selection, ISO selection, VM configuration, network setup, and creation - all from the terminal.

## Features

- **Cluster-Aware** - Automatically discovers all Hyper-V nodes in a failover cluster, shows their status, and lets you pick which node to deploy on
- **Manual Host Entry** - If no cluster is found or you need a different host, enter any Hyper-V server name/IP manually with live connectivity testing
- **ISO Browser** - Scans `D:\ISOs` and presents a numbered list to choose from
- **Full VM Configuration** - VM name, generation, CPU cores, RAM, disk size, network switch, and TPM
- **Network Configuration** - DHCP or Static IP with full IPv4 settings (IP, subnet, gateway, DNS)
- **PowerShell Direct** - Optionally apply static IP to Windows guests immediately after OS install
- **Saved Network Script** - Static IP config saved as a reusable `.ps1` for later use
- **Input Validation** - Prevents duplicates on the target host, enforces valid ranges, validates IPs
- **Smart Defaults** - Auto-detects CPU cores and switches from the target host; sets Linux Secure Boot template automatically
- **TPM Support** - One-key toggle for TPM (Generation 2 VMs)
- **Review Before Create** - Full summary including host, paths, and network before building
- **Logging** - Every action logged to a timestamped file in `Logs/`
- **Quick Launch** - Start the VM and open `vmconnect` to the correct host immediately

## Requirements

| Requirement | Details |
|---|---|
| OS | Windows 10/11 Pro, Enterprise, or Windows Server with Hyper-V enabled |
| PowerShell | 5.1 or later |
| Privileges | **Run as Administrator** |
| ISO Folder | Place `.iso` files in `D:\ISOs` (configurable at the top of the script) |
| Cluster (optional) | FailoverClusters PowerShell module for auto-discovery |
| Remote hosts (optional) | WinRM/PowerShell remoting enabled on target Hyper-V hosts |

## Quick Start

```powershell
# Open an elevated PowerShell prompt, then:
.\New-HyperVVM.ps1
```

The script guides you through five steps:

1. **Select Host** - Pick a cluster node, use local host, or enter a remote host manually
2. **Select ISO** - Pick an installation image from the list
3. **Configure VM** - Name, generation, CPU, RAM, disk, network switch, TPM, and IP settings
4. **Review** - Confirm everything including target host and storage paths
5. **Create** - The VM is built on the target host, optionally started, network applied

## Example Session

```
  +====================================================+
  |        P O W E R  V M   C R E A T O R             |
  |           Hyper-V Virtual Machine Builder          |
  +====================================================+

  --- STEP 1 - Select Hyper-V Host ---

  Failover Cluster detected: HV-CLUSTER01

    [1] HV-NODE01 (local)  (Hyper-V OK)
    [2] HV-NODE02          (Hyper-V OK)
    [3] HV-NODE03          (Hyper-V OK)
    [0] Enter a different host manually

  Select host (0-3) [default: 1]: 2

  --- STEP 2 - Select Installation ISO ---

  Found 3 ISO file(s) in D:\ISOs

    [1] ubuntu-24.04-live-server-amd64.iso  (2.63 GB)
    [2] Win11_23H2_English_x64.iso          (5.37 GB)
    [3] WindowsServer2025.iso               (4.81 GB)

  Select ISO (1-3): 3

  --- STEP 3 - VM Configuration (on HV-NODE02) ---

  VM Name: DC-01
  VM Generation [default: 2]: 2
  CPU cores (1-32) [default: 2]: 4
  RAM in GB [default: 4]: 8
  Virtual disk size in GB [default: 60]: 100

    [1] vSwitch-Prod  (External)
    [2] vSwitch-Mgmt  (Internal)
    [0] No network adapter

  Network switch (0-2) [default: 1]: 1
  Enable TPM module? (Y/N) [default: Y]: Y

    [1] DHCP        (Automatic IP from DHCP server)
    [2] Static IP   (Manually configure IP, gateway, DNS)

  IP configuration [default: 1]: 2
  IP address (e.g. 192.168.1.100): 10.0.0.10
  Subnet prefix length [default: 24]: 24
  Default gateway (e.g. 192.168.1.1): 10.0.0.1
  Primary DNS server [default: 8.8.8.8]: 10.0.0.1
  Secondary DNS server (leave blank to skip): 8.8.8.8

  --- STEP 4 - Review and Confirm ---

    Hyper-V Host ....... HV-NODE02
    VM Name ........... DC-01
    Generation ........ 2
    CPU Cores ......... 4
    RAM ............... 8 GB
    Disk Size ......... 100 GB
    Network Switch .... vSwitch-Prod
    TPM ............... Enabled
    ISO ............... WindowsServer2025.iso
    IP Mode ........... Static
    IP Address ........ 10.0.0.10/24
    Gateway ........... 10.0.0.1
    DNS Servers ....... 10.0.0.1, 8.8.8.8
    VM Path ........... C:\Hyper-V\VMs
    VHD Path .......... C:\Hyper-V\VHDs

  Create this VM? (Y/N): Y

  +====================================================+
  |   VM 'DC-01' created successfully!                 |
  |   Host: HV-NODE02                                  |
  +====================================================+
```

## Host Selection

The script detects Hyper-V hosts in this order:

1. **Failover Cluster** - If the FailoverClusters module is available, it queries `Get-ClusterNode` and tests each node for Hyper-V connectivity. Nodes are shown with their status (Up/Down/Paused) and Hyper-V reachability.

2. **Local Host** - If no cluster is found, the local machine is offered with a Hyper-V health check.

3. **Manual Entry** - Option `[0]` always lets you type any hostname or IP. The script tests `Get-VMHost` against the target before proceeding.

All Hyper-V commands (`New-VM`, `Get-VMSwitch`, `Set-VMProcessor`, etc.) are executed with `-ComputerName` targeting the selected host. VM name duplicate checks, CPU core counts, and network switches are all queried from the target host.

## Network Configuration

When you choose **Static IP**, the script:

1. **Collects** IP address, subnet prefix, gateway, primary DNS, optional secondary DNS
2. **Validates** all addresses as proper IPv4
3. **Saves** a `Set-Network.ps1` script to the VM directory (via UNC path for remote hosts)
4. **Offers to apply** the config immediately via PowerShell Direct (Windows guests only)

### Applying Network Settings

**Option A - Automatic (PowerShell Direct):**
After OS installation, the script can push the network config into the running Windows guest. Works on both local and remote Hyper-V hosts.

**Option B - Manual:**
Run the saved `Set-Network.ps1` inside the guest VM after OS installation.

## Configuration

Edit the variables at the top of `New-HyperVVM.ps1`:

```powershell
$IsoFolder = "D:\ISOs"          # Where to look for ISO files
```

VM and VHD storage paths are read from the target host's Hyper-V settings (`Get-VMHost`).

## Logs

Each run creates a timestamped log file:

```
Logs/PowerVM_20260217_143052.log
```

Log entries include timestamps, severity levels (`INFO`, `WARN`, `ERROR`, `SUCCESS`), and the target host for every action.

## License

MIT
