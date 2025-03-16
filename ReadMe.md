# Kubernetes on AWS with Terraform

This project automates the deployment of a Kubernetes control plane on AWS using Terraform. The setup includes:

- Provisioning AWS resources (EC2 instance, security group, EBS volume, and S3 bucket for Terraform state)
- Configuring a remote Terraform backend for centralized state storage, collaboration, security, and consistency
- Automating the installation and initialization of a Kubernetes control plane via a custom user data script
- Deploying essential add-ons (Flannel, Metrics Server, and Ingress-NGINX)

![Architecture Diagram](architecture.png)

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Installation Steps](#installation-steps)
- [Usage](#usage)
- [Project Structure](#project-structure)
- [Troubleshooting](#troubleshooting)
- [License](#license)

## Overview

Deploying a Kubernetes cluster on AWS can be challenging, especially when you want a reproducible and automated setup. This project leverages Terraform to provision AWS resources and automate the Kubernetes control plane deployment using a custom user data script. The approach ensures a consistent, version-controlled infrastructure and makes collaboration easier.

## Prerequisites

Before getting started, ensure you have:

- An AWS account with the necessary permissions
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) installed and configured
- [Terraform](https://developer.hashicorp.com/terraform/install) installed
- A key pair created in AWS (e.g., `codegenitor_keypair`)
- Git installed on your machine

## Installation Steps

### 1. Install and Configure AWS CLI

- Install the AWS CLI by following the official guide.
- Run `aws configure` to set up your credentials, region (e.g., `us-east-1`), and output format (e.g., `json`).

### 2. Install Terraform

- Follow the [Terraform Installation Guide](https://developer.hashicorp.com/terraform/install) to install the latest version.
- Verify installation with:
  ```bash
  terraform version
  ```

### 3. Set Up .gitignore

Create a `.gitignore` file to exclude Terraform state files, sensitive variable files, and IDE settings:

```gitignore
# Terraform state files
*.tfstate
*.tfstate.*
terraform.tfplan
.terraform/

# Sensitive variable files
*.tfvars

# IDE directories
.vscode/
.idea/

# OS-specific files
.DS_Store
```

### 4. Create an AWS Key Pair

- In the AWS Console, navigate to the EC2 Dashboard → **Key Pairs** and create a new key pair (e.g., `codegenitor_keypair`).
- Download and securely store the `.pem` file.

### 5. Configure Terraform Variables

Create a file named `IAC/variables.tf` with the following content:

```hcl
variable "region" {
  description = "The region in which the resources will be created"
  default     = "us-east-1"
}

variable "availability_zone" {
  description = "The availability zone in which the resources will be created"
  default     = "us-east-1a"
}

variable "AMI" {
  description = "The AMI to use for the EC2 instance"
  default     = "ami-04b4f1a9cf54c11d0"  # Update with your preferred AMI
}

variable "instance_type" {
  description = "The type of EC2 instance to create"
  default     = "t2.medium"
}

variable "codegenitor_keypair" {
  description = "The name of the key pair to use for the EC2 instance"
  default     = "codegenitor_keypair"
}

variable "VPC_ID" {
  description = "The VPC ID to use for the instance"
  default     = "vpc-0c4be51003fc3c274"  # Update with your VPC ID
}

variable "volume_size" {
  description = "The size of the EBS volume to attach to the instance"
  default     = 50
}
```

### 6. Create the S3 Bucket for Terraform State

Create a file named `IAC/s3_bucket.tf`:

```hcl
resource "aws_s3_bucket" "codegenitor_IAC" {
  bucket        = "codegenitor-iac"  # Ensure the bucket name is unique
  force_destroy = true
  tags = {
    Name = "terraform_Bucket_State"
  }
}
```

### 7. Configure the Terraform Backend

Create a file named `IAC/terraform.config.tf`:

```hcl
terraform {
  backend "s3" {
    bucket = "codegenitor-iac"
    key    = "terraform/terraform.tfstate"
    region = "us-east-1"
  }
}
```

Initialize Terraform and migrate the state:

```bash
terraform init -migrate-state
```

### 8. Create the Security Group

Create a file named `IAC/security_group.tf`:

```hcl
resource "aws_security_group" "codegenitor_IAC" {
  name        = "codegenitor_web_security"
  description = "Allow inbound traffic on port 80, 443, 22"
  vpc_id      = var.VPC_ID

  tags = {
    Name = "web_security"
  }

  ingress {
    description = "Allow SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

### 9. Create the EC2 Instance and Attach an EBS Volume

Create a file named `IAC/resources.tf`:

```hcl
## Create the EBS volume
resource "aws_ebs_volume" "codegenitor_IAC" {
  availability_zone = var.availability_zone
  size              = var.volume_size
  tags = {
    Name = "k8s_volume"
  }
}

## Create the EC2 web server and install Kubernetes on it ##
resource "aws_instance" "codegenitor_web_server" {
  depends_on                  = [aws_security_group.codegenitor_IAC]
  ami                         = var.AMI
  instance_type               = var.instance_type
  key_name                    = var.codegenitor_keypair
  vpc_security_group_ids      = [aws_security_group.codegenitor_IAC.id]
  user_data                   = file("IAC/user_data.sh")
  associate_public_ip_address = true
  tags = {
    Name = "codegenitor_web_server"
  }
}

## Attach the volume to the EC2 instance ##
resource "aws_volume_attachment" "codegenitor_IAC" {
  depends_on   = [aws_instance.codegenitor_web_server]
  device_name  = "/dev/sdf"
  volume_id    = aws_ebs_volume.codegenitor_IAC.id
  instance_id  = aws_instance.codegenitor_web_server.id
  force_detach = true
}
```

### 10. The User Data Script

Create a file named `IAC/user_data.sh` with the following content:

```bash
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

# Apply a pod network (Flannel)
sudo -u ubuntu kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml

# Install metrics-server
sudo -u ubuntu kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
sudo -u ubuntu kubectl patch deployment metrics-server -n kube-system --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'

# Install ingress-nginx controller and patch service type to NodePort
sudo -u ubuntu kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml -n ingress-nginx
sudo -u ubuntu kubectl patch svc ingress-nginx-controller -n ingress-nginx -p '{"spec": {"type": "NodePort"}}'
```

---

## Final Thoughts

By following this guide, you now have a fully automated process to deploy a Kubernetes control plane on AWS using Terraform. This setup:

- Provides centralized state management using an S3 backend.
- Ensures robust security through properly configured security groups.
- Automates cluster initialization with a custom user data script that resets any existing configurations.
- Deploys essential Kubernetes add-ons for networking, metrics, and ingress management.

Deploy your infrastructure as code, reduce manual errors, and enjoy a reproducible Kubernetes environment on AWS!

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
