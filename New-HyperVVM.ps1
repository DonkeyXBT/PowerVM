#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Interactive Hyper-V Virtual Machine Creator with cluster node support.

.DESCRIPTION
    Creates Hyper-V virtual machines with an interactive menu. Discovers cluster
    nodes automatically or lets you target a specific Hyper-V host. Scans D:\ISOs
    for available ISO files, and configures VM name, CPU, RAM, disk size,
    generation, network switch, TPM, and static IP settings.

.NOTES
    Author : PowerVM
    Version: 1.1.0
    Requires: Windows with Hyper-V role enabled, run as Administrator.
#>

# -- Prerequisite Check -------------------------------------------------------
if (-not (Get-Module -ListAvailable -Name Hyper-V)) {
    Write-Host ""
    Write-Host "  Hyper-V PowerShell module is not installed." -ForegroundColor Red
    Write-Host ""
    Write-Host "  To fix this, run one of the following in an elevated PowerShell:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "    # Windows 10/11 Pro/Enterprise:" -ForegroundColor DarkGray
    Write-Host "    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-Management-PowerShell" -ForegroundColor White
    Write-Host ""
    Write-Host "    # Windows Server:" -ForegroundColor DarkGray
    Write-Host "    Install-WindowsFeature -Name Hyper-V-PowerShell" -ForegroundColor White
    Write-Host ""
    exit 1
}

# -- Configuration -------------------------------------------------------------
$IsoFolder  = "D:\ISOs"

# Resolve script directory (works for .ps1 execution, ISE, VS Code, and console paste)
$ScriptDir = $null
if ($PSScriptRoot -and $PSScriptRoot -ne '') {
    $ScriptDir = $PSScriptRoot
}
if (-not $ScriptDir) {
    try { $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path -ErrorAction Stop } catch {}
}
if (-not $ScriptDir) {
    try { $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition -ErrorAction Stop } catch {}
}
if (-not $ScriptDir -or $ScriptDir -eq '' -or $ScriptDir -eq '.') {
    $ScriptDir = (Get-Location).Path
}

$LogFolder = Join-Path $ScriptDir "Logs"
$LogFile   = Join-Path $LogFolder ("PowerVM_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

# -- Logging -------------------------------------------------------------------
if (-not (Test-Path $LogFolder)) { New-Item -Path $LogFolder -ItemType Directory -Force | Out-Null }

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO","WARN","ERROR","SUCCESS")]
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] [$Level] $Message"
    if ($LogFile) {
        try { Add-Content -Path $LogFile -Value $entry -ErrorAction Stop } catch {}
    }

    switch ($Level) {
        "INFO"    { Write-Host "  $Message" -ForegroundColor Cyan }
        "WARN"    { Write-Host "  WARNING: $Message" -ForegroundColor Yellow }
        "ERROR"   { Write-Host "  ERROR: $Message" -ForegroundColor Red }
        "SUCCESS" { Write-Host "  $Message" -ForegroundColor Green }
    }
}

# -- UI Helpers ----------------------------------------------------------------
function Show-Banner {
    Clear-Host
    Write-Host ""
    Write-Host "  +====================================================+" -ForegroundColor DarkCyan
    Write-Host "  |                                                    |" -ForegroundColor DarkCyan
    Write-Host "  |        P O W E R  V M   C R E A T O R             |" -ForegroundColor Cyan
    Write-Host "  |           Hyper-V Virtual Machine Builder          |" -ForegroundColor DarkCyan
    Write-Host "  |                                                    |" -ForegroundColor DarkCyan
    Write-Host "  +====================================================+" -ForegroundColor DarkCyan
    Write-Host ""
}

function Show-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "  --- $Title ---" -ForegroundColor White
    Write-Host ""
}

function Read-ValidatedInput {
    param(
        [string]$Prompt,
        [string]$Default = "",
        [scriptblock]$Validator = { $true },
        [string]$ErrorMessage = "Invalid input. Please try again."
    )
    while ($true) {
        $display = if ($Default) { "$Prompt [default: $Default]" } else { $Prompt }
        Write-Host "  $display" -ForegroundColor White -NoNewline
        Write-Host ": " -NoNewline
        $value = Read-Host
        if ([string]::IsNullOrWhiteSpace($value) -and $Default) { $value = $Default }
        if (& $Validator $value) { return $value }
        Write-Host "  $ErrorMessage" -ForegroundColor Red
    }
}

