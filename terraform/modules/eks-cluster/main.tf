# terraform/modules/eks-cluster/main.tf
resource "aws_eks_cluster" "main" {
  name     = "${var.project_name}-eks-cluster"
  role_arn = aws_iam_role.eks_cluster_role.arn
  version = var.eks_version
  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [aws_security_group.eks_cluster_sg.id]
    endpoint_private_access = false # Keep public access for now for Jenkins/local kubectl
    endpoint_public_access  = true
  }
  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_service_policy,
  ]
  tags = {
    Name = "${var.project_name}-eks-cluster"
  }
}

resource "aws_iam_role" "eks_cluster_role" {
  name = "${var.project_name}-eks-cluster-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

resource "aws_iam_role_policy_attachment" "eks_service_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

resource "aws_security_group" "eks_cluster_sg" {
  name        = "${var.project_name}-eks-cluster-sg"
  description = "Security group for the EKS cluster control plane"
  vpc_id      = var.vpc_id

  # Allow inbound from worker nodes to control plane
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    security_groups = [aws_security_group.eks_node_group_sg.id]
  }
  # Allow all outbound (for EKS control plane to interact with AWS services)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "${var.project_name}-eks-cluster-sg"
  }
}

# EKS Node Group (Managed Node Group for simplicity)
resource "aws_eks_node_group" "app_nodes" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project_name}-app-nodes"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = var.private_subnet_ids # EKS nodes should be in private subnets
  instance_types  = ["t3.medium"] # Small instance, adjust as needed

  scaling_config {
    desired_size = 2
    max_size     = 4
    min_size     = 2
  }

  update_config {
    max_unavailable = 1
  }

  remote_access {
    ec2_ssh_key = "prod-kp" # <--- IMPORTANT: REPLACE WITH YOUR SSH KEY PAIR NAME
    source_security_group_ids = [aws_security_group.eks_node_group_sg.id] # Allow SSH from its own SG for self-management
  }

  # Allow communication to RDS from EKS node security group
  lifecycle {
    create_before_destroy = true
  }
  tags = {
    Name                                       = "${var.project_name}-eks-node-group"
    "eks.amazonaws.com/cluster-name"           = aws_eks_cluster.main.name
    "kubernetes.io/cluster/${aws_eks_cluster.main.name}" = "owned" # Required for some AWS services to discover the cluster
  }
}

resource "aws_iam_role" "eks_node_role" {
  name = "${var.project_name}-eks-node-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_container_registry_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_role.name
}

# Security group for the EKS nodes
resource "aws_security_group" "eks_node_group_sg" {
  name        = "${var.project_name}-eks-node-group-sg"
  description = "Security group for EKS worker nodes"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr] # Allow all internal VPC traffic
  }
  ingress {
    from_port   = 22 # SSH from specific IPs or Jumpserver
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["1.158.17.99/32"] # <--- IMPORTANT: RESTRICT THIS TO YOUR IP or JUMP SERVER
    description = "Allow SSH from specific IP"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"] # Allow all outbound internet access for updates, Docker Hub pull etc.
  }
  tags = {
    Name = "${var.project_name}-eks-node-group-sg"
  }
}

# Add ingress rule to RDS SG from EKS Node SG
resource "aws_security_group_rule" "eks_to_rds" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_node_group_sg.id
  security_group_id        = var.rds_security_group_id
  description              = "Allow EKS nodes to connect to RDS"
}