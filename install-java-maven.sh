#!/bin/bash

# Install default Java and Maven
sudo apt update
sudo apt install -y default-jdk maven

# Set JAVA_HOME and MAVEN_HOME, and update PATH in ~/.bashrc
JAVA_HOME_PATH=$(readlink -f /usr/bin/java | sed "s:bin/java::")
MAVEN_HOME_PATH="/usr/share/maven"

echo "export JAVA_HOME=${JAVA_HOME_PATH}" >> ~/.bashrc
echo "export MAVEN_HOME=${MAVEN_HOME_PATH}" >> ~/.bashrc
echo 'export PATH=$JAVA_HOME/bin:$MAVEN_HOME/bin:$PATH' >> ~/.bashrc

# Apply the environment variable changes
source ~/.bashrc

# Enable password authentication for SSH
SSH_CONFIG="/etc/ssh/ssh_config"
sudo sed -i 's/^#PasswordAuthentication no/PasswordAuthentication yes/' "$SSH_CONFIG"
sudo sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' "$SSH_CONFIG"

# Restart SSH service
sudo systemctl restart ssh

echo "Java and Maven installed. Environment variables set. Password authentication enabled."