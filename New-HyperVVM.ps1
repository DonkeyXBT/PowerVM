#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Interactive Hyper-V Virtual Machine Creator.

.DESCRIPTION
    Creates Hyper-V virtual machines with an interactive menu. Scans D:\ISOs for
    available ISO files, lets the user pick one, and configures VM name, CPU, RAM,
    disk size, generation, network switch, and TPM.

.NOTES
    Author : PowerVM
    Version: 1.0.0
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
$IsoFolder       = "D:\ISOs"
$DefaultVMPath   = (Get-VMHost).VirtualMachinePath
$DefaultVHDPath  = (Get-VMHost).VirtualHardDiskPath
$LogFolder       = Join-Path $PSScriptRoot "Logs"
$LogFile         = Join-Path $LogFolder ("PowerVM_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

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
    Add-Content -Path $LogFile -Value $entry

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

# -- Step 1: ISO Selection ----------------------------------------------------
function Select-Iso {
    Show-Section "STEP 1 - Select Installation ISO"

    if (-not (Test-Path $IsoFolder)) {
        Write-Log "ISO folder not found: $IsoFolder" -Level ERROR
        throw "ISO folder '$IsoFolder' does not exist. Please create it and add ISO files."
    }

    $isos = Get-ChildItem -Path $IsoFolder -Filter "*.iso" -File | Sort-Object Name
    if ($isos.Count -eq 0) {
        Write-Log "No ISO files found in $IsoFolder" -Level ERROR
        throw "No .iso files found in '$IsoFolder'."
    }

    Write-Host "  Found $($isos.Count) ISO file(s) in $IsoFolder" -ForegroundColor Gray
    Write-Host ""

    for ($i = 0; $i -lt $isos.Count; $i++) {
        $size = "{0:N2} GB" -f ($isos[$i].Length / 1GB)
        Write-Host "    [$($i + 1)] " -ForegroundColor Yellow -NoNewline
        Write-Host "$($isos[$i].Name)" -ForegroundColor White -NoNewline
        Write-Host "  ($size)" -ForegroundColor DarkGray
    }
    Write-Host ""

    $choice = Read-ValidatedInput `
        -Prompt "Select ISO (1-$($isos.Count))" `
        -Validator { param($v) $v -match '^\d+$' -and [int]$v -ge 1 -and [int]$v -le $isos.Count } `
        -ErrorMessage "Enter a number between 1 and $($isos.Count)."

    $selected = $isos[[int]$choice - 1]
    Write-Log "ISO selected: $($selected.Name)" -Level INFO
    return $selected.FullName
}

# -- Step 2: VM Configuration -------------------------------------------------
function Get-VMConfig {
    Show-Section "STEP 2 - VM Configuration"

    # VM Name
    $vmName = Read-ValidatedInput `
        -Prompt "VM Name" `
        -Validator {
            param($v)
            if ([string]::IsNullOrWhiteSpace($v)) { return $false }
            if (Get-VM -Name $v -ErrorAction SilentlyContinue) {
                Write-Host "  A VM with that name already exists." -ForegroundColor Red
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

    # CPU
    $maxCpu = (Get-CimInstance Win32_Processor | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
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

    # Network Switch
    $switches = Get-VMSwitch | Sort-Object Name
    $switchName = $null
    if ($switches.Count -gt 0) {
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
        Write-Log "No virtual switches found - skipping network config." -Level WARN
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

# -- Step 3: Confirmation -----------------------------------------------------
function Confirm-VMCreation {
    param($Config, $IsoPath)

    Show-Section "STEP 3 - Review and Confirm"

    $isoName = Split-Path $IsoPath -Leaf

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
    Write-Host ""

    $confirm = Read-ValidatedInput `
        -Prompt "Create this VM? (Y/N)" `
        -Validator { param($v) $v -in @("Y","y","N","n","Yes","yes","No","no") } `
        -ErrorMessage "Enter Y or N."

    return $confirm -match '^[Yy]'
}

# -- Step 4: VM Creation ------------------------------------------------------
function New-VMFromConfig {
    param($Config, $IsoPath)

    Show-Section "STEP 4 - Creating Virtual Machine"

    try {
        # Create the VM
        Write-Log "Creating VM '$($Config.Name)'..."
        $vmParams = @{
            Name               = $Config.Name
            MemoryStartupBytes = $Config.RAM
            Generation         = $Config.Generation
            NoVHD              = $true
            Path               = $DefaultVMPath
        }
        if ($Config.Switch) { $vmParams.SwitchName = $Config.Switch }

        $vm = New-VM @vmParams
        Write-Log "VM created successfully." -Level SUCCESS

        # Create and attach VHDX
        $vhdPath = Join-Path $DefaultVHDPath "$($Config.Name).vhdx"
        Write-Log "Creating virtual disk: $vhdPath"
        New-VHD -Path $vhdPath -SizeBytes $Config.DiskSize -Dynamic | Out-Null

        if ($Config.Generation -eq 1) {
            Add-VMHardDiskDrive -VMName $Config.Name -Path $vhdPath
        } else {
            Add-VMHardDiskDrive -VMName $Config.Name -ControllerType SCSI -Path $vhdPath
        }
        Write-Log "Virtual disk attached." -Level SUCCESS

        # Set CPU
        Write-Log "Setting CPU count to $($Config.CPU)..."
        Set-VMProcessor -VMName $Config.Name -Count $Config.CPU

        # Attach ISO
        Write-Log "Mounting ISO..."
        if ($Config.Generation -eq 1) {
            Set-VMDvdDrive -VMName $Config.Name -Path $IsoPath
        } else {
            Add-VMDvdDrive -VMName $Config.Name -Path $IsoPath
            $dvd = Get-VMDvdDrive -VMName $Config.Name
            Set-VMFirmware -VMName $Config.Name -FirstBootDevice $dvd
        }
        Write-Log "ISO mounted." -Level SUCCESS

        # TPM and Security (Gen 2)
        if ($Config.Generation -eq 2) {
            if ($Config.TPM) {
                Write-Log "Enabling TPM..."
                Set-VMKeyProtector -VMName $Config.Name -NewLocalKeyProtector
                Enable-VMTPM -VMName $Config.Name
                Write-Log "TPM enabled." -Level SUCCESS
            }

            # Set Secure Boot template for Linux ISOs
            $isoName = (Split-Path $IsoPath -Leaf).ToLower()
            if ($isoName -match 'ubuntu|debian|centos|fedora|arch|linux|kali|rocky|alma|suse|mint') {
                Write-Log "Linux ISO detected - setting Secure Boot template to MicrosoftUEFICertificateAuthority."
                Set-VMFirmware -VMName $Config.Name -SecureBootTemplate MicrosoftUEFICertificateAuthority
            }
        }

        # Disable automatic checkpoints (cleaner experience)
        Set-VM -VMName $Config.Name -AutomaticCheckpointsEnabled $false
        Write-Log "Automatic checkpoints disabled."

        Write-Host ""
        Write-Host "  +====================================================+" -ForegroundColor Green
        Write-Host "  |   VM '$($Config.Name)' created successfully!        |" -ForegroundColor Green
        Write-Host "  +====================================================+" -ForegroundColor Green
        Write-Host ""
        Write-Log "VM '$($Config.Name)' creation completed successfully." -Level SUCCESS

        # Save network config script if static IP was chosen
        if ($Config.Network.Mode -eq "Static") {
            $net = $Config.Network
            $dnsServers = @($net.DNS1)
            if ($net.DNS2) { $dnsServers += $net.DNS2 }
            $dnsString = ($dnsServers | ForEach-Object { "'$_'" }) -join ","

            $netScriptContent = @"
# PowerVM Network Configuration for $($Config.Name)
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
            $netScriptPath = Join-Path $DefaultVMPath "$($Config.Name)\Set-Network.ps1"
            $netScriptDir = Split-Path $netScriptPath -Parent
            if (-not (Test-Path $netScriptDir)) {
                New-Item -Path $netScriptDir -ItemType Directory -Force | Out-Null
            }
            $netScriptContent | Out-File -FilePath $netScriptPath -Encoding UTF8
            Write-Log "Network config script saved: $netScriptPath" -Level SUCCESS
        }

        # Ask to start
        $startChoice = Read-ValidatedInput `
            -Prompt "Start the VM now? (Y/N)" `
            -Default "N" `
            -Validator { param($v) $v -in @("Y","y","N","n","Yes","yes","No","no") } `
            -ErrorMessage "Enter Y or N."

        if ($startChoice -match '^[Yy]') {
            Start-VM -Name $Config.Name
            Write-Log "VM '$($Config.Name)' started." -Level SUCCESS
            vmconnect.exe localhost $Config.Name 2>$null
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
                        Invoke-Command -VMName $Config.Name -Credential $guestCred -ScriptBlock {
                            param($IP, $Prefix, $GW, $DNS)

                            $adapter = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
                            if (-not $adapter) { throw "No active network adapter found in guest." }

                            # Remove existing config
                            Remove-NetIPAddress -InterfaceIndex $adapter.ifIndex -Confirm:$false -ErrorAction SilentlyContinue
                            Remove-NetRoute -InterfaceIndex $adapter.ifIndex -Confirm:$false -ErrorAction SilentlyContinue

                            # Apply new config
                            New-NetIPAddress -InterfaceIndex $adapter.ifIndex `
                                -IPAddress $IP -PrefixLength $Prefix -DefaultGateway $GW

                            Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex `
                                -ServerAddresses $DNS

                        } -ArgumentList $net.IPAddress, $net.PrefixLength, $net.Gateway, $dnsArray

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

    $isoPath = Select-Iso
    $config  = Get-VMConfig
    $confirmed = Confirm-VMCreation -Config $config -IsoPath $isoPath

    if ($confirmed) {
        New-VMFromConfig -Config $config -IsoPath $isoPath
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
