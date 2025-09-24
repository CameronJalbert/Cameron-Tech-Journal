#!/bin/bash
# Usage: ./dns-resolver.sh <network-prefix> <dns-server>
# Example: ./dns-resolver.sh 10.0.5 10.0.5.22

network=$1
dns_server=$2

echo "DNS resolution for $network.0/24"

for host in $(seq 1 254); do
    ip="$network.$host"
    nslookup $ip $dns_server 2>/dev/null | \
    awk -v ip="$ip" '/name =/ {print ip " -> " $4}'
done
