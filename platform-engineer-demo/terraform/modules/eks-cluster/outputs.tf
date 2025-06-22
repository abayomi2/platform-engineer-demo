# terraform/modules/eks-cluster/outputs.tf
output "cluster_name" {
  value = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.main.endpoint
}

output "cluster_certificate_authority_data" {
  value = aws_eks_cluster.main.certificate_authority[0].data
}
# terraform/modules/eks-cluster/outputs.tf
output "eks_node_group_sg_id" {
  description = "The Security Group ID of the EKS Node Group."
  value       = aws_security_group.eks_node_group_sg.id
}

# NEW: Output the ARN of the EKS Node Group IAM role
output "node_group_role_arn" {
  description = "The ARN of the IAM role used by the EKS node group."
  value       = aws_iam_role.eks_node_role.arn
}