# SIEM EKS Cluster Infrastructure
terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
  }
}

provider "aws" {
  region = var.region
}

# Data source for availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Data source for current AWS caller identity
data "aws_caller_identity" "current" {}

# Variables
variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "siem-eks-cluster"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "node_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 4
}

variable "node_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 1
}

variable "node_instance_types" {
  description = "EC2 instance types for worker nodes"
  type        = list(string)
  default     = ["t3.medium"]
}

# VPC Configuration
resource "aws_vpc" "siem_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name                                        = "${var.cluster_name}-vpc"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    Project                                     = "SIEM"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "siem_igw" {
  vpc_id = aws_vpc.siem_vpc.id

  tags = {
    Name    = "${var.cluster_name}-igw"
    Project = "SIEM"
  }
}

# Public Subnets
resource "aws_subnet" "siem_public_subnets" {
  count = 2

  vpc_id                  = aws_vpc.siem_vpc.id
  cidr_block              = "10.0.${count.index + 1}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name                                        = "${var.cluster_name}-public-subnet-${count.index + 1}"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = "1"
    Project                                     = "SIEM"
  }
}

# Private Subnets
resource "aws_subnet" "siem_private_subnets" {
  count = 2

  vpc_id            = aws_vpc.siem_vpc.id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name                                        = "${var.cluster_name}-private-subnet-${count.index + 1}"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = "1"
    Project                                     = "SIEM"
  }
}

# NAT Gateway for private subnets
resource "aws_eip" "siem_nat_eip" {
  count  = 2
  domain = "vpc"

  tags = {
    Name    = "${var.cluster_name}-nat-eip-${count.index + 1}"
    Project = "SIEM"
  }

  depends_on = [aws_internet_gateway.siem_igw]
}

resource "aws_nat_gateway" "siem_nat_gw" {
  count = 2

  allocation_id = aws_eip.siem_nat_eip[count.index].id
  subnet_id     = aws_subnet.siem_public_subnets[count.index].id

  tags = {
    Name    = "${var.cluster_name}-nat-gw-${count.index + 1}"
    Project = "SIEM"
  }

  depends_on = [aws_internet_gateway.siem_igw]
}

# Route Tables
resource "aws_route_table" "siem_public_rt" {
  vpc_id = aws_vpc.siem_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.siem_igw.id
  }

  tags = {
    Name    = "${var.cluster_name}-public-rt"
    Project = "SIEM"
  }
}

resource "aws_route_table" "siem_private_rt" {
  count  = 2
  vpc_id = aws_vpc.siem_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.siem_nat_gw[count.index].id
  }

  tags = {
    Name    = "${var.cluster_name}-private-rt-${count.index + 1}"
    Project = "SIEM"
  }
}

# Route Table Associations
resource "aws_route_table_association" "siem_public_rta" {
  count = 2

  subnet_id      = aws_subnet.siem_public_subnets[count.index].id
  route_table_id = aws_route_table.siem_public_rt.id
}

resource "aws_route_table_association" "siem_private_rta" {
  count = 2

  subnet_id      = aws_subnet.siem_private_subnets[count.index].id
  route_table_id = aws_route_table.siem_private_rt[count.index].id
}

# Security Group for EKS Cluster
resource "aws_security_group" "siem_cluster_sg" {
  name_prefix = "${var.cluster_name}-cluster-sg"
  vpc_id      = aws_vpc.siem_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.cluster_name}-cluster-sg"
    Project = "SIEM"
  }
}

# Security Group for EKS Worker Nodes
resource "aws_security_group" "siem_node_sg" {
  name_prefix = "${var.cluster_name}-node-sg"
  vpc_id      = aws_vpc.siem_vpc.id

  ingress {
    from_port = 0
    to_port   = 65535
    protocol  = "tcp"
    self      = true
  }

  ingress {
    from_port       = 1025
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.siem_cluster_sg.id]
  }

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.siem_cluster_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.cluster_name}-node-sg"
    Project = "SIEM"
  }
}

# IAM Role for EKS Cluster
resource "aws_iam_role" "siem_cluster_role" {
  name = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })

  tags = {
    Name    = "${var.cluster_name}-cluster-role"
    Project = "SIEM"
  }
}

resource "aws_iam_role_policy_attachment" "siem_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.siem_cluster_role.name
}

# IAM Role for EKS Worker Nodes
resource "aws_iam_role" "siem_node_role" {
  name = "${var.cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })

  tags = {
    Name    = "${var.cluster_name}-node-role"
    Project = "SIEM"
  }
}

resource "aws_iam_role_policy_attachment" "siem_node_worker_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.siem_node_role.name
}

resource "aws_iam_role_policy_attachment" "siem_node_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.siem_node_role.name
}

resource "aws_iam_role_policy_attachment" "siem_node_registry_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.siem_node_role.name
}

# EKS Cluster
resource "aws_eks_cluster" "siem_cluster" {
  name     = var.cluster_name
  role_arn = aws_iam_role.siem_cluster_role.arn
  version  = "1.28"

  vpc_config {
    subnet_ids              = concat(aws_subnet.siem_private_subnets[*].id, aws_subnet.siem_public_subnets[*].id)
    endpoint_private_access = true
    endpoint_public_access  = true
    security_group_ids      = [aws_security_group.siem_cluster_sg.id]
  }

  depends_on = [
    aws_iam_role_policy_attachment.siem_cluster_policy,
  ]

  tags = {
    Name    = var.cluster_name
    Project = "SIEM"
  }
}

