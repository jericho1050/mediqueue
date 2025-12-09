terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# Data sources to get current AWS account info
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# IAM Role for EC2 to access ECR
resource "aws_iam_role" "k8s_node_role" {
  name = "mediqueue-k8s-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = { Name = "mediqueue-k8s-node-role" }
}

# Policy to allow ECR pull
resource "aws_iam_role_policy" "ecr_pull_policy" {
  name = "mediqueue-ecr-pull-policy"
  role = aws_iam_role.k8s_node_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      }
    ]
  })
}

# Instance Profile (attaches role to EC2)
resource "aws_iam_instance_profile" "k8s_node_profile" {
  name = "mediqueue-k8s-node-profile"
  role = aws_iam_role.k8s_node_role.name
}

# 1. Find the latest Ubuntu 22.04 AMI (Amazon Machine Image)
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical (Ubuntu creators)

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# 2. Create the Key Pair (So you can SSH into it)
# Make sure you have a public key on your mac at ~/.ssh/id_ed25519.pub
# If not, run: ssh-keygen -t ed25519
resource "aws_key_pair" "deployer" {
  key_name   = "mediqueue-key"
  public_key = file("~/.ssh/id_ed25519.pub") # <--- ENSURE THIS PATH IS CORRECT
}

# 3. The Server itself (EC2 Instance)
resource "aws_instance" "k8s_node" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.ec2_instance_type

  subnet_id                   = aws_subnet.public_1.id
  vpc_security_group_ids      = [aws_security_group.k8s_sg.id]
  key_name                    = aws_key_pair.deployer.key_name
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.k8s_node_profile.name

  # Root volume - 30GB for K8s + Docker images
  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    delete_on_termination = true
  }

  # 4. The Magic Script (Installs K3s on boot)
  user_data = <<-EOF
              #!/bin/bash
              set -e

              # Update and install utilities
              apt-get update
              apt-get install -y curl unzip

              # Install AWS CLI v2
              curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
              unzip -q awscliv2.zip
              ./aws/install
              rm -rf aws awscliv2.zip

              # Install K3s (Lightweight Kubernetes)
              curl -sfL https://get.k3s.io | sh -

              # Wait for K3s to be ready (up to 120 seconds)
              echo "Waiting for K3s to be ready..."
              for i in {1..120}; do
                if [ -f /etc/rancher/k3s/k3s.yaml ] && kubectl get nodes &>/dev/null; then
                  break
                fi
                sleep 1
              done

              # Allow the default user (ubuntu) to read the kubeconfig
              mkdir -p /home/ubuntu/.kube
              cp /etc/rancher/k3s/k3s.yaml /home/ubuntu/.kube/config
              chown ubuntu:ubuntu /home/ubuntu/.kube/config
              chmod 600 /home/ubuntu/.kube/config

              # Add alias for easier typing
              echo "alias k=kubectl" >> /home/ubuntu/.bashrc
              echo "export KUBECONFIG=/home/ubuntu/.kube/config" >> /home/ubuntu/.bashrc

              # Install Helm
              curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

              chmod 644 /etc/rancher/k3s/k3s.yaml # Make sure the kubeconfig file is readable by the ubuntu user

              # Create mediqueue namespace
              kubectl create namespace mediqueue --dry-run=client -o yaml | kubectl apply -f -

              # Create ECR pull secret for K3s (refreshed by cron)
              AWS_REGION="${data.aws_region.current.name}"
              AWS_ACCOUNT="${data.aws_caller_identity.current.account_id}"
              ECR_REGISTRY="$AWS_ACCOUNT.dkr.ecr.$AWS_REGION.amazonaws.com"
              
              # Get ECR password and create k8s secret
              ECR_TOKEN=$(aws ecr get-login-password --region $AWS_REGION)
              kubectl create secret docker-registry ecr-registry-secret \
                --namespace=mediqueue \
                --docker-server=$ECR_REGISTRY \
                --docker-username=AWS \
                --docker-password=$ECR_TOKEN \
                --dry-run=client -o yaml | kubectl apply -f -

              # Create cron job to refresh ECR token every 6 hours (token expires in 12h)
              cat > /usr/local/bin/refresh-ecr-token.sh << 'SCRIPT'
              #!/bin/bash
              AWS_REGION="${data.aws_region.current.name}"
              AWS_ACCOUNT="${data.aws_caller_identity.current.account_id}"
              ECR_REGISTRY="$AWS_ACCOUNT.dkr.ecr.$AWS_REGION.amazonaws.com"
              ECR_TOKEN=$(aws ecr get-login-password --region $AWS_REGION)
              kubectl create secret docker-registry ecr-registry-secret \
                --namespace=mediqueue \
                --docker-server=$ECR_REGISTRY \
                --docker-username=AWS \
                --docker-password=$ECR_TOKEN \
                --dry-run=client -o yaml | kubectl apply -f -
              SCRIPT
              chmod +x /usr/local/bin/refresh-ecr-token.sh
              
              # Add to crontab (every 6 hours)
              echo "0 */6 * * * /usr/local/bin/refresh-ecr-token.sh" | crontab -

              echo "Setup complete!"
              EOF

  tags = {
    Name = var.instance_name
  }

  depends_on = [aws_iam_instance_profile.k8s_node_profile]
}

