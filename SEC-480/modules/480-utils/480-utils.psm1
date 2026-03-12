function 480Banner()
{
    Write-Host "Hello SYS480 Devops"
}



# 480Connect - connects to a vCenter server
# vCenter will handle the error if any
Function 480Connect([string] $server)
{
    $conn = $global:DefaultVIServer
    if($conn) {
       
        $msg = "Already connected to: {0}" -f $conn
        Write-Host -ForegroundColor Green $msg
    }
    else {
        
        $conn = Connect-VIServer -Server $server
    }
}



# reads JSON config file and returns it as an object
Function Get-480Config([string] $config_path)
{
    Write-Host "Reading " $config_path
    $conf = $null
    if (Test-Path $config_path)
    {
        # read the file and convert from JSON into a usable object
        $conf = (Get-Content -Raw -Path $config_path | ConvertFrom-Json)
        $msg = "Using config from: {0}" -f $config_path
        Write-Host -ForegroundColor Green $msg
    }
    else
    {
        Write-Host -ForegroundColor Red "No Configuration found at $config_path"
    }
    return $conf
}


# lists all VMs in a given folder and lets the user pick one by index
Function Select-VM([string] $folder)
{
    
    $vms = Get-VM -Location $folder
    $index = 1
    foreach ($vm in $vms)
    {
        Write-Host [$index] $vm.name
        $index += 1
    }
    $pick_index = Read-Host "Which index number [x] do you want to pick?"

    # make sure the input is a number and falls within the valid range regex for this ^ is the start of the string \d+ is  one or more digits $ is end of the string 
    if (-not ($pick_index -match '^\d+$') -or [int]$pick_index -lt 1 -or [int]$pick_index -gt $vms.Count)
    {
        Write-Host -ForegroundColor Red "Invalid selection. Please enter a number between 1 and $($vms.Count)."
        return $null
    }

    # arrays are 0-indexed so subtract 1 from the user's pick
    $selected_vm = $vms[[int]$pick_index - 1]
    Write-Host "You picked " $selected_vm.name
    return $selected_vm
}




# lists all snapshots on a given VM and lets the user pick one by index 
Function Select-Snapshot([object] $vm)
{
    $snapshots = Get-Snapshot -VM $vm
    if (-not $snapshots)
    {
        Write-Host -ForegroundColor Red "No snapshots found on VM '$($vm.name)'."
        return $null
    }
    $index = 1
    foreach ($snap in $snapshots)
    {
        Write-Host [$index] $snap.name
        $index += 1
    }
    $pick_index = Read-Host "Which snapshot do you want to clone from friend?"

    # same as Select-VM
    if (-not ($pick_index -match '^\d+$') -or [int]$pick_index -lt 1 -or [int]$pick_index -gt $snapshots.Count)
    {
        Write-Host -ForegroundColor Red "Invalid selection. Please enter a number between 1 and $($snapshots.Count)."
        return $null
    }

    $selected_snap = $snapshots[[int]$pick_index - 1]
    Write-Host "You picked " $selected_snap.name
    return $selected_snap
}





# New-LinkedClone creates a linked clone from a snapshot of an existing VM
# parms come from the config file (480driver) any missing ones are prompted
Function New-LinkedClone([object] $vm, [object] $snapshot, [string] $clone_name, [string] $esxi_host, [string] $datastore)
{
    
    if (-not $clone_name) { $clone_name = Read-Host "Enter a name for the new linked clone" }
    if (-not $esxi_host)  { $esxi_host  = Read-Host "Enter the ESXi host (IP or hostname)" }
    if (-not $datastore)  { $datastore  = Read-Host "Enter the datastore name" }

    $vmhost = Get-VMHost -Name $esxi_host
    $ds     = Get-Datastore -Name $datastore

    Write-Host -ForegroundColor Yellow "Creating linked clone '$clone_name'..."
    $linked_clone = New-VM -Name $clone_name -VM $vm -ReferenceSnapshot $snapshot -VMHost $vmhost -Datastore $ds -LinkedClone
    Write-Host -ForegroundColor Green "Linked clone '$clone_name' created successfully."
    return $linked_clone
}



