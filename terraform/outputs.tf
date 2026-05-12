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

output "ansible_command" {
  description = "Ansible command to run manually (e.g. from WSL on Windows)"
  value       = <<-EOT
    ansible-playbook \
      -i '${aws_instance.minecraft.public_ip},' \
      --private-key ~/.ssh/cs312-key.pem \
      -u ec2-user \
      -e "ecr_image_uri=${var.ecr_image_uri}" \
      -e "s3_backup_bucket=${var.s3_backup_bucket}" \
      -e "student_id=${var.student_id}" \
      ../ansible/playbook.yml
  EOT
}
