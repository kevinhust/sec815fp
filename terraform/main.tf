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

# Use existing VPC
data "aws_vpc" "siem_vpc" {
  filter {
    name   = "tag:Name"
    values = ["siem-eks-cluster-vpc"]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
}

# Network infrastructure already exists in the VPC

# Use existing subnets
data "aws_subnets" "siem_public_subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.siem_vpc.id]
  }
  filter {
    name   = "tag:kubernetes.io/role/elb"
    values = ["1"]
  }
}

data "aws_subnets" "siem_private_subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.siem_vpc.id]
  }
  filter {
    name   = "tag:kubernetes.io/role/internal-elb"
    values = ["1"]
  }
}

# Network routing already configured in existing VPC

# Security Group for EKS Cluster
resource "aws_security_group" "siem_cluster_sg" {
  name_prefix = "${var.cluster_name}-cluster-sg"
  vpc_id      = data.aws_vpc.siem_vpc.id

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
  vpc_id      = data.aws_vpc.siem_vpc.id

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

# Use existing IAM Role for EKS Cluster
data "aws_iam_role" "siem_cluster_role" {
  name = "${var.cluster_name}-cluster-role"
}

# Use existing IAM Role for EKS Worker Nodes
data "aws_iam_role" "siem_node_role" {
  name = "${var.cluster_name}-node-role"
}

# EKS Cluster
resource "aws_eks_cluster" "siem_cluster" {
  name     = var.cluster_name
  role_arn = data.aws_iam_role.siem_cluster_role.arn
  version  = "1.28"

  vpc_config {
    subnet_ids              = concat(data.aws_subnets.siem_private_subnets.ids, data.aws_subnets.siem_public_subnets.ids)
    endpoint_private_access = true
    endpoint_public_access  = true
    security_group_ids      = [aws_security_group.siem_cluster_sg.id]
  }

  # IAM roles and policies already exist

  tags = {
    Name    = var.cluster_name
    Project = "SIEM"
  }
}

# EKS Node Group
resource "aws_eks_node_group" "siem_nodes" {
  cluster_name    = aws_eks_cluster.siem_cluster.name
  node_group_name = "${var.cluster_name}-nodes"
  node_role_arn   = data.aws_iam_role.siem_node_role.arn
  subnet_ids      = data.aws_subnets.siem_private_subnets.ids
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
  value       = data.aws_iam_role.siem_cluster_role.name
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = aws_eks_cluster.siem_cluster.certificate_authority[0].data
}

output "cluster_iam_role_arn" {
  description = "IAM role ARN associated with EKS cluster"
  value       = data.aws_iam_role.siem_cluster_role.arn
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
  vpc_id      = data.aws_vpc.siem_vpc.id

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
  subnet_id              = data.aws_subnets.siem_public_subnets.ids[0]
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
  subnet_id              = data.aws_subnets.siem_public_subnets.ids[0]
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
  subnet_id              = data.aws_subnets.siem_public_subnets.ids[1]
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
  value       = data.aws_vpc.siem_vpc.id
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