# New-FullClone creates a full clone of a VM from a snapshot
# try/catch here bc if step 2 or 3 fails we need to clean up the temp clone, otherwise it gets left behind in vCenter as an orphaned VM 
Function New-FullClone([object] $vm, [object] $snapshot, [string] $clone_name, [string] $esxi_host, [string] $datastore)
{
   
    if (-not $clone_name) { $clone_name = Read-Host "Enter a name for the new full clone" }
    if (-not $esxi_host)  { $esxi_host  = Read-Host "Enter the ESXi host (IP or hostname)" }
    if (-not $datastore)  { $datastore  = Read-Host "Enter the datastore name" }

    $vmhost = Get-VMHost -Name $esxi_host
    $ds     = Get-Datastore -Name $datastore

    # create a temporary linked clone from the selected snapshot
    $temp_name = "temp-linked-clone"
    Write-Host -ForegroundColor Yellow "Creating temporary linked clone '$temp_name'..."
    $temp_clone = New-VM -Name $temp_name -VM $vm -ReferenceSnapshot $snapshot -VMHost $vmhost -Datastore $ds -LinkedClone

    try
    {
        # create the full clone from the temporary linked clone
        Write-Host -ForegroundColor Yellow "Creating full clone '$clone_name'..."
        $full_clone = New-VM -Name $clone_name -VM $temp_clone -VMHost $vmhost -Datastore $ds

        # remove the temporary linked clone, it is no longer needed
        Write-Host -ForegroundColor Yellow "Removing temporary linked clone..."
        Remove-VM -VM $temp_clone -DeletePermanently -Confirm:$false

        Write-Host -ForegroundColor Green "Full clone '$clone_name' created successfully."
        return $full_clone
    }
    catch
    {
        # if step 2 or 3 failed will clean up the temp clone so it does not get left behind in vCenter
        Write-Host -ForegroundColor Red "Error creating full clone: $_"
        Write-Host -ForegroundColor Yellow "Cleaning up temporary linked clone '$temp_name'..."
        Remove-VM -VM $temp_clone -DeletePermanently -Confirm:$false
    }
}


# Lab 6 content below:

# New-Network
# Creates a standard virtual switch and portgroup on the chosen ESXi host
Function New-Network([string] $vswitch_name, [string] $portgroup_name, [string] $esxi_host)
{
    if (-not $vswitch_name)   { $vswitch_name   = Read-Host "Enter the new vSwitch name" }
    if (-not $portgroup_name) { $portgroup_name = Read-Host "Enter the new portgroup name" }
    if (-not $esxi_host)      { $esxi_host      = Read-Host "Enter the ESXi host name or IP" }

    $vmhost = Get-VMHost -Name $esxi_host -ErrorAction Stop

    $existing_switch = Get-VirtualSwitch -VMHost $vmhost -Name $vswitch_name -ErrorAction SilentlyContinue
    if ($existing_switch)
    {
        Write-Host -ForegroundColor Yellow "vSwitch '$vswitch_name' already exists on host '$esxi_host'."
    }
    else
    {
        Write-Host -ForegroundColor Yellow "Creating vSwitch '$vswitch_name' on '$esxi_host'..."
        $existing_switch = New-VirtualSwitch -VMHost $vmhost -Name $vswitch_name
        Write-Host -ForegroundColor Green "vSwitch '$vswitch_name' created successfully."
    }

    $existing_pg = Get-VirtualPortGroup -VirtualSwitch $existing_switch -Name $portgroup_name -ErrorAction SilentlyContinue
    if ($existing_pg)
    {
        Write-Host -ForegroundColor Yellow "Portgroup '$portgroup_name' already exists on vSwitch '$vswitch_name'."
    }
    else
    {
        Write-Host -ForegroundColor Yellow "Creating portgroup '$portgroup_name' on '$vswitch_name'..."
        New-VirtualPortGroup -VirtualSwitch $existing_switch -Name $portgroup_name | Out-Null
        Write-Host -ForegroundColor Green "Portgroup '$portgroup_name' created successfully."
    }
}