# EKS Node Group
resource "aws_eks_node_group" "siem_nodes" {
  cluster_name    = aws_eks_cluster.siem_cluster.name
  node_group_name = "${var.cluster_name}-nodes"
  node_role_arn   = aws_iam_role.siem_node_role.arn
  subnet_ids      = aws_subnet.siem_private_subnets[*].id
  instance_types  = var.node_instance_types

  scaling_config {
    desired_size = var.node_desired_size
    max_size     = var.node_max_size
    min_size     = var.node_min_size
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.siem_node_worker_policy,
    aws_iam_role_policy_attachment.siem_node_cni_policy,
    aws_iam_role_policy_attachment.siem_node_registry_policy,
  ]

  tags = {
    Name    = "${var.cluster_name}-nodes"
    Project = "SIEM"
  }
}

# Outputs
output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = aws_eks_cluster.siem_cluster.endpoint
}

output "cluster_security_group_id" {
  description = "Security group ids attached to the cluster control plane"
  value       = aws_eks_cluster.siem_cluster.vpc_config[0].cluster_security_group_id
}

output "cluster_iam_role_name" {
  description = "IAM role name associated with EKS cluster"
  value       = aws_iam_role.siem_cluster_role.name
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = aws_eks_cluster.siem_cluster.certificate_authority[0].data
}

output "cluster_iam_role_arn" {
  description = "IAM role ARN associated with EKS cluster"
  value       = aws_iam_role.siem_cluster_role.arn
}

output "node_groups" {
  description = "EKS node groups"
  value       = aws_eks_node_group.siem_nodes.arn
}

# Key Pair for EC2 instances
resource "aws_key_pair" "siem_key" {
  key_name   = "${var.cluster_name}-key"
  public_key = file("${path.module}/../siem-key.pub")

  tags = {
    Name    = "${var.cluster_name}-key-pair"
    Project = "SIEM"
  }
}

# Security Group for EC2 instances
resource "aws_security_group" "siem_ec2_sg" {
  name_prefix = "${var.cluster_name}-ec2-sg"
  vpc_id      = aws_vpc.siem_vpc.id

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP access for Splunk Universal Forwarder
  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # Splunk forwarder port
  ingress {
    from_port   = 9997
    to_port     = 9997
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.cluster_name}-ec2-sg"
    Project = "SIEM"
  }
}

# AMI data source for Amazon Linux 2
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# SIEM Server EC2 Instance (for demonstration/monitoring)
resource "aws_instance" "siem_server" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.medium"
  key_name               = aws_key_pair.siem_key.key_name
  subnet_id              = aws_subnet.siem_public_subnets[0].id
  vpc_security_group_ids = [aws_security_group.siem_ec2_sg.id]

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
    encrypted   = true
  }

  user_data = base64encode(templatefile("${path.module}/userdata/siem-server.sh", {
    cluster_name = var.cluster_name
  }))

  tags = {
    Name                = "${var.cluster_name}-siem-server"
    Project             = "SIEM"
    Role                = "SIEM-Server"
    Environment         = "Production"
    MonitoringTarget    = "true"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

# Client Instance 1 (for log generation and testing)
resource "aws_instance" "client_1" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  key_name               = aws_key_pair.siem_key.key_name
  subnet_id              = aws_subnet.siem_public_subnets[0].id
  vpc_security_group_ids = [aws_security_group.siem_ec2_sg.id]

  root_block_device {
    volume_type = "gp3"
    volume_size = 10
    encrypted   = true
  }

  user_data = base64encode(templatefile("${path.module}/userdata/client.sh", {
    cluster_name = var.cluster_name
    client_name  = "client-1"
  }))

  tags = {
    Name                = "${var.cluster_name}-client-1"
    Project             = "SIEM"
    Role                = "Log-Source"
    Environment         = "Production"
    MonitoringTarget    = "true"
    ClientType          = "Web-Server"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

# Client Instance 2 (for log generation and testing)
resource "aws_instance" "client_2" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  key_name               = aws_key_pair.siem_key.key_name
  subnet_id              = aws_subnet.siem_public_subnets[1].id
  vpc_security_group_ids = [aws_security_group.siem_ec2_sg.id]

  root_block_device {
    volume_type = "gp3"
    volume_size = 10
    encrypted   = true
  }

  user_data = base64encode(templatefile("${path.module}/userdata/client.sh", {
    cluster_name = var.cluster_name
    client_name  = "client-2"
  }))

  tags = {
    Name                = "${var.cluster_name}-client-2"
    Project             = "SIEM"
    Role                = "Log-Source"
    Environment         = "Production"
    MonitoringTarget    = "true"
    ClientType          = "Database-Server"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

# Outputs
output "vpc_id" {
  description = "ID of the VPC where the cluster is deployed"
  value       = aws_vpc.siem_vpc.id
}

output "siem_server_public_ip" {
  description = "Public IP address of the SIEM server"
  value       = aws_instance.siem_server.public_ip
}

output "siem_server_private_ip" {
  description = "Private IP address of the SIEM server"
  value       = aws_instance.siem_server.private_ip
}

output "client_1_public_ip" {
  description = "Public IP address of client 1"
  value       = aws_instance.client_1.public_ip
}

output "client_1_private_ip" {
  description = "Private IP address of client 1"
  value       = aws_instance.client_1.private_ip
}

output "client_2_public_ip" {
  description = "Public IP address of client 2"
  value       = aws_instance.client_2.public_ip
}

output "client_2_private_ip" {
  description = "Private IP address of client 2"
  value       = aws_instance.client_2.private_ip
}

output "ssh_connection_commands" {
  description = "SSH commands to connect to instances"
  value = {
    siem_server = "ssh -i siem-key.pem ec2-user@${aws_instance.siem_server.public_ip}"
    client_1    = "ssh -i siem-key.pem ec2-user@${aws_instance.client_1.public_ip}"
    client_2    = "ssh -i siem-key.pem ec2-user@${aws_instance.client_2.public_ip}"
  }
}
