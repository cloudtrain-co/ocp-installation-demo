#cat install-tools.sh

#!/usr/bin/env bash
set -euo pipefail

# Configuration
OPENSHIFT_VERSION="4.17.40"
OC_CLIENT_TAR="openshift-client-linux-${OPENSHIFT_VERSION}.tar.gz"
OC_INSTALLER_TAR="openshift-install-linux-${OPENSHIFT_VERSION}.tar.gz"
OC_CLIENT_URL="https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/${OPENSHIFT_VERSION}/${OC_CLIENT_TAR}"
OC_INSTALLER_URL="https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/${OPENSHIFT_VERSION}/${OC_INSTALLER_TAR}"
AWS_ZIP="awscliv2.zip"
AWS_URL="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
INSTALL_DIR="/usr/local/bin"
WORKDIR="$(mktemp -d /tmp/ocp-install.XXXX)"
AWS_PROFILE_NAME="ocp"
AWS_REGION="ap-south-1"
OCP_DIR="${HOME}/ocp-installation"
AWS_DIR="${OCP_DIR}/.aws"
AWS_CREDENTIALS_FILE="${AWS_DIR}/credentials"
AWS_CONFIG_FILE="${AWS_DIR}/config"

cleanup() { rm -rf "${WORKDIR}"; }
trap cleanup EXIT

confirm() {
  local prompt="$1" default="$2" reply
  if [ "${default}" = "Y" ]; then
    read -rp "${prompt} [Y/n]: " reply; reply=${reply:-Y}
  else
    read -rp "${prompt} [y/N]: " reply; reply=${reply:-N}
  fi
  case "${reply}" in [Yy]* ) return 0 ;; * ) return 1 ;; esac
}

info() { echo -e "\n[INFO] $*"; }
error() { echo -e "\n[ERROR] $*" >&2; }

ensure_package() {
  local pkg="$1"
  if ! dpkg -s "${pkg}" >/dev/null 2>&1; then
    info "Installing package ${pkg}"
    sudo apt-get update -qq
    sudo apt-get install -y --no-install-recommends "${pkg}"
  else
    info "Package ${pkg} already present"
  fi
}

info "Preparing environment and installing prerequisites"
ensure_package "curl"
ensure_package "unzip"
ensure_package "wget"
ensure_package "ca-certificates"
ensure_package "lsb-release"
ensure_package "bash-completion"
ensure_package "openssh-client"

mkdir -p "${WORKDIR}"
cd "${WORKDIR}"

install_aws_cli() {
  info "Installing AWS CLI v2"
  if command -v aws >/dev/null 2>&1; then
    current="$(aws --version 2>&1 || true)"
    info "Existing aws detected: ${current}"
    if ! confirm "Overwrite existing aws CLI installation?" "Y"; then
      info "Skipping AWS CLI installation"
      return
    fi
  fi
  info "Downloading AWS CLI"
  curl -sSL "${AWS_URL}" -o "${AWS_ZIP}"
  unzip -oq "${AWS_ZIP}"
  sudo ./aws/install --update || sudo ./aws/install || true
  export PATH="${PATH}:${INSTALL_DIR}"
  info "AWS CLI install attempted"
}

install_openshift_tools() {
  info "Installing OpenShift installer and client (oc, kubectl)"
  wget  "${OC_CLIENT_URL}" -O "${OC_CLIENT_TAR}"
  wget  "${OC_INSTALLER_URL}" -O "${OC_INSTALLER_TAR}"
  tar -xzf "${OC_CLIENT_TAR}"
  tar -xzf "${OC_INSTALLER_TAR}"
  for bin in oc kubectl openshift-install; do
    if [ -f "${bin}" ]; then
      if command -v "${bin}" >/dev/null 2>&1; then
        if confirm "Overwrite existing ${bin} in ${INSTALL_DIR}?" "Y"; then
          sudo mv -f "${bin}" "${INSTALL_DIR}/"; sudo chmod +x "${INSTALL_DIR}/${bin}"
        else
          info "Skipping overwrite of ${bin}"; rm -f "${bin}"
        fi
      else
        sudo mv -f "${bin}" "${INSTALL_DIR}/"; sudo chmod +x "${INSTALL_DIR}/${bin}"
      fi
    else
      error "Expected binary ${bin} not found after extracting tar"
    fi
  done

  info "Configuring oc bash completion"
  if [ -x "${INSTALL_DIR}/oc" ]; then
    oc completion bash > oc_bash_completion || true
    sudo mv -f oc_bash_completion /etc/bash_completion.d/oc
    sudo chmod 644 /etc/bash_completion.d/oc
    if ! grep -qF "/etc/bash_completion.d/oc" "${HOME}/.bashrc" 2>/dev/null; then
      echo "source /etc/bash_completion.d/oc" >> "${HOME}/.bashrc"
    fi
  fi
}

