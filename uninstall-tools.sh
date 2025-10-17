#cat uninstall-tools.sh

#!/bin/bash

# Function to remove a file if it exists
remove_if_exists() {
  if [ -f "$1" ]; then
    echo "Removing $1"
    sudo rm -f "$1"
  fi
}

echo "🔧 Starting uninstallation..."

# --- AWS CLI ---
echo "➡ Uninstalling AWS CLI..."
if command -v aws >/dev/null 2>&1; then
  AWS_PATH=$(command -v aws)
  echo "Found aws at $AWS_PATH"
  sudo rm -rf /usr/local/aws-cli
  remove_if_exists "$AWS_PATH"
else
  echo "AWS CLI not found in PATH."
fi

# Also try apt-based uninstall
sudo apt -y remove awscli >/dev/null 2>&1 && echo "Removed awscli via apt."

# --- kubectl ---
echo "➡ Uninstalling kubectl..."
if command -v kubectl >/dev/null 2>&1; then
  KUBECTL_PATH=$(command -v kubectl)
  echo "Found kubectl at $KUBECTL_PATH"
  remove_if_exists "$KUBECTL_PATH"
else
  echo "kubectl not found in PATH."
fi

# Also try apt/snap uninstall
sudo apt -y remove kubectl >/dev/null 2>&1 && echo "Removed kubectl via apt."
sudo snap remove kubectl >/dev/null 2>&1 && echo "Removed kubectl via snap."

# --- OpenShift CLI (oc) ---
echo "➡ Uninstalling OpenShift CLI (oc)..."
if command -v oc >/dev/null 2>&1; then
  OC_PATH=$(command -v oc)
  echo "Found oc at $OC_PATH"
  remove_if_exists "$OC_PATH"
else
  echo "oc not found in PATH."
fi

# --- OpenShift Installer (openshift-install) ---
echo "➡ Uninstalling OpenShift Installer (openshift-install)..."
if command -v openshift-install >/dev/null 2>&1; then
  INSTALLER_PATH=$(command -v openshift-install)
  echo "Found openshift-install at $INSTALLER_PATH"
  remove_if_exists "$INSTALLER_PATH"
else
  echo "openshift-install not found in PATH."
fi

echo "✅ Uninstallation complete."
