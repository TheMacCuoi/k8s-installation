#!/bin/bash
#
# Common setup for all servers (Control Plane and Nodes)

set -euxo pipefail

# Variable Declaration

KUBERNETES_VERSION="1.28.1-00"

# disable swap
sudo swapoff -a

# keeps the swaf off during reboot
(crontab -l 2>/dev/null; echo "@reboot /sbin/swapoff -a") | crontab - || true
sudo apt-get update -y


# Install CRI-O Runtime

OS="xUbuntu_22.04"

VERSION="1.28"

# Create the .conf file to load the modules at bootup
cat <<EOF | sudo tee /etc/modules-load.d/crio.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Set up required sysctl params, these persist across reboots.
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sudo sysctl --system

cat <<EOF | sudo tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list
deb https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/ /
EOF
cat <<EOF | sudo tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable:cri-o:$VERSION.list
deb http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$VERSION/$OS/ /
EOF

curl -L https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable:cri-o:$VERSION/$OS/Release.key | sudo apt-key --keyring /etc/apt/trusted.gpg.d/libcontainers.gpg add -
curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/Release.key | sudo apt-key --keyring /etc/apt/trusted.gpg.d/libcontainers.gpg add -

sudo apt-get update
sudo apt-get install cri-o cri-o-runc -y

sudo systemctl daemon-reload
sudo systemctl enable crio --now

echo "CRI runtime installed susccessfully"

# Install kubelet, kubectl and Kubeadm

sudo apt-get update -y
sudo apt-get install -y apt-transport-https ca-certificates curl
sudo curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://dl.k8s.io/apt/doc/apt-key.gpg

echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update -y
sudo apt-get install -y kubelet="$KUBERNETES_VERSION" kubectl="$KUBERNETES_VERSION" kubeadm="$KUBERNETES_VERSION"
sudo apt-get update -y
sudo apt-get install -y jq

local_ip="$(ip --json addr show eth0 | jq -r '.[0].addr_info[] | select(.family == "inet") | .local')"
cat > /etc/default/kubelet << EOF
KUBELET_EXTRA_ARGS=--node-ip=$local_ip
EOF

# Adding hosts
# Define arrays for IP addresses and hostnames
IP_ADDRESSES=("172.16.1.16")
HOSTNAMES=("registry.iguidevietnam.com")

# Loop through the arrays and add entries to the hosts file
for ((i=0; i<${#IP_ADDRESSES[@]}; i++)); do
    IP_ADDRESS="${IP_ADDRESSES[i]}"
    HOSTNAME="${HOSTNAMES[i]"

    # Check if the entry already exists in the hosts file
    if grep -q "$IP_ADDRESS\s$HOSTNAME" /etc/hosts; then
        echo "Entry already exists in /etc/hosts: $IP_ADDRESS $HOSTNAME"
    else
        # Append the entry to the hosts file
        echo "$IP_ADDRESS $HOSTNAME" | sudo tee -a /etc/hosts
        echo "Entry added to /etc/hosts: $IP_ADDRESS $HOSTNAME"
    fi
done

# Define an array of insecure registry addresses
INSECURE_REGISTRIES=("registry.iguidevietnam.com")

# Function to check and add an insecure registry
add_insecure_registry() {
    local registry=$1

    # Check if the registry is already in the CRI-O configuration
    if grep -q "$registry" /etc/crio/crio.conf; then
        echo "Insecure registry $registry is already configured in CRI-O."
    else
        # Add the insecure registry to CRI-O configuration
        echo "Adding insecure registry $registry to CRI-O configuration..."
        echo "[registries.insecure]" | sudo tee -a /etc/crio/crio.conf
        echo "registries = [\"$registry\"]" | sudo tee -a /etc/crio/crio.conf

        # Restart CRI-O to apply the changes
        echo "Restarting CRI-O..."
        sudo systemctl restart crio

        echo "Insecure registry $registry added to CRI-O."
    }
}

# Loop through the array and add each insecure registry
for registry in "${INSECURE_REGISTRIES[@]}"; do
    add_insecure_registry "$registry"
done