ensure_ssh_key() {
  if [ -f "${HOME}/.ssh/id_rsa" ] || [ -f "${HOME}/.ssh/id_ed25519" ]; then
    info "SSH key already exists, skipping generation"
  else
    info "Generating SSH key (no passphrase)."
    ssh-keygen -t rsa -b 4096 -f "${HOME}/.ssh/id_rsa" -N "" -q
    chmod 600 "${HOME}/.ssh/id_rsa"
    info "SSH key generated at ${HOME}/.ssh/id_rsa"
  fi
}

configure_aws_profile_in_dir() {
  info "Creating directory ${OCP_DIR} (skipping if exists) and writing AWS profile ${AWS_PROFILE_NAME} there"
  mkdir -p "${AWS_DIR}"
  chmod 700 "${AWS_DIR}"

  read -rp "Enter AWS Access Key ID: " AWS_ACCESS_KEY_ID
  read -srp "Enter AWS Secret Access Key: " AWS_SECRET_ACCESS_KEY
  echo
  if [ -z "${AWS_ACCESS_KEY_ID}" ] || [ -z "${AWS_SECRET_ACCESS_KEY}" ]; then
    error "AWS credentials cannot be empty; aborting profile configuration"
    return 1
  fi

  {
    echo "[${AWS_PROFILE_NAME}]"
    echo "aws_access_key_id = ${AWS_ACCESS_KEY_ID}"
    echo "aws_secret_access_key = ${AWS_SECRET_ACCESS_KEY}"
  } > "${AWS_CREDENTIALS_FILE}"
  chmod 600 "${AWS_CREDENTIALS_FILE}"

  {
    echo "[profile ${AWS_PROFILE_NAME}]"
    echo "region = ${AWS_REGION}"
    echo "output = json"
  } > "${AWS_CONFIG_FILE}"
  chmod 600 "${AWS_CONFIG_FILE}"

  info "Wrote credentials to ${AWS_CREDENTIALS_FILE} and config to ${AWS_CONFIG_FILE}"
  info "To use this profile in commands, set AWS_SHARED_CREDENTIALS_FILE and AWS_CONFIG_FILE or export AWS_PROFILE=${AWS_PROFILE_NAME} and point AWS config/env to this directory"
}

verify_tool() {
  local name="$1" check_cmd="$2"
  if eval "${check_cmd}" >/dev/null 2>&1; then
    echo "**${name}**: installed"
  else
    echo "**${name}**: NOT installed or not found in PATH"
  fi
}

main() {
  info "Starting installation in ${WORKDIR}"
  install_aws_cli
  install_openshift_tools
  ensure_ssh_key
  if ! configure_aws_profile_in_dir; then
    error "AWS configure failed or skipped"
  fi

  info "Final verification of installed tools"
  echo
  verify_tool "aws" "command -v aws"
  verify_tool "openshift-install" "command -v openshift-install"
  verify_tool "oc" "command -v oc"
  verify_tool "kubectl" "command -v kubectl"
  echo

  if command -v aws >/dev/null 2>&1; then echo "aws version: $(aws --version 2>&1)"; fi
  if command -v openshift-install >/dev/null 2>&1; then echo "openshift-install version: $(openshift-install version 2>&1 || true)"; fi
  if command -v oc >/dev/null 2>&1; then echo "oc version: $(oc version --client --output=yaml 2>/dev/null || oc version)"; fi
  if command -v kubectl >/dev/null 2>&1; then echo "kubectl version: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"; fi

  echo
  echo "source ~/.bashrc"
  info "Installation script completed"
}

main "$@"
