# terraform/modules/jenkins-server/main.tf
resource "aws_instance" "jenkins_server" {
  ami           = "ami-0f3f13f145e66a0a3" # Amazon Linux 2 (HVM), SSD Volume Type. Find latest for your region!
  instance_type = "t3.medium" # t2.medium/t3.medium recommended for Jenkins
  subnet_id     = var.public_subnet_id
  vpc_security_group_ids = [aws_security_group.jenkins_sg.id]
  key_name      = "prod-kp" # <--- IMPORTANT: REPLACE WITH YOUR SSH KEY PAIR NAME
  associate_public_ip_address = true # Jenkins will be accessible via public IP
  root_block_device {
    volume_size = 30 # NEW: Increased size to 30 GiB
    volume_type = "gp2" # Keep as gp2, or change to gp3 for better performance/cost if desired
    delete_on_termination = true # Explicitly set to true for clean destroy
  }
  # IAM Instance Profile for Jenkins to access AWS services (ECR, EKS, Secrets Manager)
  iam_instance_profile = aws_iam_instance_profile.jenkins_profile.name

  user_data = templatefile("${path.module}/install_jenkins.sh.tpl", {
  EKS_CLUSTER_NAME = var.eks_cluster_name
  AWS_REGION       = var.aws_region
  JAVA_HOME        = "/usr/lib/jvm/java-17-amazon-corretto" # Or the correct path for Corretto 17

})
user_data_replace_on_change = true

  tags = {
    Name = "${var.project_name}-jenkins-server"
  }
}

resource "aws_security_group" "jenkins_sg" {
  name        = "${var.project_name}-jenkins-sg"
  description = "Security group for Jenkins server"
  vpc_id      = var.vpc_id

  # Allow SSH from your IP
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["1.158.17.99/32"] # <--- IMPORTANT: RESTRICT THIS TO YOUR IP(I am using my local PC IP as an example)
    description = "Allow SSH from specific IP"
  }

  # Allow HTTP for Jenkins UI
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # <--- IMPORTANT: RESTRICT THIS IN PRODUCTION!
    description = "Allow HTTP for Jenkins UI"
  }

  # Allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "${var.project_name}-jenkins-sg"
  }
}

# IAM Role for Jenkins EC2 Instance
resource "aws_iam_role" "jenkins_role" {
  name = "${var.project_name}-jenkins-role"
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

resource "aws_iam_role_policy_attachment" "jenkins_s3_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess" # For storing build artifacts, etc.
  role       = aws_iam_role.jenkins_role.name
}

resource "aws_iam_role_policy_attachment" "jenkins_ecr_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess" # To push images to ECR
  role       = aws_iam_role.jenkins_role.name
}

resource "aws_iam_role_policy_attachment" "jenkins_eks_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy" # For Jenkins to interact with EKS
  role       = aws_iam_role.jenkins_role.name
}

resource "aws_iam_role_policy_attachment" "jenkins_secrets_manager_policy" {
  policy_arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite" # To read/write secrets (e.g., Docker Hub creds)
  role       = aws_iam_role.jenkins_role.name
}

# Required for EKS authentication for instance roles
resource "aws_iam_role_policy_attachment" "jenkins_eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.jenkins_role.name
}

resource "aws_iam_instance_profile" "jenkins_profile" {
  name = "${var.project_name}-jenkins-profile"
  role = aws_iam_role.jenkins_role.name
}