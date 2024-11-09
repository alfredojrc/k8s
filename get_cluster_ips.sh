#!/bin/bash
echo "Control Plane Init: $(multipass info control-plane-1 | grep IPv4 | awk '{print $2}')"
echo "Control Plane Join: $(multipass info control-plane-2 | grep IPv4 | awk '{print $2}'), $(multipass info control-plane-3 | grep IPv4 | awk '{print $2}')"
echo "Workers: $(multipass info worker-1 | grep IPv4 | awk '{print $2}'), $(multipass info worker-2 | grep IPv4 | awk '{print $2}'), $(multipass info worker-3 | grep IPv4 | awk '{print $2}')"
echo "HAProxy: $(multipass info haproxy-1 | grep IPv4 | awk '{print $2}'), $(multipass info haproxy-2 | grep IPv4 | awk '{print $2}')"
