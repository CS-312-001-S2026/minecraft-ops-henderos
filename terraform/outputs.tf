output "instance_public_ip" {
  description = "Public IP of the Minecraft server — use this for nmap and Minecraft client"
  value       = aws_instance.minecraft.public_ip
}

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.minecraft.id
}

output "security_group_id" {
  description = "Security group ID"
  value       = aws_security_group.minecraft.id
}

output "ssh_command" {
  description = "SSH command to access the host"
  value       = "ssh -i ~/.ssh/cs312-key.pem ec2-user@${aws_instance.minecraft.public_ip}"
}

output "bootstrap_log" {
  description = "Command to tail cloud-init bootstrap progress on the host"
  value       = "ssh -i ~/.ssh/cs312-key.pem ec2-user@${aws_instance.minecraft.public_ip} sudo tail -f /var/log/cloud-init-minecraft.log"
}
