#!/bin/bash
#
# Setup for Control Plane (Master) servers

set -euxo pipefail

# If you need public access to API server using the servers Public IP adress, change PUBLIC_IP_ACCESS to true.

PUBLIC_IP_ACCESS="true"
NODENAME=$(hostname -s)
POD_CIDR="192.168.0.0/16"
NETWORK_INTERFACE=""

# Pull required images

sudo kubeadm config images pull

# Initialize kubeadm based on PUBLIC_IP_ACCESS

if [[ "$PUBLIC_IP_ACCESS" == "false" ]]; then
    
    MASTER_PRIVATE_IP=$(ip addr show $NETWORK_INTERFACE | awk '/inet / {print $2}' | cut -d/ -f1)
    sudo kubeadm init --apiserver-advertise-address="$MASTER_PRIVATE_IP" --apiserver-cert-extra-sans="$MASTER_PRIVATE_IP" --pod-network-cidr="$POD_CIDR" --node-name "$NODENAME" --ignore-preflight-errors Swap

elif [[ "$PUBLIC_IP_ACCESS" == "true" ]]; then

    MASTER_PUBLIC_IP=$(curl ifconfig.me && echo "")
    
    sudo kubeadm init --control-plane-endpoint="$MASTER_PUBLIC_IP" --apiserver-cert-extra-sans="$MASTER_PUBLIC_IP" --pod-network-cidr="$POD_CIDR" --node-name "$NODENAME" --ignore-preflight-errors Swap

else
    echo "Error: MASTER_PUBLIC_IP has an invalid value: $PUBLIC_IP_ACCESS"
    exit 1
fi

# Configure kubeconfig

mkdir -p "$HOME"/.kube
sudo cp -i /etc/kubernetes/admin.conf "$HOME"/.kube/config
sudo chown "$(id -u)":"$(id -g)" "$HOME"/.kube/config

# Install Claico Network Plugin Network for premise

curl https://raw.githubusercontent.com/projectcalico/calico/v3.26.4/manifests/calico.yaml -O

kubectl apply -f calico.yaml

#ohmyzsh
echo "Installing Zsh..."
if [ "$(uname)" == "Darwin" ]; then
  # macOS
  brew install zsh
elif [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]; then
  # Linux
  sudo apt-get install zsh
fi

# Install Oh My Zsh plugins
echo "Installing zsh-autosuggestions plugin..."
git clone https://github.com/zsh-users/zsh-autosuggestions ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions

echo "Installing kubectl plugin..."
git clone https://github.com/ohmyzsh/ohmyzsh.git ~/.oh-my-zsh/custom/plugins/kubectl

# Update Zsh configuration to include plugins and set theme
echo "Updating Zsh configuration..."
sed -i '/^plugins=(/s/)$/ zsh-autosuggestions kubectl kubectx)/' ~/.zshrc
sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="agnoster"/' ~/.zshrc


# Add Kubernetes configuration template
cat <<'EOF' >> ~/.zshrc

# Kubernetes configuration
export KUBECONFIG=$HOME/.kube/config

# kubectx and kubens configuration
export FZF_DEFAULT_OPTS='--height 40% --reverse --border'
source <(kubectl completion zsh)


# Alias for kubectl
alias k=kubectl
complete -F __start_kubectl k
EOF

echo "Installation complete. Please restart your terminal or log out and log back in."
