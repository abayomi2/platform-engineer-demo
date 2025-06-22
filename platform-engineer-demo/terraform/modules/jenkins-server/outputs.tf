# terraform/modules/jenkins-server/outputs.tf
output "jenkins_public_ip" {
  value = aws_instance.jenkins_server.public_ip
}

output "jenkins_security_group_id" {
  value = aws_security_group.jenkins_sg.id
}

# NEW: Output the ARN of the Jenkins IAM role
output "jenkins_role_arn" {
  description = "The ARN of the IAM role attached to the Jenkins EC2 instance."
  value       = aws_iam_role.jenkins_role.arn
}