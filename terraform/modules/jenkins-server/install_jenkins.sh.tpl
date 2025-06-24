#!/bin/bash
set -eux # Exit on error, unset variable error, print commands

# --- System Update & Git ---
echo "Updating system packages..."
sudo yum update -y || { echo "ERROR: System update failed."; exit 1; }

echo "Installing Git..."
sudo yum install -y git || { echo "ERROR: Git installation failed."; exit 1; }
git --version || { echo "ERROR: Git verification failed."; exit 1; }

# --- Install Java (Amazon Corretto 17) ---
echo "Installing Amazon Corretto 17..."
sudo yum install -y java-17-amazon-corretto || { echo "ERROR: Java 17 installation failed."; exit 1; }

# Dynamically detect JAVA_HOME and export it
echo "export JAVA_HOME=\$(dirname \$(dirname \$(readlink -f \$(which java))))" | sudo tee /etc/profile.d/java.sh
echo 'export PATH=$JAVA_HOME/bin:$PATH' | sudo tee -a /etc/profile.d/java.sh
sudo chmod +x /etc/profile.d/java.sh # Ensure profile script is executable
source /etc/profile.d/java.sh # Source for current script execution

# Verify Java installation
java -version || { echo "ERROR: Java verification failed. Exiting."; exit 1; }

# --- Install Maven (Standard Binary Download) ---
echo "Installing Maven (specific version)..."
MAVEN_VERSION="3.9.10" # Current stable Maven 3.x.x
MAVEN_TAR_GZ="apache-maven-$${MAVEN_VERSION}-bin.tar.gz" # $$ passes $ literally to rendered script
MAVEN_DOWNLOAD_URL="https://dlcdn.apache.org/maven/maven-3/$${MAVEN_VERSION}/binaries/$${MAVEN_TAR_GZ}"
MAVEN_INSTALL_DIR="/opt/maven" # Standard location for manually installed software

sudo mkdir -p "$${MAVEN_INSTALL_DIR}" || { echo "ERROR: Maven install dir creation failed. Exiting."; exit 1; }
sudo curl -fSL "$${MAVEN_DOWNLOAD_URL}" -o "/tmp/$${MAVEN_TAR_GZ}" || { echo "ERROR: Maven download failed. Exiting."; exit 1; }
sudo tar -xzf "/tmp/$${MAVEN_TAR_GZ}" -C "$${MAVEN_INSTALL_DIR}" || { echo "ERROR: Maven extraction failed. Exiting."; exit 1; }
sudo rm "/tmp/$${MAVEN_TAR_GZ}" # Clean up downloaded archive

# Create a symlink to the specific Maven version for easier PATH management
sudo ln -s "$${MAVEN_INSTALL_DIR}/apache-maven-$${MAVEN_VERSION}" "$${MAVEN_INSTALL_DIR}/latest" || true # ||true if symlink exists

# Add Maven to PATH (ensure it's sourced for subsequent commands in this script and for jenkins user)
echo "export M2_HOME=$${MAVEN_INSTALL_DIR}/latest" | sudo tee -a /etc/profile.d/maven.sh
echo 'export PATH=$M2_HOME/bin:$PATH' | sudo tee -a /etc/profile.d/maven.sh
sudo chmod +x /etc/profile.d/maven.sh # Ensure profile script is executable
source /etc/profile.d/maven.sh # Source for current script execution

mvn --version || { echo "ERROR: Maven verification failed after installation. Exiting."; exit 1; }
# --- End Maven Installation ---


# --- Install Docker ---
echo "Installing Docker..."
sudo amazon-linux-extras enable docker || { echo "ERROR: amazon-linux-extras enable docker failed. Exiting."; exit 1; }
sudo yum clean metadata || { echo "ERROR: yum clean metadata failed. Exiting."; exit 1; }
sudo yum install -y docker || { echo "ERROR: Docker yum install failed. Exiting."; exit 1; }
sudo systemctl start docker || { echo "ERROR: Docker start failed. Exiting."; exit 1; }
sudo systemctl enable docker || { echo "ERROR: Docker enable failed. Exiting."; exit 1; }
sudo usermod -aG docker ec2-user || { echo "ERROR: Adding ec2-user to docker group failed. Exiting."; exit 1; }
sudo usermod -aG docker jenkins || true # Allow to fail if Jenkins isn't fully created yet