# -- Step 1: Hyper-V Node Selection -------------------------------------------
function Select-HyperVNode {
    Show-Section "STEP 1 - Select Hyper-V Host"

    $localHost = $env:COMPUTERNAME
    $nodes = @()

    # Try to discover cluster nodes
    $clusterAvailable = $false
    if (Get-Module -ListAvailable -Name FailoverClusters -ErrorAction SilentlyContinue) {
        try {
            Import-Module FailoverClusters -ErrorAction Stop
            $clusterNodes = Get-ClusterNode -ErrorAction Stop
            if ($clusterNodes) {
                $clusterAvailable = $true
                $clusterName = (Get-Cluster -ErrorAction Stop).Name
                Write-Host "  Failover Cluster detected: " -ForegroundColor Gray -NoNewline
                Write-Host $clusterName -ForegroundColor White
                Write-Host ""

                foreach ($node in ($clusterNodes | Sort-Object Name)) {
                    $status = $node.State.ToString()
                    $hvOk = $false

                    if ($status -eq "Up") {
                        # Test if Hyper-V is responding on the node
                        try {
                            Get-VMHost -ComputerName $node.Name -ErrorAction Stop | Out-Null
                            $hvOk = $true
                        } catch {
                            $hvOk = $false
                        }
                    }

                    $nodes += [PSCustomObject]@{
                        Name     = $node.Name
                        Status   = $status
                        HyperV   = $hvOk
                    }
                }

                for ($i = 0; $i -lt $nodes.Count; $i++) {
                    $n = $nodes[$i]
                    $statusColor = if ($n.Status -eq "Up" -and $n.HyperV) { "Green" } elseif ($n.Status -eq "Up") { "Yellow" } else { "Red" }
                    $hvLabel = if ($n.HyperV) { "Hyper-V OK" } elseif ($n.Status -eq "Up") { "Hyper-V unreachable" } else { $n.Status }
                    $isLocal = if ($n.Name -eq $localHost) { " (local)" } else { "" }

                    Write-Host "    [$($i + 1)] " -ForegroundColor Yellow -NoNewline
                    Write-Host "$($n.Name)$isLocal" -ForegroundColor White -NoNewline
                    Write-Host "  ($hvLabel)" -ForegroundColor $statusColor
                }
                Write-Host "    [0] " -ForegroundColor Yellow -NoNewline
                Write-Host "Enter a different host manually" -ForegroundColor DarkGray
                Write-Host ""
            }
        } catch {
            Write-Log "Cluster query failed: $($_.Exception.Message)" -Level INFO
        }
    }

    if (-not $clusterAvailable) {
        Write-Host "  No failover cluster detected." -ForegroundColor Gray
        Write-Host ""

        # Check if local Hyper-V is available
        $localHvOk = $false
        try {
            Get-VMHost -ErrorAction Stop | Out-Null
            $localHvOk = $true
        } catch {
            $localHvOk = $false
        }

        if ($localHvOk) {
            Write-Host "    [1] " -ForegroundColor Yellow -NoNewline
            Write-Host "$localHost (local)" -ForegroundColor White -NoNewline
            Write-Host "  (Hyper-V OK)" -ForegroundColor Green
        } else {
            Write-Host "    [1] " -ForegroundColor Yellow -NoNewline
            Write-Host "$localHost (local)" -ForegroundColor White -NoNewline
            Write-Host "  (Hyper-V not available)" -ForegroundColor Red
        }
        Write-Host "    [0] " -ForegroundColor Yellow -NoNewline
        Write-Host "Enter a different host manually" -ForegroundColor DarkGray
        Write-Host ""

        $nodes = @([PSCustomObject]@{ Name = $localHost; Status = "Up"; HyperV = $localHvOk })
    }

    # Node selection
    $maxChoice = $nodes.Count
    $nodeChoice = Read-ValidatedInput `
        -Prompt "Select host (0-$maxChoice)" `
        -Default "1" `
        -Validator { param($v) $v -match '^\d+$' -and [int]$v -ge 0 -and [int]$v -le $maxChoice } `
        -ErrorMessage "Enter a number between 0 and $maxChoice."

    $targetHost = $null

    if ([int]$nodeChoice -eq 0) {
        # Manual entry
        $targetHost = Read-ValidatedInput `
            -Prompt "Enter Hyper-V host name or IP" `
            -Validator {
                param($v)
                if ([string]::IsNullOrWhiteSpace($v)) { return $false }
                Write-Host "  Testing connection to $v..." -ForegroundColor Gray
                try {
                    Get-VMHost -ComputerName $v -ErrorAction Stop | Out-Null
                    return $true
                } catch {
                    Write-Host "  Could not reach Hyper-V on '$v': $($_.Exception.Message)" -ForegroundColor Red
                    return $false
                }
            } `
            -ErrorMessage "Enter a valid Hyper-V host."
    } else {
        $selected = $nodes[[int]$nodeChoice - 1]
        if (-not $selected.HyperV) {
            Write-Log "Selected node '$($selected.Name)' does not have Hyper-V available." -Level WARN
            $proceed = Read-ValidatedInput `
                -Prompt "Node '$($selected.Name)' may not be reachable. Try anyway? (Y/N)" `
                -Default "N" `
                -Validator { param($v) $v -in @("Y","y","N","n") } `
                -ErrorMessage "Enter Y or N."

            if ($proceed -notmatch '^[Yy]') {
                throw "Aborted: selected node is not available."
            }
        }
        $targetHost = $selected.Name
    }

    # Get host paths from target
    $isLocal = ($targetHost -eq $localHost)
    Write-Log "Target Hyper-V host: $targetHost$(if ($isLocal) { ' (local)' })"

    try {
        $vmHost = Get-VMHost -ComputerName $targetHost -ErrorAction Stop
        Write-Log "Connected to $targetHost - VM path: $($vmHost.VirtualMachinePath)" -Level SUCCESS
    } catch {
        Write-Log "Failed to connect to Hyper-V on $targetHost : $_" -Level ERROR
        throw "Cannot connect to Hyper-V on '$targetHost'."
    }

    return @{
        ComputerName = $targetHost
        IsLocal      = $isLocal
        VMPath       = $vmHost.VirtualMachinePath
        VHDPath      = $vmHost.VirtualHardDiskPath
    }
}

# -- Step 2: ISO Selection ----------------------------------------------------
function Select-Iso {
    param($HostInfo)

    $targetHost = $HostInfo.ComputerName
    $isLocal    = $HostInfo.IsLocal

    Show-Section "STEP 2 - Select Installation ISO"

    # Determine the ISO browse path
    # For remote hosts, try the same folder via UNC, then the remote host's local path
    $browsePathDisplay = $IsoFolder
    $browsePath        = $null
    $isoPathIsRemote   = $false
    $isos              = @()

    if ($isLocal) {
        # Local host - browse local folder directly
        if (Test-Path $IsoFolder) {
            $browsePath = $IsoFolder
            $isos = Get-ChildItem -Path $browsePath -Filter "*.iso" -File | Sort-Object Name
        }
    } else {
        # Remote host - try multiple paths to find ISOs

        # 1. Try UNC path to the ISO folder on the remote host (e.g. \\REMOTEHOST\D$\ISOs)
        $uncIsoPath = "\\$targetHost\" + ($IsoFolder -replace ':', '$')
        if (Test-Path $uncIsoPath -ErrorAction SilentlyContinue) {
            $browsePath = $uncIsoPath
            $browsePathDisplay = "$IsoFolder on $targetHost"
            $isos = Get-ChildItem -Path $browsePath -Filter "*.iso" -File | Sort-Object Name
            $isoPathIsRemote = $true
        }

        # 2. Try the local ISO folder (maybe it's a shared/mapped path accessible from both)
        if ($isos.Count -eq 0 -and (Test-Path $IsoFolder -ErrorAction SilentlyContinue)) {
            $browsePath = $IsoFolder
            $browsePathDisplay = "$IsoFolder (local - will need to be accessible from $targetHost)"
            $isos = Get-ChildItem -Path $browsePath -Filter "*.iso" -File | Sort-Object Name
        }
    }

    if ($isos.Count -gt 0) {
        Write-Host "  Found $($isos.Count) ISO file(s) in $browsePathDisplay" -ForegroundColor Gray
        Write-Host ""

        for ($i = 0; $i -lt $isos.Count; $i++) {
            $size = "{0:N2} GB" -f ($isos[$i].Length / 1GB)
            Write-Host "    [$($i + 1)] " -ForegroundColor Yellow -NoNewline
            Write-Host "$($isos[$i].Name)" -ForegroundColor White -NoNewline
            Write-Host "  ($size)" -ForegroundColor DarkGray
        }
        Write-Host "    [0] " -ForegroundColor Yellow -NoNewline
        Write-Host "Enter a custom ISO path manually" -ForegroundColor DarkGray
        Write-Host ""

        $choice = Read-ValidatedInput `
            -Prompt "Select ISO (0-$($isos.Count))" `
            -Validator { param($v) $v -match '^\d+$' -and [int]$v -ge 0 -and [int]$v -le $isos.Count } `
            -ErrorMessage "Enter a number between 0 and $($isos.Count)."

        if ([int]$choice -gt 0) {
            $selected = $isos[[int]$choice - 1]

            if ($isoPathIsRemote) {
                # Convert UNC browse path back to local path for the remote host
                # e.g. \\HOST\D$\ISOs\file.iso -> D:\ISOs\file.iso
                $remoteLocalPath = Join-Path $IsoFolder $selected.Name
                Write-Log "ISO selected: $($selected.Name) (path on $targetHost : $remoteLocalPath)" -Level INFO
                return $remoteLocalPath
            } elseif (-not $isLocal) {
                # Local browse but remote host - convert to UNC for the remote host to access
                # Or just return local path and let user deal with access
                Write-Host ""
                Write-Host "  NOTE: The ISO is on this management machine." -ForegroundColor Yellow
                Write-Host "  The remote host $targetHost needs to access this file." -ForegroundColor Yellow
                Write-Host ""
                Write-Host "  The ISO path as seen by $targetHost must be provided." -ForegroundColor Gray
                Write-Host "  Examples:" -ForegroundColor DarkGray
                Write-Host "    - UNC share:    \\fileserver\ISOs\$($selected.Name)" -ForegroundColor DarkGray
                Write-Host "    - Cluster vol:  C:\ClusterStorage\Volume1\ISOs\$($selected.Name)" -ForegroundColor DarkGray
                Write-Host "    - Same path:    $($selected.FullName)  (if drive is shared/replicated)" -ForegroundColor DarkGray
                Write-Host ""

                $remotePath = Read-ValidatedInput `
                    -Prompt "ISO path accessible from $targetHost" `
                    -Default $selected.FullName `
                    -Validator { param($v) -not [string]::IsNullOrWhiteSpace($v) } `
                    -ErrorMessage "Path cannot be empty."
                Write-Log "ISO selected: $($selected.Name) (remote path: $remotePath)" -Level INFO
                return $remotePath
            } else {
                Write-Log "ISO selected: $($selected.Name)" -Level INFO
                return $selected.FullName
            }
        }
        # Fall through to manual entry if choice is 0
    } else {
        Write-Host "  No ISO files found automatically." -ForegroundColor Yellow
        if (-not $isLocal) {
            Write-Host "  Could not browse $IsoFolder on $targetHost." -ForegroundColor Yellow
        }
        Write-Host ""
    }

    # Manual ISO path entry
    Write-Host "  Enter the full path to the ISO file as accessible from $targetHost." -ForegroundColor Gray
    if (-not $isLocal) {
        Write-Host "  Examples:" -ForegroundColor DarkGray
        Write-Host "    - UNC share:    \\fileserver\ISOs\server2025.iso" -ForegroundColor DarkGray
        Write-Host "    - Cluster vol:  C:\ClusterStorage\Volume1\ISOs\server2025.iso" -ForegroundColor DarkGray
        Write-Host "    - Local path:   D:\ISOs\server2025.iso  (on $targetHost)" -ForegroundColor DarkGray
    }
    Write-Host ""

    $manualPath = Read-ValidatedInput `
        -Prompt "ISO path" `
        -Validator {
            param($v)
            if ([string]::IsNullOrWhiteSpace($v)) { return $false }
            if ($v -notmatch '\.iso$') {
                Write-Host "  Path must end with .iso" -ForegroundColor Red
                return $false
            }
            # Try to verify the path exists (locally or via UNC)
            if (Test-Path $v -ErrorAction SilentlyContinue) { return $true }
            # For remote paths we can't always verify - accept it
            if (-not $isLocal) {
                Write-Host "  Cannot verify path from here - will attempt to use it on $targetHost." -ForegroundColor Yellow
                return $true
            }
            Write-Host "  File not found: $v" -ForegroundColor Red
            return $false
        } `
        -ErrorMessage "Enter a valid path to an ISO file."

    Write-Log "ISO selected (manual): $manualPath" -Level INFO
    return $manualPath
}

# -- Step 3: VM Configuration -------------------------------------------------
function Get-VMConfig {
    param($HostInfo)

    $targetHost = $HostInfo.ComputerName

    Show-Section "STEP 3 - VM Configuration (on $targetHost)"

    # VM Name
    $vmName = Read-ValidatedInput `
        -Prompt "VM Name" `
        -Validator {
            param($v)
            if ([string]::IsNullOrWhiteSpace($v)) { return $false }
            if (Get-VM -ComputerName $targetHost -Name $v -ErrorAction SilentlyContinue) {
                Write-Host "  A VM with that name already exists on $targetHost." -ForegroundColor Red
                return $false
            }
            return $true
        } `
        -ErrorMessage "Name cannot be empty."
    Write-Log "VM name: $vmName"

    # Generation
    Write-Host ""
    Write-Host "    [1] " -ForegroundColor Yellow -NoNewline
    Write-Host "Generation 1" -ForegroundColor White -NoNewline
    Write-Host "  (Legacy BIOS, IDE)" -ForegroundColor DarkGray
    Write-Host "    [2] " -ForegroundColor Yellow -NoNewline
    Write-Host "Generation 2" -ForegroundColor White -NoNewline
    Write-Host "  (UEFI, Secure Boot, TPM - Recommended)" -ForegroundColor DarkGray
    Write-Host ""

    $gen = Read-ValidatedInput `
        -Prompt "VM Generation" `
        -Default "2" `
        -Validator { param($v) $v -in @("1","2") } `
        -ErrorMessage "Enter 1 or 2."
    $generation = [int]$gen
    Write-Log "Generation: $generation"

    # CPU - query target host
    try {
        $maxCpu = (Get-CimInstance Win32_Processor -ComputerName $targetHost | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
    } catch {
        $maxCpu = (Get-CimInstance Win32_Processor | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
        Write-Log "Could not query CPU from $targetHost, using local CPU count." -Level WARN
    }
    $cpuDefault = [Math]::Min(2, $maxCpu)
    $cpu = Read-ValidatedInput `
        -Prompt "CPU cores (1-$maxCpu)" `
        -Default "$cpuDefault" `
        -Validator { param($v) $v -match '^\d+$' -and [int]$v -ge 1 -and [int]$v -le $maxCpu } `
        -ErrorMessage "Enter a number between 1 and $maxCpu."
    $cpuCount = [int]$cpu
    Write-Log "CPU cores: $cpuCount"

    # RAM
    $ram = Read-ValidatedInput `
        -Prompt "RAM in GB" `
        -Default "4" `
        -Validator { param($v) $v -match '^\d+$' -and [int]$v -ge 1 -and [int]$v -le 1024 } `
        -ErrorMessage "Enter a number between 1 and 1024."
    $ramBytes = [int64]$ram * 1GB
    Write-Log "RAM: ${ram} GB"

    # Disk Size
    $disk = Read-ValidatedInput `
        -Prompt "Virtual disk size in GB" `
        -Default "60" `
        -Validator { param($v) $v -match '^\d+$' -and [int]$v -ge 1 -and [int]$v -le 64000 } `
        -ErrorMessage "Enter a number between 1 and 64000."
    $diskBytes = [int64]$disk * 1GB
    Write-Log "Disk size: ${disk} GB"

    # Network Switch - from target host
    $switches = Get-VMSwitch -ComputerName $targetHost -ErrorAction SilentlyContinue | Sort-Object Name
    $switchName = $null
    if ($switches -and $switches.Count -gt 0) {
        Write-Host ""
        for ($i = 0; $i -lt $switches.Count; $i++) {
            Write-Host "    [$($i + 1)] " -ForegroundColor Yellow -NoNewline
            Write-Host "$($switches[$i].Name)" -ForegroundColor White -NoNewline
            Write-Host "  ($($switches[$i].SwitchType))" -ForegroundColor DarkGray
        }
        Write-Host "    [0] " -ForegroundColor Yellow -NoNewline
        Write-Host "No network adapter" -ForegroundColor DarkGray
        Write-Host ""

        $swChoice = Read-ValidatedInput `
            -Prompt "Network switch (0-$($switches.Count))" `
            -Default "1" `
            -Validator { param($v) $v -match '^\d+$' -and [int]$v -ge 0 -and [int]$v -le $switches.Count } `
            -ErrorMessage "Enter a number between 0 and $($switches.Count)."

        if ([int]$swChoice -gt 0) {
            $switchName = $switches[[int]$swChoice - 1].Name
            Write-Log "Network switch: $switchName"
        } else {
            Write-Log "Network: none"
        }
    } else {
        Write-Log "No virtual switches found on $targetHost - skipping network config." -Level WARN
    }

    # TPM (Gen 2 only)
    $enableTPM = $false
    if ($generation -eq 2) {
        $tpmChoice = Read-ValidatedInput `
            -Prompt "Enable TPM module? (Y/N)" `
            -Default "Y" `
            -Validator { param($v) $v -in @("Y","y","N","n","Yes","yes","No","no") } `
            -ErrorMessage "Enter Y or N."
        $enableTPM = $tpmChoice -match '^[Yy]'
        Write-Log "TPM: $(if ($enableTPM) { 'Enabled' } else { 'Disabled' })"
    }

    # Network IP Configuration
    $netConfig = @{ Mode = "DHCP" }
    if ($switchName) {
        Write-Host ""
        Write-Host "    [1] " -ForegroundColor Yellow -NoNewline
        Write-Host "DHCP" -ForegroundColor White -NoNewline
        Write-Host "  (Automatic IP from DHCP server)" -ForegroundColor DarkGray
        Write-Host "    [2] " -ForegroundColor Yellow -NoNewline
        Write-Host "Static IP" -ForegroundColor White -NoNewline
        Write-Host "  (Manually configure IP, gateway, DNS)" -ForegroundColor DarkGray
        Write-Host ""

        $ipMode = Read-ValidatedInput `
            -Prompt "IP configuration" `
            -Default "1" `
            -Validator { param($v) $v -in @("1","2") } `
            -ErrorMessage "Enter 1 or 2."

        if ($ipMode -eq "2") {
            $netConfig.Mode = "Static"

            $ipAddr = Read-ValidatedInput `
                -Prompt "IP address (e.g. 192.168.1.100)" `
                -Validator {
                    param($v)
                    try { [System.Net.IPAddress]::Parse($v) | Out-Null; return $true }
                    catch { return $false }
                } `
                -ErrorMessage "Enter a valid IPv4 address."
            $netConfig.IPAddress = $ipAddr
            Write-Log "Static IP: $ipAddr"

            $prefix = Read-ValidatedInput `
                -Prompt "Subnet prefix length (e.g. 24 for 255.255.255.0)" `
                -Default "24" `
                -Validator { param($v) $v -match '^\d+$' -and [int]$v -ge 1 -and [int]$v -le 32 } `
                -ErrorMessage "Enter a number between 1 and 32."
            $netConfig.PrefixLength = [int]$prefix
            Write-Log "Subnet prefix: /$prefix"

            $gateway = Read-ValidatedInput `
                -Prompt "Default gateway (e.g. 192.168.1.1)" `
                -Validator {
                    param($v)
                    try { [System.Net.IPAddress]::Parse($v) | Out-Null; return $true }
                    catch { return $false }
                } `
                -ErrorMessage "Enter a valid IPv4 address."
            $netConfig.Gateway = $gateway
            Write-Log "Gateway: $gateway"

            $dns1 = Read-ValidatedInput `
                -Prompt "Primary DNS server (e.g. 8.8.8.8)" `
                -Default "8.8.8.8" `
                -Validator {
                    param($v)
                    try { [System.Net.IPAddress]::Parse($v) | Out-Null; return $true }
                    catch { return $false }
                } `
                -ErrorMessage "Enter a valid IPv4 address."
            $netConfig.DNS1 = $dns1
            Write-Log "Primary DNS: $dns1"

            $dns2 = Read-ValidatedInput `
                -Prompt "Secondary DNS server (leave blank to skip)" `
                -Default "" `
                -Validator {
                    param($v)
                    if ([string]::IsNullOrWhiteSpace($v)) { return $true }
                    try { [System.Net.IPAddress]::Parse($v) | Out-Null; return $true }
                    catch { return $false }
                } `
                -ErrorMessage "Enter a valid IPv4 address or leave blank."
            if (-not [string]::IsNullOrWhiteSpace($dns2)) {
                $netConfig.DNS2 = $dns2
                Write-Log "Secondary DNS: $dns2"
            }
        } else {
            Write-Log "Network mode: DHCP"
        }
    }

    return @{
        Name       = $vmName
        Generation = $generation
        CPU        = $cpuCount
        RAM        = $ramBytes
        RAMDisplay = $ram
        DiskSize   = $diskBytes
        DiskDisplay= $disk
        Switch     = $switchName
        TPM        = $enableTPM
        Network    = $netConfig
    }
}

# -- Step 4: Confirmation -----------------------------------------------------
function Confirm-VMCreation {
    param($Config, $IsoPath, $HostInfo)

    Show-Section "STEP 4 - Review and Confirm"

    $isoName = Split-Path $IsoPath -Leaf

    Write-Host "    Hyper-V Host ....... " -NoNewline -ForegroundColor DarkGray
    Write-Host "$($HostInfo.ComputerName)$(if ($HostInfo.IsLocal) { ' (local)' })" -ForegroundColor White
    Write-Host "    VM Name ........... " -NoNewline -ForegroundColor DarkGray
    Write-Host $Config.Name -ForegroundColor White
    Write-Host "    Generation ........ " -NoNewline -ForegroundColor DarkGray
    Write-Host $Config.Generation -ForegroundColor White
    Write-Host "    CPU Cores ......... " -NoNewline -ForegroundColor DarkGray
    Write-Host $Config.CPU -ForegroundColor White
    Write-Host "    RAM ............... " -NoNewline -ForegroundColor DarkGray
    Write-Host "$($Config.RAMDisplay) GB" -ForegroundColor White
    Write-Host "    Disk Size ......... " -NoNewline -ForegroundColor DarkGray
    Write-Host "$($Config.DiskDisplay) GB" -ForegroundColor White
    Write-Host "    Network Switch .... " -NoNewline -ForegroundColor DarkGray
    Write-Host $(if ($Config.Switch) { $Config.Switch } else { "None" }) -ForegroundColor White
    Write-Host "    TPM ............... " -NoNewline -ForegroundColor DarkGray
    Write-Host $(if ($Config.TPM) { "Enabled" } else { "Disabled" }) -ForegroundColor White
    Write-Host "    ISO ............... " -NoNewline -ForegroundColor DarkGray
    Write-Host $isoName -ForegroundColor White

    # Network details
    $net = $Config.Network
    Write-Host "    IP Mode ........... " -NoNewline -ForegroundColor DarkGray
    Write-Host $net.Mode -ForegroundColor White
    if ($net.Mode -eq "Static") {
        Write-Host "    IP Address ........ " -NoNewline -ForegroundColor DarkGray
        Write-Host "$($net.IPAddress)/$($net.PrefixLength)" -ForegroundColor White
        Write-Host "    Gateway ........... " -NoNewline -ForegroundColor DarkGray
        Write-Host $net.Gateway -ForegroundColor White
        $dnsDisplay = $net.DNS1
        if ($net.DNS2) { $dnsDisplay += ", $($net.DNS2)" }
        Write-Host "    DNS Servers ....... " -NoNewline -ForegroundColor DarkGray
        Write-Host $dnsDisplay -ForegroundColor White
    }

    Write-Host "    VM Path ........... " -NoNewline -ForegroundColor DarkGray
    Write-Host $HostInfo.VMPath -ForegroundColor White
    Write-Host "    VHD Path .......... " -NoNewline -ForegroundColor DarkGray
    Write-Host $HostInfo.VHDPath -ForegroundColor White
    Write-Host ""

    $confirm = Read-ValidatedInput `
        -Prompt "Create this VM? (Y/N)" `
        -Validator { param($v) $v -in @("Y","y","N","n","Yes","yes","No","no") } `
        -ErrorMessage "Enter Y or N."

    return $confirm -match '^[Yy]'
}

# -- Step 5: VM Creation ------------------------------------------------------
function New-VMFromConfig {
    param($Config, $IsoPath, $HostInfo)

    $targetHost = $HostInfo.ComputerName
    $vmPath     = $HostInfo.VMPath
    $vhdPath    = $HostInfo.VHDPath

    Show-Section "STEP 5 - Creating Virtual Machine on $targetHost"

    try {
        # Create the VM
        Write-Log "Creating VM '$($Config.Name)' on $targetHost..."
        $vmParams = @{
            Name               = $Config.Name
            ComputerName       = $targetHost
            MemoryStartupBytes = $Config.RAM
            Generation         = $Config.Generation
            NoVHD              = $true
            Path               = $vmPath
        }
        if ($Config.Switch) { $vmParams.SwitchName = $Config.Switch }

        $vm = New-VM @vmParams
        Write-Log "VM created successfully on $targetHost." -Level SUCCESS

        # Create and attach VHDX
        $vhdFullPath = Join-Path $vhdPath "$($Config.Name).vhdx"
        Write-Log "Creating virtual disk: $vhdFullPath"
        New-VHD -ComputerName $targetHost -Path $vhdFullPath -SizeBytes $Config.DiskSize -Dynamic | Out-Null

        if ($Config.Generation -eq 1) {
            Add-VMHardDiskDrive -ComputerName $targetHost -VMName $Config.Name -Path $vhdFullPath
        } else {
            Add-VMHardDiskDrive -ComputerName $targetHost -VMName $Config.Name -ControllerType SCSI -Path $vhdFullPath
        }
        Write-Log "Virtual disk attached." -Level SUCCESS

        # Set CPU
        Write-Log "Setting CPU count to $($Config.CPU)..."
        Set-VMProcessor -ComputerName $targetHost -VMName $Config.Name -Count $Config.CPU

        # Attach ISO
        Write-Log "Mounting ISO..."
        if ($Config.Generation -eq 1) {
            Set-VMDvdDrive -ComputerName $targetHost -VMName $Config.Name -Path $IsoPath
        } else {
            Add-VMDvdDrive -ComputerName $targetHost -VMName $Config.Name -Path $IsoPath
            $dvd = Get-VMDvdDrive -ComputerName $targetHost -VMName $Config.Name
            Set-VMFirmware -ComputerName $targetHost -VMName $Config.Name -FirstBootDevice $dvd
        }
        Write-Log "ISO mounted." -Level SUCCESS

        # TPM and Security (Gen 2)
        if ($Config.Generation -eq 2) {
            if ($Config.TPM) {
                Write-Log "Enabling TPM..."
                Set-VMKeyProtector -ComputerName $targetHost -VMName $Config.Name -NewLocalKeyProtector
                Enable-VMTPM -ComputerName $targetHost -VMName $Config.Name
                Write-Log "TPM enabled." -Level SUCCESS
            }

            # Set Secure Boot template for Linux ISOs
            $isoName = (Split-Path $IsoPath -Leaf).ToLower()
            if ($isoName -match 'ubuntu|debian|centos|fedora|arch|linux|kali|rocky|alma|suse|mint') {
                Write-Log "Linux ISO detected - setting Secure Boot template to MicrosoftUEFICertificateAuthority."
                Set-VMFirmware -ComputerName $targetHost -VMName $Config.Name -SecureBootTemplate MicrosoftUEFICertificateAuthority
            }
        }

        # Disable automatic checkpoints (cleaner experience)
        Set-VM -ComputerName $targetHost -VMName $Config.Name -AutomaticCheckpointsEnabled $false
        Write-Log "Automatic checkpoints disabled."

        Write-Host ""
        Write-Host "  +====================================================+" -ForegroundColor Green
        Write-Host "  |   VM '$($Config.Name)' created successfully!        |" -ForegroundColor Green
        Write-Host "  |   Host: $($targetHost.PadRight(43))|" -ForegroundColor Green
        Write-Host "  +====================================================+" -ForegroundColor Green
        Write-Host ""
        Write-Log "VM '$($Config.Name)' creation completed on $targetHost." -Level SUCCESS

        # Save network config script if static IP was chosen
        $netScriptPath = $null
        if ($Config.Network.Mode -eq "Static") {
            $net = $Config.Network
            $dnsServers = @($net.DNS1)
            if ($net.DNS2) { $dnsServers += $net.DNS2 }
            $dnsString = ($dnsServers | ForEach-Object { "'$_'" }) -join ","

            $netScriptContent = @"
# PowerVM Network Configuration for $($Config.Name)
# Created on host: $targetHost
# Run this inside the guest VM after OS installation.
# Requires: Run as Administrator

`$adapter = Get-NetAdapter | Where-Object { `$_.Status -eq 'Up' } | Select-Object -First 1
if (-not `$adapter) {
    Write-Host 'No active network adapter found.' -ForegroundColor Red
    exit 1
}

Write-Host "Configuring adapter: `$(`$adapter.Name)" -ForegroundColor Cyan

# Remove existing IP config
Remove-NetIPAddress -InterfaceIndex `$adapter.ifIndex -Confirm:`$false -ErrorAction SilentlyContinue
Remove-NetRoute -InterfaceIndex `$adapter.ifIndex -Confirm:`$false -ErrorAction SilentlyContinue

# Set static IP
New-NetIPAddress -InterfaceIndex `$adapter.ifIndex ``
    -IPAddress '$($net.IPAddress)' ``
    -PrefixLength $($net.PrefixLength) ``
    -DefaultGateway '$($net.Gateway)'

# Set DNS servers
Set-DnsClientServerAddress -InterfaceIndex `$adapter.ifIndex ``
    -ServerAddresses @($dnsString)

Write-Host 'Network configuration applied successfully.' -ForegroundColor Green
Write-Host ''
Write-Host '  IP Address .... $($net.IPAddress)/$($net.PrefixLength)' -ForegroundColor White
Write-Host '  Gateway ....... $($net.Gateway)' -ForegroundColor White
Write-Host "  DNS Servers ... $($dnsServers -join ', ')" -ForegroundColor White
"@
            $netScriptPath = Join-Path $vmPath "$($Config.Name)\Set-Network.ps1"
            # Write to target host via UNC or local path
            if ($HostInfo.IsLocal) {
                $scriptDir = Split-Path $netScriptPath -Parent
                if (-not (Test-Path $scriptDir)) {
                    New-Item -Path $scriptDir -ItemType Directory -Force | Out-Null
                }
                $netScriptContent | Out-File -FilePath $netScriptPath -Encoding UTF8
            } else {
                # Convert local path to UNC for remote host
                $uncPath = "\\$targetHost\" + ($netScriptPath -replace ':', '$')
                $uncDir = Split-Path $uncPath -Parent
                if (-not (Test-Path $uncDir)) {
                    New-Item -Path $uncDir -ItemType Directory -Force | Out-Null
                }
                $netScriptContent | Out-File -FilePath $uncPath -Encoding UTF8
            }
            Write-Log "Network config script saved: $netScriptPath" -Level SUCCESS
        }

        # Ask to start
        $startChoice = Read-ValidatedInput `
            -Prompt "Start the VM now? (Y/N)" `
            -Default "N" `
            -Validator { param($v) $v -in @("Y","y","N","n","Yes","yes","No","no") } `
            -ErrorMessage "Enter Y or N."

        if ($startChoice -match '^[Yy]') {
            Start-VM -ComputerName $targetHost -Name $Config.Name
            Write-Log "VM '$($Config.Name)' started on $targetHost." -Level SUCCESS
            vmconnect.exe $targetHost $Config.Name 2>$null
        }

        # Apply network config via PowerShell Direct (after OS install)
        if ($Config.Network.Mode -eq "Static" -and $Config.Switch) {
            Write-Host ""
            Write-Host "  --- Network Configuration ---" -ForegroundColor White
            Write-Host ""
            Write-Host "  Static IP was configured. You can apply it after OS installation:" -ForegroundColor Gray
            Write-Host ""
            Write-Host "    Option 1: Apply now via PowerShell Direct (Windows guest, OS must be installed)" -ForegroundColor DarkGray
            Write-Host "    Option 2: Skip now, run the saved script later inside the VM" -ForegroundColor DarkGray
            Write-Host "              Script: $netScriptPath" -ForegroundColor DarkGray
            Write-Host ""

            $applyNow = Read-ValidatedInput `
                -Prompt "Apply network config now via PowerShell Direct? (Y/N)" `
                -Default "N" `
                -Validator { param($v) $v -in @("Y","y","N","n","Yes","yes","No","no") } `
                -ErrorMessage "Enter Y or N."

            if ($applyNow -match '^[Yy]') {
                Write-Host ""
                Write-Host "  Enter credentials for the guest VM:" -ForegroundColor White
                $guestCred = Get-Credential -Message "Guest VM credentials for $($Config.Name)"

                if ($guestCred) {
                    $net = $Config.Network
                    $dnsArray = @($net.DNS1)
                    if ($net.DNS2) { $dnsArray += $net.DNS2 }

                    Write-Log "Applying network configuration via PowerShell Direct..."

                    try {
                        Invoke-Command -ComputerName $targetHost -ScriptBlock {
                            param($VMName, $Cred, $IP, $Prefix, $GW, $DNS)

                            Invoke-Command -VMName $VMName -Credential $Cred -ScriptBlock {
                                param($IP, $Prefix, $GW, $DNS)

                                $adapter = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
                                if (-not $adapter) { throw "No active network adapter found in guest." }

                                Remove-NetIPAddress -InterfaceIndex $adapter.ifIndex -Confirm:$false -ErrorAction SilentlyContinue
                                Remove-NetRoute -InterfaceIndex $adapter.ifIndex -Confirm:$false -ErrorAction SilentlyContinue

                                New-NetIPAddress -InterfaceIndex $adapter.ifIndex `
                                    -IPAddress $IP -PrefixLength $Prefix -DefaultGateway $GW

                                Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex `
                                    -ServerAddresses $DNS

                            } -ArgumentList $IP, $Prefix, $GW, $DNS

                        } -ArgumentList $Config.Name, $guestCred, $net.IPAddress, $net.PrefixLength, $net.Gateway, $dnsArray

                        Write-Log "Network configuration applied to guest VM." -Level SUCCESS
                    }
                    catch {
                        Write-Log "Could not apply network config: $_" -Level WARN
                        Write-Host "  You can apply it later by running the script inside the VM:" -ForegroundColor Yellow
                        Write-Host "  $netScriptPath" -ForegroundColor White
                    }
                }
            } else {
                Write-Log "Network config deferred. Script saved for later use."
                Write-Host "  To apply later, copy and run inside the VM:" -ForegroundColor Gray
                Write-Host "  $netScriptPath" -ForegroundColor White
            }
        }
    }
    catch {
        Write-Log "Failed to create VM: $_" -Level ERROR
        Write-Log $_.ScriptStackTrace -Level ERROR
        throw
    }
}

# -- Main ----------------------------------------------------------------------
try {
    Show-Banner
    Write-Log "PowerVM session started."
    Write-Log "Log file: $LogFile"

    $hostInfo  = Select-HyperVNode
    $isoPath   = Select-Iso -HostInfo $hostInfo
    $config    = Get-VMConfig -HostInfo $hostInfo
    $confirmed = Confirm-VMCreation -Config $config -IsoPath $isoPath -HostInfo $hostInfo

    if ($confirmed) {
        New-VMFromConfig -Config $config -IsoPath $isoPath -HostInfo $hostInfo
    } else {
        Write-Log "VM creation cancelled by user." -Level WARN
        Write-Host "  Cancelled. No VM was created." -ForegroundColor Yellow
    }
}
catch {
    Write-Log "Fatal error: $_" -Level ERROR
    Write-Host ""
    Write-Host "  Script terminated due to an error. Check the log: $LogFile" -ForegroundColor Red
    exit 1
}
finally {
    Write-Log "PowerVM session ended."
    Write-Host ""
    Write-Host "  Log saved to: $LogFile" -ForegroundColor DarkGray
    Write-Host ""
}
