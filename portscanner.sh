#!/bin/bash

# Enhanced Port Scanner Script
# Usage: ./portscanner.sh <hostfile> <portfile>
# Example: ./portscanner.sh sweep.txt mytcpports.txt

# Check if correct number of arguments provided
if [ $# -ne 2 ]; then
    echo "Usage: $0 <hostfile> <portfile>"
    echo "Example: $0 sweep.txt mytcpports.txt"
    exit 1
fi

# Assign command line arguments to variables
hostfile=$1
portfile=$2

# Check if host file exists
if [ ! -f "$hostfile" ]; then
    echo "Error: Host file '$hostfile' not found!"
    exit 1
fi

# Check if port file exists
if [ ! -f "$portfile" ]; then
    echo "Error: Port file '$portfile' not found!"
    exit 1
fi

# Display scan information
echo "=== Enhanced Port Scanner ==="
echo "Host file: $hostfile"
echo "Port file: $portfile"
echo "Scan started at: $(date)"
echo "=========================="
echo

# Read each host from the host file
while IFS= read -r host; do
    # Skip empty lines and comments
    [[ -z "$host" || "$host" =~ ^[[:space:]]*# ]] && continue
    
    echo "Scanning host: $host"
    
    # Read each port from the port file
    while IFS= read -r port; do
        # Skip empty lines and comments
        [[ -z "$port" || "$port" =~ ^[[:space:]]*# ]] && continue
        
        # Perform the port scan with timeout
        # Use /dev/tcp for connection testing with 1 second timeout
        timeout 1 bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null
        
        # Check if connection was successful
        if [ $? -eq 0 ]; then
            echo "$host,$port"
        fi
        
    done < "$portfile"
    
    echo # Add blank line after each host
    
done < "$hostfile"

echo "Scan completed at: $(date)"
