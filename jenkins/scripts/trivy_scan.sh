# jenkins/scripts/trivy_scan.sh
#!/bin/bash
set -eo pipefail # Exit on error, exit on pipe failure

IMAGE_NAME=$1

if [ -z "$IMAGE_NAME" ]; then
  echo "Usage: $0 <image-name>"
  exit 1
fi

echo "Installing Trivy..."
# For Amazon Linux 2 (based on RHEL/CentOS)
# Use full path for yum/rpm
sudo /usr/bin/rpm -ivh https://github.com/aquasecurity/trivy/releases/download/v0.51.0/trivy_0.51.0_Linux-64bit.rpm || { echo "Trivy RPM install failed (might be already installed)."; }

echo "Installing jq (for JSON parsing)..."
sudo /usr/bin/yum install -y jq || { echo "jq installation failed."; exit 1; }

# Ensure Trivy is in PATH, or run it with full path
# Since /usr/local/bin is in PATH, 'trivy' command should work.
echo "Running Trivy scan on $IMAGE_NAME..."
# --exit-code 1 ensures a non-zero exit if any HIGH/CRITICAL vulns are found
# --ignore-unfixed to only report fixable vulnerabilities
trivy image --severity HIGH,CRITICAL --format json --exit-code 1 --output trivy-results.json --ignore-unfixed "$IMAGE_NAME"

# Check scan results based on exit code from Trivy.
# Trivy automatically exits with 1 if --exit-code 1 is used and vulnerabilities are found.
if [ $? -eq 0 ]; then
  echo "Trivy scan passed: No HIGH/CRITICAL vulnerabilities found (or all are unfixed)."
else
  echo "!!! TRIVY SCAN FAILED: Found HIGH/CRITICAL vulnerabilities. See trivy-results.json below. !!!"
  cat trivy-results.json
  exit 1 # Explicitly exit with 1 to fail the Jenkins stage
fi

# You can add a step to publish trivy-results.json as a build artifact in Jenkins.