# Elastic IP for stable public IP address
resource "aws_eip" "k8s_node_eip" {
  domain = "vpc"

  tags = { Name = "mediqueue-k8s-eip" }
}

# Associate Elastic IP with EC2 instance
resource "aws_eip_association" "k8s_node_eip_assoc" {
  instance_id   = aws_instance.k8s_node.id
  allocation_id = aws_eip.k8s_node_eip.id
}

# The hospital grounds (VPC)
resource "aws_vpc" "mediqueue_vpc" {
  cidr_block           = var.cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "mediqueue_vpc" }
}

# The main Gate (internet gateway)
# without this, the VPC would be isolated and no internet access would be possible
resource "aws_internet_gateway" "mediqueue_igw" {
  vpc_id = aws_vpc.mediqueue_vpc.id

  tags = { Name = "mediqueue_igw" }
}

# e.g Ward A (Public Subnet)
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.mediqueue_vpc.id
  cidr_block              = var.public_subnet_1_cidr_block
  availability_zone       = var.availability_zone_1
  map_public_ip_on_launch = true

  tags = { Name = "mediqueue_public_1" }
}

# e.g Ward B (Public Subnet)
resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.mediqueue_vpc.id
  cidr_block              = var.public_subnet_2_cidr_block
  availability_zone       = var.availability_zone_2
  map_public_ip_on_launch = true

  tags = { Name = "mediqueue_public_2" }
}

# The hospital Map (Route Table)
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.mediqueue_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.mediqueue_igw.id
  }

  tags = { Name = "mediqueue_public_route_table" }
}

# Hang the map in Ward A
resource "aws_route_table_association" "public_route_table_association_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public_route_table.id
}

# Hang the map in Ward B
resource "aws_route_table_association" "public_route_table_association_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public_route_table.id
}

# Security Guards | Security Groups (firewalls)
resource "aws_security_group" "k8s_sg" {
  name        = "mediqueue_sg"
  description = "Cluster Firewall"
  vpc_id      = aws_vpc.mediqueue_vpc.id

  # Allow SSH (port 22) - Required to access the server
  ingress {
    description = "Allow SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ip]
  }

  # Allow HTTP (port 80) traffic from the internet
  ingress {
    description = "Allow HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ip]
  }

  # Allow HTTPS (port 443) traffic from the internet
  ingress {
    description = "Allow HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ip]
  }

  # Allow Kubernetes API (port 6443) - Required for kubectl access
  ingress {
    description = "Allow K8s API"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ip]
  }

  # Allow OUTBOUND traffic to the internet (So nodes can download images, etc)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "mediqueue_sg" }
}

# ECR Repositories
resource "aws_ecr_repository" "api" {
  name                 = var.image_repository_api
  image_tag_mutability = "MUTABLE"
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Name = "mediqueue-api" }
}

resource "aws_ecr_repository" "worker" {
  name                 = var.image_repository_worker
  image_tag_mutability = "MUTABLE"
  force_delete = true
  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Name = "mediqueue-worker" }
}

resource "aws_ecr_repository" "frontend" {
  name                 = var.image_repository_frontend
  image_tag_mutability = "MUTABLE"
  force_delete = true 
  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Name = "mediqueue-frontend" }
}

# ECR Repository Policies (restrict to current account only)
resource "aws_ecr_repository_policy" "api" {
  repository = aws_ecr_repository.api.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowPull"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
      }
    ]
  })
}

resource "aws_ecr_repository_policy" "worker" {
  repository = aws_ecr_repository.worker.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowPull"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
      }
    ]
  })
}

resource "aws_ecr_repository_policy" "frontend" {
  repository = aws_ecr_repository.frontend.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowPull"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
      }
    ]
  })
}