# --- Install kubectl ---
echo "Installing kubectl..."
curl -LO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" || { echo "ERROR: kubectl download failed. Exiting."; exit 1; }
chmod +x kubectl || { echo "ERROR: kubectl chmod failed. Exiting."; exit 1; }
sudo mv kubectl /usr/local/bin/ || { echo "ERROR: kubectl move failed. Exiting."; exit 1; }

# --- Install AWS CLI v2 ---
echo "Installing AWS CLI v2..."
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip" || { echo "ERROR: AWS CLI v2 download failed. Exiting."; exit 1; }
unzip -q /tmp/awscliv2.zip -d /tmp || { echo "ERROR: AWS CLI v2 unzip failed. Exiting."; exit 1; }
sudo /tmp/aws/install --update || { echo "ERROR: AWS CLI v2 install script failed. Exiting."; exit 1; }
sudo ln -sf /usr/local/bin/aws /usr/bin/aws || { echo "ERROR: AWS CLI v2 symlink failed. Exiting."; exit 1; }
rm -rf /tmp/aws /tmp/awscliv2.zip

# Verify kubectl and AWS CLI are in the PATH for the user_data script itself.
kubectl version --client || { echo "ERROR: kubectl verification failed. Exiting."; exit 1; }
aws --version || { echo "ERROR: AWS CLI v2 verification failed. Exiting."; exit 1; }
# --- End Tool Installation ---


# --- Install Jenkins ---
echo "Installing Jenkins..."
sudo wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo || { echo "ERROR: Jenkins repo download failed. Exiting."; exit 1; }
sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key || { echo "ERROR: Jenkins GPG key import failed. Exiting."; exit 1; }
sudo yum upgrade -y || { echo "ERROR: yum upgrade failed during Jenkins install. Exiting."; exit 1; }
sudo yum install -y jenkins || { echo "ERROR: Jenkins yum install failed. Exiting."; exit 1; }

echo "Attempting to start Jenkins service..."
sudo systemctl enable jenkins || { echo "ERROR: Jenkins enable failed. Exiting."; exit 1; }
sudo systemctl start jenkins || true # Allow initial start to fail if dependencies aren't fully resolved yet

# --- Configure Jenkins user's AWS CLI and kubeconfig ---
echo "Configuring Jenkins AWS access for the jenkins user..."
sudo mkdir -p /var/lib/jenkins/.aws || { echo "ERROR: Jenkins .aws dir creation failed. Exiting."; exit 1; }
sudo chown jenkins:jenkins /var/lib/jenkins/.aws || { echo "ERROR: Jenkins .aws dir ownership failed. Exiting."; exit 1; }

# Create kubeconfig updater script with specific EKS cluster name and region
# ${EKS_CLUSTER_NAME} and ${AWS_REGION} are template variables, passed by Terraform.
# $$PATH ensures $PATH is passed literally to the shell script.
cat <<'EOF' | sudo tee /var/lib/jenkins/.kubeconfig_update.sh
#!/bin/bash
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin # Set a robust PATH for this specific script
aws eks update-kubeconfig --name ${EKS_CLUSTER_NAME} --region ${AWS_REGION} || { echo "ERROR: Kubeconfig update command failed within script. Exiting."; exit 1; }
EOF

sudo chmod +x /var/lib/jenkins/.kubeconfig_update.sh || { echo "ERROR: Kubeconfig update script chmod failed. Exiting."; exit 1; }
sudo chown jenkins:jenkins /var/lib/jenkins/.kubeconfig_update.sh || { echo "ERROR: Kubeconfig update script chown failed. Exiting."; exit 1; }

echo "Waiting for EC2 instance profile credentials to propagate (60s)..."
sleep 60
echo "Updating kubeconfig for Jenkins user..."
sudo -u jenkins /var/lib/jenkins/.kubeconfig_update.sh || { echo "ERROR: Kubeconfig update for jenkins user failed. Exiting."; exit 1; }

# --- Final service reloads ---
echo "Reloading and restarting Jenkins..."
sudo systemctl daemon-reload || { echo "ERROR: Systemd daemon reload failed. Exiting."; exit 1; }
sudo systemctl restart jenkins || { echo "ERROR: Jenkins restart failed. Exiting."; exit 1; }

echo "Checking Jenkins final status..."
sudo systemctl status jenkins