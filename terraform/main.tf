provider "aws" {
  region = var.aws_region
}

# 1. Isolated VPC & Networking
resource "aws_vpc" "mesh_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "mesh-vpc"
  }
}

resource "aws_subnet" "mesh_public_subnet" {
  vpc_id                  = aws_vpc.mesh_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"

  tags = {
    Name = "mesh-public-subnet"
  }
}

resource "aws_internet_gateway" "mesh_igw" {
  vpc_id = aws_vpc.mesh_vpc.id

  tags = {
    Name = "mesh-igw"
  }
}

resource "aws_route_table" "mesh_rt" {
  vpc_id = aws_vpc.mesh_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.mesh_igw.id
  }

  tags = {
    Name = "mesh-public-rt"
  }
}

resource "aws_route_table_association" "mesh_rta" {
  subnet_id      = aws_subnet.mesh_public_subnet.id
  route_table_id = aws_route_table.mesh_rt.id
}

# 2. Strict Ingress Security Group
resource "aws_security_group" "mesh_sg" {
  name        = "headscale-control-sg"
  description = "Allow inbound SSH, Headscale TLS, and DERP/STUN"
  vpc_id      = aws_vpc.mesh_vpc.id

  # SSH
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Headscale TLS & ACME challenges
  ingress {
    description = "HTTPS Headscale Control"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTP ACME Challenge"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Headscale DERP Relay / STUN
  ingress {
    description = "Headscale STUN / DERP"
    from_port   = 3478
    to_port     = 3478
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # All outbound traffic
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "mesh-security-group"
  }
}

# 3. SSH Key Pair
resource "aws_key_pair" "mesh_key" {
  key_name   = "mesh-operator-key"
  public_key = file(var.public_key_path)
}

# 4. AMI Lookup for Ubuntu 24.04 Noble LTS
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# 5. EC2 Control Plane Node
resource "aws_instance" "headscale_node" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.mesh_public_subnet.id
  vpc_security_group_ids      = [aws_security_group.mesh_sg.id]
  key_name                    = aws_key_pair.mesh_key.key_name
  associate_public_ip_address = true

  root_block_device {
    volume_size           = 20 # Under AWS 30 GB Free Tier limit
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "headscale-control-01"
    Role = "control-plane"
  }
}
