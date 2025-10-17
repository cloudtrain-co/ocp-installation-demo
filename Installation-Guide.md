

````markdown
# OCP (Self-managed) Installation on AWS

## Overview
This guide explains how to install an **OpenShift Container Platform (OCP)** self-managed cluster on **AWS** using installation scripts.

> ⚠️ **Important:**  
> Perform the following steps from your **Linux** or **Windows (WSL)** laptop.  
> Do **not** perform cluster installation from an EC2 instance.

---

## Prerequisites
1. You must have a **domain name** for creating the cluster.  
2. An **AWS user** with CLI access and permission to create resources (preferably admin rights).  
3. Once the Route53 hosted zone is created, copy the list of nameservers and add an **NS record** to your domain provider’s DNS configuration.  
4. Verify DNS resolution using [whatsmydns.net](https://whatsmydns.net).  
5. Download your **Pull Secret** from the [Red Hat portal](https://console.redhat.com/openshift/downloads) and save it in a file named as pull-secret.json.

---

## Download Installation Scripts

You can view or download each script directly from this repository:

| Script                                     Description                           |
| -------------------------------------------------------------------------------- |
| install-tools.sh — Installs oc, kubectl, and aws cli                             |
| install-cluster.sh — Creates Route53 hosted zone and starts cluster installation |
| cleanup.sh — Deletes the OCP cluster and Route53 hosted zone                     |
| uninstall-tools.sh — Uninstalls oc, kubectl, aws, and openshift-install binaries |


Download all scripts at once using the commands below:
````
```bash
wget https://raw.githubusercontent.com/cloudtrain-co/ocp-installation-demo/main/install-tools.sh
wget https://raw.githubusercontent.com/cloudtrain-co/ocp-installation-demo/main/install-cluster.sh
wget https://raw.githubusercontent.com/cloudtrain-co/ocp-installation-demo/main/cleanup.sh
wget https://raw.githubusercontent.com/cloudtrain-co/ocp-installation-demo/main/uninstall-tools.sh
```
---
## Preparing Your Environment
### Install Required Tools
---
## Installation Steps
### Step 1: Copy Scripts
Copy the scripts to your OS under the user's home directory:

```bash
cp install-tools.sh install-cluster.sh cleanup.sh uninstall-tools.sh ~
```

### Step 2: Install Required Tools
Run the tool installation script:
```bash
cd ~
./install-tools.sh
```

### Step 3: Save Pull Secret
Login to the Red Hat portal and copy your pull secret.
Save it to `~/pull-secret.json`:

```bash
vi ~/pull-secret.json
```

Then run:

```bash
./install-cluster.sh
```

Follow the on-screen instructions and provide the required inputs.
Cluster installation may take **45–90 minutes**.
Once complete, credentials for the `kubeadmin` user will be displayed.

Login to the cluster:

```bash
oc login -u kubeadmin -p <password> https://api.<cluster-name>.<base-domain>:6443 --insecure-skip-tls-verify=true
```

Verify cluster health once logged in.

---

## Step 4: Cluster Deletion

To delete the cluster, run the cleanup scripts from the same bastion where it was created:

```bash
./cleanup.sh
./uninstall-tools.sh
```

After deletion, remove the NS records added to your domain provider before cluster creation.

---

## Notes

* Always perform installation and deletion from the same **bastion host**.
* Do not run cluster installation from an **EC2 instance**.
* Keep a copy of your **pull-secret.json** and **kubeadmin credentials** secure.
