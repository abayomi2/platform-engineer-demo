
#!/bin/bash
set -eux

# Install Java (Amazon Corretto 17)
sudo yum install -y java-17-amazon-corretto

# Dynamically detect JAVA_HOME and export it
echo "export JAVA_HOME=\$(dirname \$(dirname \$(readlink -f \$(which java))))" | sudo tee /etc/profile.d/java.sh
echo 'export PATH=$JAVA_HOME/bin:$PATH' | sudo tee -a /etc/profile.d/java.sh
sudo chmod +x /etc/profile.d/java.sh
source /etc/profile.d/java.sh

# Install Docker
sudo amazon-linux-extras enable docker
sudo yum clean metadata
sudo yum install -y docker
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker ec2-user
sudo usermod -aG docker jenkins || true  # If Jenkins isn't created yet

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
unzip -q /tmp/awscliv2.zip -d /tmp
sudo /tmp/aws/install --update
sudo ln -sf /usr/local/bin/aws /usr/bin/aws
rm -rf /tmp/aws /tmp/awscliv2.zip

# Install Jenkins
sudo wget -O /etc/yum.repos.d/jenkins.repo \
  https://pkg.jenkins.io/redhat-stable/jenkins.repo
sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
sudo yum upgrade -y
sudo yum install -y jenkins
sudo systemctl enable jenkins
sudo systemctl start jenkins

# Print versions for verification
java -version
docker --version
kubectl version --client
aws --version
