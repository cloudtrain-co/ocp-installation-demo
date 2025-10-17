# cat install-cluster.sh
#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# Configuration
# ==================================================
OCP_DIR="${HOME}/ocp-installation"
AWS_DIR="${OCP_DIR}/.aws"
AWS_CREDENTIALS_FILE="${AWS_DIR}/credentials"
AWS_CONFIG_FILE="${AWS_DIR}/config"
HOSTED_ZONE_NAME="ocp.cloudtrain.co"
CALLER_REFERENCE="ocp-$(date +%s)"
OPENSHIFT_INSTALL_BIN="/usr/local/bin/openshift-install"
CUSTOM_CONFIG_FILE="${HOME}/custom-install-config.yaml"
REQUIRED_CMDS=(aws "${OPENSHIFT_INSTALL_BIN}" oc kubectl yq)

# ==================================================
# Helper functions
# ==================================================
info() { printf '\n[INFO] %s\n' "$*"; }
error() { printf '\n[ERROR] %s\n' "$*" >&2; }
confirm_yes_no() {
  local prompt="$1" ans
  while true; do
    read -rp "${prompt} (yes/no): " ans
    case "${ans}" in
      yes|YES|y|Y) return 0 ;;
      no|NO|n|N) return 1 ;;
      *) printf 'Please answer "yes" or "no".\n' ;;
    esac
  done
}
mask_value() {
  local value="$1"
  local length=${#value}
  if (( length > 12 )); then
    local prefix=${value:0:6}
    local suffix=${value: -6}
    echo "${prefix}***${suffix}"
  else
    echo "***masked***"
  fi
}

# ==================================================
# Verify AWS credentials/config
# ==================================================
info "Checking AWS credentials/config"
if [ ! -f "${AWS_CREDENTIALS_FILE}" ] || [ ! -f "${AWS_CONFIG_FILE}" ]; then
  error "AWS credentials/config not found in ${AWS_DIR}."
  exit 1
fi

export AWS_SHARED_CREDENTIALS_FILE="${AWS_CREDENTIALS_FILE}"
export AWS_CONFIG_FILE="${AWS_CONFIG_FILE}"
export AWS_PROFILE="ocp"

# ==================================================
# Verify required tools
# ==================================================
info "Verifying required commands"
for cmd in "${REQUIRED_CMDS[@]}"; do
  binary="${cmd%% *}"
  if ! command -v "${binary}" >/dev/null 2>&1; then
    error "Required command not found in PATH: ${binary}"
    if [ "${binary}" = "yq" ]; then
      info "Attempting to install yq..."
      curl -L "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64" -o /usr/local/bin/yq
      chmod +x /usr/local/bin/yq
      info "yq installed successfully."
    else
      exit 1
    fi
  else
    printf '**%s**: found\n' "${binary}"
  fi
done

# ==================================================
# Ask user for cluster values
# ==================================================
read -rp "Region (e.g., ap-south-1): " region
read -rp "Base Domain (e.g., ocp.cloudtrain.co): " base_domain
read -rp "Cluster Name (e.g., prod): " cluster_name

# Pull Secret from file
read -rp "Enter path to Pull Secret JSON file (e.g., ${HOME}/pull-secret.json): " pull_secret_file
if [ ! -f "$pull_secret_file" ]; then
    error "Pull Secret file not found: $pull_secret_file"
    exit 1
fi
pull_secret=$(<"$pull_secret_file")

# SSH Key from default location
SSH_KEY_FILE="${HOME}/.ssh/id_rsa.pub"
if [ ! -f "$SSH_KEY_FILE" ]; then
    error "SSH Public Key file not found at ${SSH_KEY_FILE}"
    exit 1
fi
ssh_key=$(<"$SSH_KEY_FILE")

# ==================================================
# Generate custom-install-config.yaml
# ==================================================
cat > "${CUSTOM_CONFIG_FILE}" <<EOF
additionalTrustBundlePolicy: Proxyonly
apiVersion: v1
baseDomain: ${base_domain}
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: worker
  platform:
    aws:
      metadataService: {}
      rootVolume:
        iops: 3000
        size: 60
        type: "gp3"
      type: t3.large
      zones:
      - ${region}a
  replicas: 1
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  platform:
    aws:
      metadataService: {}
      rootVolume:
        iops: 3000
        size: 60
        type: "gp3"
      type: t3.xlarge
      zones:
      - ${region}a
  replicas: 3
metadata:
  creationTimestamp: null
  name: ${cluster_name}
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 10.0.0.0/16
  networkType: OVNKubernetes
  serviceNetwork:
  - 172.30.0.0/16
platform:
  aws:
    region: ${region}
    vpc: {}
publish: External
pullSecret: |
  ${pull_secret}
sshKey: |
  ${ssh_key}
EOF
info "custom-install-config.yaml created at ${CUSTOM_CONFIG_FILE}"

# Unset sensitive variables
unset pull_secret
unset ssh_key

# ==================================================
# Copy to install-config.yaml
# ==================================================
mkdir -p "${OCP_DIR}"
INSTALL_CONFIG_FILE="${OCP_DIR}/install-config.yaml"

if [ -f "${INSTALL_CONFIG_FILE}" ]; then
  BACKUP_FILE="${INSTALL_CONFIG_FILE}.bak.$(date +%s)"
  cp "${INSTALL_CONFIG_FILE}" "${BACKUP_FILE}"
  info "Existing install-config.yaml backed up as ${BACKUP_FILE}"
fi

cp "${CUSTOM_CONFIG_FILE}" "${INSTALL_CONFIG_FILE}"
info "custom-install-config.yaml copied to ${INSTALL_CONFIG_FILE}"

# ==================================================
# Create or verify Route53 hosted zone
# ==================================================
info "Checking for existing Route53 hosted zone ${HOSTED_ZONE_NAME}"

EXISTING_ZONE_ID=$(aws route53 list-hosted-zones-by-name \
  --dns-name "${HOSTED_ZONE_NAME}" \
  --query "HostedZones[?Name=='${HOSTED_ZONE_NAME}.'].Id" \
  --output text)

if [ -z "${EXISTING_ZONE_ID}" ] || [ "${EXISTING_ZONE_ID}" = "None" ]; then
  info "Hosted zone ${HOSTED_ZONE_NAME} not found."

  if confirm_yes_no "Do you want to create a new hosted zone for ${HOSTED_ZONE_NAME}?"; then
    info "Creating hosted zone..."
    CREATE_OUTPUT=$(aws route53 create-hosted-zone \
      --name "${HOSTED_ZONE_NAME}" \
      --caller-reference "${CALLER_REFERENCE}" \
      --hosted-zone-config Comment="created by script",PrivateZone=false)

    NEW_ZONE_ID=$(echo "${CREATE_OUTPUT}" | yq '.HostedZone.Id' | sed 's/\/hostedzone\///')
    info "Hosted zone created successfully with ID: ${NEW_ZONE_ID}"
    ZONE_ID="${NEW_ZONE_ID}"
  else
    error "Hosted zone is required for OpenShift installation. Exiting."
    exit 1
  fi
else
  info "Hosted zone ${HOSTED_ZONE_NAME} already exists with ID: ${EXISTING_ZONE_ID}"
  ZONE_ID="${EXISTING_ZONE_ID}"
fi

# ==================================================
# Display hosted zones for user reference
# ==================================================
info "Current hosted zones:"
aws route53 list-hosted-zones --query "HostedZones[*].{Name:Name,Id:Id}" --output table

# ==================================================
# Ask user to update NS records at domain provider
# ==================================================
info "Please add the following Name Servers (NS records) to your domain provider for ${HOSTED_ZONE_NAME}:"
NS_SERVERS=$(aws route53 get-hosted-zone --id "${ZONE_ID}" \
  --query "DelegationSet.NameServers" --output text)
echo "${NS_SERVERS}"

echo
confirm_yes_no "Have you added these NS records at your domain provider?"

# ==================================================
# DNS lookup loop (2 minutes max)
# ==================================================
info "Performing DNS lookup for ${HOSTED_ZONE_NAME} (up to 2 minutes)..."
SUCCESS=0
for i in {1..8}; do
  if nslookup -type=NS "${HOSTED_ZONE_NAME}" >/dev/null 2>&1; then
    info "DNS lookup successful for ${HOSTED_ZONE_NAME}."
    SUCCESS=1
    break
  else
    info "Attempt ${i}/8 failed. Retrying in 15 seconds..."
    sleep 15
  fi
done

if [ "${SUCCESS}" -eq 0 ]; then
  error "DNS lookup failed after 2 minutes. Continuing anyway..."
else
  info "DNS lookup check passed."
fi

# ==================================================
# Post-validation for secret preview
# ==================================================
FINAL_PULL_SECRET=$(yq e '.pullSecret' "${INSTALL_CONFIG_FILE}")
FINAL_SSH_KEY=$(yq e '.sshKey' "${INSTALL_CONFIG_FILE}")

info "Preview of install-config.yaml (last 5 lines hidden for security):"
total_lines=$(wc -l < "${INSTALL_CONFIG_FILE}")
lines_to_show=$((total_lines - 5))
if (( lines_to_show > 0 )); then
    head -n "${lines_to_show}" "${INSTALL_CONFIG_FILE}"
fi
echo "  ... (last 5 lines hidden) ..."

preview_pull_secret=$(tail -c 6 <<< "$FINAL_PULL_SECRET" 2>/dev/null || echo "N/A")
preview_ssh_key=$(tail -c 6 <<< "$FINAL_SSH_KEY" 2>/dev/null || echo "N/A")
info "Cluster creation confirmation:"
echo "  Pull Secret last 6 chars: ${preview_pull_secret}"
echo "  SSH Key last 6 chars     : ${preview_ssh_key}"

# ==================================================
# Confirm and run OpenShift installer
# ==================================================
if confirm_yes_no "Start cluster creation now?"; then
    info "Starting OpenShift cluster installation..."
    "${OPENSHIFT_INSTALL_BIN}" create cluster --dir="${OCP_DIR}" --log-level=info
    info "OpenShift cluster installation finished."
else
    info "Cluster creation aborted by user. Exiting."
    exit 0
fi

# ==================================================
# Final post-validation
# ==================================================
info "Post-validation masked results:"
echo "  pullSecret: $(mask_value "${FINAL_PULL_SECRET}")"
echo "  sshKey    : $(mask_value "${FINAL_SSH_KEY}")"

echo
echo "source ~/.bashrc"
info "Script finished."
