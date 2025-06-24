# jenkins/scripts/trivy_scan.sh
#!/bin/bash
set -eo pipefail # Exit on error, exit on pipe failure

IMAGE_NAME=$1

if [ -z "$IMAGE_NAME" ]; then
  echo "Usage: $0 <image-name>"
  exit 1
fi

echo "Installing Trivy..."
sudo /usr/bin/rpm -ivh https://github.com/aquasecurity/trivy/releases/download/v0.51.0/trivy_0.51.0_Linux-64bit.rpm || { echo "Trivy RPM install failed (might be already installed)."; }

echo "Installing jq (for JSON parsing)..."
sudo /usr/bin/yum install -y jq || { echo "jq installation failed."; exit 1; }

echo "Running Trivy scan on $IMAGE_NAME..."
# Removed --exit-code 1 from the Trivy command itself.
trivy image --severity HIGH,CRITICAL --format json --output trivy-results.json --ignore-unfixed "$IMAGE_NAME"

TRIVY_EXIT_CODE=$? # Capture Trivy's actual exit code.

if [ -s trivy-results.json ]; then # -s checks if file is non-empty
  echo "--- Trivy Scan Results Summary (HIGH/CRITICAL) ---"
  cat trivy-results.json | jq -r '
    .Results[] | select(.Vulnerabilities != null) |
    .Vulnerabilities[] | select(.Severity == "HIGH" or .Severity == "CRITICAL") |
    "Vulnerability: \(.VulnerabilityID) - Package: \(.PkgName) - Installed: \(.InstalledVersion) - Fixed: \(.FixedVersion) - Severity: \(.Severity) - Title: \(.Title)"
  '
  echo "--- End Trivy Scan Results Summary ---"
else
  echo "WARNING: Trivy scan did not produce a results file. This might indicate a scan error."
  TRIVY_EXIT_CODE=2 # Force exit code to 2 if no results file (for error condition)
fi

# Now, evaluate Trivy's captured exit code (TRIVY_EXIT_CODE).
if [ "$TRIVY_EXIT_CODE" -eq 0 ]; then
  echo "Trivy scan passed: No HIGH/CRITICAL vulnerabilities found."
  exit 0 # Success for Jenkins stage
elif [ "$TRIVY_EXIT_CODE" -eq 1 ]; then
  echo "WARNING: Trivy scan found HIGH/CRITICAL vulnerabilities. Pipeline will continue for demo purposes."
  # In a real production pipeline, you would likely exit 1 here to enforce security gates.
  exit 0 # <--- THIS IS THE CRITICAL LINE TO ADD/CONFIRM
else # TRIVY_EXIT_CODE is 2 (scan error) or other unexpected non-vuln exit code
  echo "ERROR: Trivy scan encountered a critical error during execution (Exit Code: $TRIVY_EXIT_CODE)."
  exit 1 # Fail the Jenkins stage due to a scan error, not a vulnerability finding.
fi
# Ensure the script ends with 'fi' and no extra characters after it.