param(
    [Parameter(Mandatory=$true)]
    [string]$NetworkPrefix,
    
    [Parameter(Mandatory=$true)]
    [string]$DnsServer,
    
    [int]$StartOctet = 1,
    [int]$EndOctet = 254
)

# Function to perform reverse DNS lookup
function Resolve-IPAddress {
    param(
        [string]$IPAddress,
        [string]$DnsServer
    )
    
    try {
        $result = Resolve-DnsName -Name $IPAddress -Server $DnsServer -Type PTR -ErrorAction Stop
        return $result.NameHost
    }
    catch {
        return $null
    }
}

# Main script execution
Write-Host "Starting DNS resolution for network $NetworkPrefix.0/24 using DNS server $DnsServer" -ForegroundColor Green
Write-Host ""

# Loop through IP addresses in the specified range
for ($i = $StartOctet; $i -le $EndOctet; $i++) {
    $currentIP = "$NetworkPrefix.$i"
    
    # Attempt to resolve the IP address
    $hostname = Resolve-IPAddress -IPAddress $currentIP -DnsServer $DnsServer
    
    if ($hostname) {
        Write-Host "$currentIP $hostname" -ForegroundColor White
    }
    else {
        # Optionally show failed lookups (commented out to match your example output)
        # Write-Host "$currentIP No PTR record found" -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host "DNS resolution complete." -ForegroundColor Green
