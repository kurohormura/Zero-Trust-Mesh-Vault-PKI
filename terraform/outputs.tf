output "instance_public_ip" {
  description = "Public IPv4 of the Headscale control EC2 instance"
  value       = aws_instance.headscale_node.public_ip
}

output "ssh_command" {
  description = "Command to connect to the node"
  value       = "ssh -i ~/.ssh/id_ed25519_mesh ubuntu@${aws_instance.headscale_node.public_ip}"
}
