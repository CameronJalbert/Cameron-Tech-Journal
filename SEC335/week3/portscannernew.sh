#!/bin/bash

# Usage: ./portscanner2.sh <network-prefix> <port>
# Example: ./portscanner2.sh 10.0.5 53

network=$1
port=$2

echo "ip,port"

for host in $(seq 1 254); do
    ip="$network.$host"
   
    # Attempt TCP connection with timeout
    timeout 1 bash -c "echo >/dev/tcp/$ip/$port" 2>/dev/null && \
    echo "$ip,$port"
done
