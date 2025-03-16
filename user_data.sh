#!/bin/bash

# Fix IPv4 issue for apt-get
sudo tee /etc/apt/apt.conf.d/99force-ipv4 <<EOF
Acquire::ForceIPv4 "true";
EOF

# Update the system and upgrade packages
sudo apt-get update && sudo apt-get upgrade -y

# Disable swap (required by Kubernetes)
sudo swapoff -a

# Load required kernel modules
sudo tee /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Set sysctl parameters for Kubernetes networking
sudo tee /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system

# Install containerd
sudo apt-get update
sudo apt-get install -y containerd
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml

# Adjust containerd configuration for Kubernetes
sudo sed -i '/disable_cgroup/s/=.*/= false/' /etc/containerd/config.toml
sudo sed -i '/\[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options\]/,/\[/{s/SystemdCgroup\s*=.*/SystemdCgroup = true/}' /etc/containerd/config.toml

sudo systemctl restart containerd

# Install Kubernetes apt repository and components
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl

# Verify installation of Kubernetes components
dpkg -l | grep -E 'kubeadm|kubelet|kubectl'
kubectl version --client
sudo systemctl status kubelet

# Set up kubectl autocompletion and alias for the ubuntu user
sudo -u ubuntu bash -c 'echo "source <(kubectl completion bash)" >> /home/ubuntu/.bashrc'
sudo -u ubuntu bash -c 'cat <<EOF >> /home/ubuntu/.bashrc
alias k=kubectl
complete -o default -F __start_kubectl k
export KUBECONFIG=/home/ubuntu/.kube/config
EOF'

# Get the instance's private IP for API server advertise address
ADVERTISE_IP=$(hostname -I | awk '{print $1}')

# Check for existing Kubernetes configuration and reset if found
if [ -f /etc/kubernetes/admin.conf ]; then
  echo "Existing Kubernetes configuration detected. Resetting cluster..."
  sudo kubeadm reset -f
  sudo rm -rf /etc/kubernetes/manifests/*
  sudo rm -rf /var/lib/etcd
else
  echo "No existing Kubernetes configuration found. Proceeding with initialization."
fi

# Generate a kubeadm configuration file with a custom node name and cluster name
cat <<EOF | sudo tee /tmp/kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
nodeRegistration:
  name: codegenitor-controlplane
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
clusterName: controlplane-cluster
apiServer:
  extraArgs:
    advertise-address: "${ADVERTISE_IP}"
networking:
  podSubnet: "10.244.0.0/16"
EOF

# Initialize Kubernetes master node using the generated configuration
sudo kubeadm init --config=/tmp/kubeadm-config.yaml

# Configure kubectl for the root user (optional)
mkdir -p $HOME/.kube
sudo cp -f /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Configure kubectl for the ubuntu user
sudo mkdir -p /home/ubuntu/.kube
sudo cp -f /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
sudo chown ubuntu:ubuntu /home/ubuntu/.kube/config

# Apply a pod network (Flannel in this case)
sudo -u ubuntu kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml

# Install metrics-server
sudo -u ubuntu kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
sudo -u ubuntu kubectl patch deployment metrics-server -n kube-system --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'

# Install ingress-nginx controller and patch service type to NodePort
sudo -u ubuntu kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml -n ingress-nginx
sudo -u ubuntu kubectl patch svc ingress-nginx-controller -n ingress-nginx -p '{"spec": {"type": "NodePort"}}'
