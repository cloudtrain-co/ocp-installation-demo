#cat cleanup.sh

#!/usr/bin/env bash
#set -euo pipefail

# ==================================================
# Configuration
# ==================================================
OCP_DIR="${HOME}/ocp-installation"
AWS_DIR="${OCP_DIR}/.aws"
AWS_CREDENTIALS_FILE="${AWS_DIR}/credentials"
AWS_CONFIG_FILE="${AWS_DIR}/config"
OPENSHIFT_INSTALL_BIN="/usr/local/bin/openshift-install"
HOSTED_ZONE_NAME="ocp.cloudtrain.co"

# ==================================================
# Export AWS env so aws CLI uses local files
# ==================================================
export AWS_SHARED_CREDENTIALS_FILE="${AWS_CREDENTIALS_FILE}"
export AWS_CONFIG_FILE="${AWS_CONFIG_FILE}"
export AWS_PROFILE="ocp"

# ==================================================
# Destroy OpenShift cluster
# ==================================================
echo "Destroying OpenShift cluster..."
"${OPENSHIFT_INSTALL_BIN}" destroy cluster --dir="${OCP_DIR}" --log-level=info
echo "OpenShift cluster destroyed."

# ==================================================
# Delete Route 53 hosted zone
# ==================================================
echo "Looking for Route 53 hosted zone: ${HOSTED_ZONE_NAME}"
ZONE_ID=$(aws route53 list-hosted-zones-by-name \
  --dns-name "${HOSTED_ZONE_NAME}" \
  --query "HostedZones[?Name=='${HOSTED_ZONE_NAME}.'].Id" \
  --output text)

if [ -n "${ZONE_ID}" ]; then
  echo "Found hosted zone: ${ZONE_ID}"
  #echo "Deleting hosted zone: ${ZONE_ID}"
  #aws route53 delete-hosted-zone --id "${ZONE_ID}"
  echo "Hosted zone ${HOSTED_ZONE_NAME} deleted."
else
  echo "No hosted zone found for ${HOSTED_ZONE_NAME}. Skipping."
fi
