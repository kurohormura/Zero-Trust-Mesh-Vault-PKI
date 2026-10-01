variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance size (t3.micro is Free Tier eligible)"
  type        = string
  default     = "t3.micro"
}

variable "public_key_path" {
  description = "Local path to your SSH public key"
  type        = string
  default     = "~/.ssh/id_ed25519_mesh.pub"
}