# Get-IP
# Gets the first MAC address and first IPv4 address from a named VM
Function Get-IP([string] $vm_name)
{
    if (-not $vm_name) { $vm_name = Read-Host "Enter the VM name" }

    $vm = Get-VM -Name $vm_name -ErrorAction SilentlyContinue
    if (-not $vm)
    {
        Write-Host -ForegroundColor Red "VM '$vm_name' not found."
        return $null
    }

    $adapter = Get-NetworkAdapter -VM $vm | Select-Object -First 1
    $mac = $null
    if ($adapter) { $mac = $adapter.MacAddress }

    $ipv4 = $null
    if ($vm.Guest.IPAddress)
    {
        $ipv4 = $vm.Guest.IPAddress | Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' } | Select-Object -First 1
    }

    [pscustomobject]@{
        VM   = $vm.Name
        IP   = $ipv4
        MAC  = $mac
    }
}

# Start-480VM
# Starts one or more VMs by name
Function Start-480VM([string[]] $vm_names)
{
    if (-not $vm_names)
    {
        $vm_names = (Read-Host "Enter one or more VM names separated by commas").Split(",") | ForEach-Object { $_.Trim() }
    }

    foreach ($name in $vm_names)
    {
        $vm = Get-VM -Name $name -ErrorAction SilentlyContinue
        if (-not $vm)
        {
            Write-Host -ForegroundColor Red "VM '$name' not found."
            continue
        }

        if ($vm.PowerState -eq "PoweredOn")
        {
            Write-Host -ForegroundColor Yellow "VM '$name' is already powered on."
        }
        else
        {
            Write-Host -ForegroundColor Yellow "Starting VM '$name'..."
            Start-VM -VM $vm -Confirm:$false | Out-Null
            Write-Host -ForegroundColor Green "VM '$name' started."
        }
    }
}

# Stop-480VM
# Stops one or more VMs by name
Function Stop-480VM([string[]] $vm_names)
{
    if (-not $vm_names)
    {
        $vm_names = (Read-Host "Enter one or more VM names separated by commas").Split(",") | ForEach-Object { $_.Trim() }
    }

    foreach ($name in $vm_names)
    {
        $vm = Get-VM -Name $name -ErrorAction SilentlyContinue
        if (-not $vm)
        {
            Write-Host -ForegroundColor Red "VM '$name' not found."
            continue
        }

        if ($vm.PowerState -eq "PoweredOff")
        {
            Write-Host -ForegroundColor Yellow "VM '$name' is already powered off."
        }
        else
        {
            Write-Host -ForegroundColor Yellow "Stopping VM '$name'..."
            Stop-VM -VM $vm -Confirm:$false | Out-Null
            Write-Host -ForegroundColor Green "VM '$name' stopped."
        }
    }
}

# Set-Network
# Sets a VM NIC to a chosen portgroup/network
Function Set-Network([string] $vm_name, [string] $network_name, [int] $nic_number = 1)
{
    if (-not $vm_name)      { $vm_name      = Read-Host "Enter the VM name" }
    if (-not $network_name) { $network_name = Read-Host "Enter the target network/portgroup name" }

    $vm = Get-VM -Name $vm_name -ErrorAction SilentlyContinue
    if (-not $vm)
    {
        Write-Host -ForegroundColor Red "VM '$vm_name' not found."
        return
    }

    $adapters = Get-NetworkAdapter -VM $vm
    if (-not $adapters)
    {
        Write-Host -ForegroundColor Red "No network adapters found on '$vm_name'."
        return
    }

    if ($nic_number -lt 1 -or $nic_number -gt $adapters.Count)
    {
        Write-Host -ForegroundColor Red "Invalid NIC number. '$vm_name' has $($adapters.Count) adapter(s)."
        return
    }

    $adapter = $adapters[$nic_number - 1]

    Write-Host -ForegroundColor Yellow "Setting NIC $nic_number on '$vm_name' to network '$network_name'..."
    Set-NetworkAdapter -NetworkAdapter $adapter -NetworkName $network_name -Confirm:$false | Out-Null
    Write-Host -ForegroundColor Green "NIC $nic_number on '$vm_name' is now connected to '$network_name'."
}
