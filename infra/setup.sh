#!/usr/bin/env bash
# =============================================================================
# Alchemyst AI DevOps Assignment — Infrastructure Setup
# Author: Rehan
# Provisions VPC, subnet, firewall rules, and 4 VMs on GCP (us-east1)
# Usage: bash infra/setup.sh
# =============================================================================

set -euo pipefail

# ---------- Configuration ----------------------------------------------------
PROJECT_ID="${GCP_PROJECT_ID:-your-gcp-project-id}"
REGION="us-east1"
ZONE="us-east1-b"
NETWORK="alchemyst-net"
SUBNET="alchemyst-private-subnet"
SUBNET_RANGE="192.168.1.0/24"

# VM names
GATEWAY_VM="rehan-gateway"
ENGINE_VM="rehan-engine"
INFERENCE_VM="rehan-inference"
CALLER_VM="rehan-caller"

MACHINE_TYPE="e2-medium"
DISK_SIZE="25GB"
IMAGE_FAMILY="ubuntu-2204-lts"
IMAGE_PROJECT="ubuntu-os-cloud"

echo "==> Project: $PROJECT_ID | Region: $REGION"
gcloud config set project "$PROJECT_ID"

# ---------- 1. Enable APIs ---------------------------------------------------
echo "==> Enabling required APIs..."
gcloud services enable compute.googleapis.com

# ---------- 2. VPC Network ---------------------------------------------------
echo "==> Creating custom VPC..."
gcloud compute networks create "$NETWORK" \
  --subnet-mode=custom \
  --bgp-routing-mode=regional \
  --description="Alchemyst distributed inference VPC"

# ---------- 3. Private Subnet ------------------------------------------------
echo "==> Creating private subnet ($SUBNET_RANGE)..."
gcloud compute networks subnets create "$SUBNET" \
  --network="$NETWORK" \
  --region="$REGION" \
  --range="$SUBNET_RANGE" \
  --enable-private-ip-google-access \
  --description="Private subnet — worker VMs live here"

# ---------- 4. Firewall Rules ------------------------------------------------
echo "==> Setting up firewall rules..."

# Internal RPC communication between all VMs
gcloud compute firewall-rules create alchemyst-allow-internal \
  --network="$NETWORK" \
  --direction=INGRESS \
  --priority=1000 \
  --action=ALLOW \
  --rules=tcp,udp,icmp \
  --source-ranges="$SUBNET_RANGE" \
  --description="Allow all internal traffic between VMs"

# SSH access (restrict to your IP in production)
gcloud compute firewall-rules create alchemyst-allow-ssh \
  --network="$NETWORK" \
  --direction=INGRESS \
  --priority=1000 \
  --action=ALLOW \
  --rules=tcp:22 \
  --source-ranges="0.0.0.0/0" \
  --description="SSH access for administration"

# Only the gateway VM accepts public HTTP on port 3111
gcloud compute firewall-rules create alchemyst-allow-http \
  --network="$NETWORK" \
  --direction=INGRESS \
  --priority=1000 \
  --action=ALLOW \
  --rules=tcp:3111 \
  --source-ranges="0.0.0.0/0" \
  --target-tags="api-gateway" \
  --description="Public HTTP API — gateway only"

# ---------- 5. Create VMs ----------------------------------------------------
echo "==> Launching gateway VM (public-facing)..."
gcloud compute instances create "$GATEWAY_VM" \
  --zone="$ZONE" \
  --machine-type="$MACHINE_TYPE" \
  --subnet="$SUBNET" \
  --boot-disk-size="$DISK_SIZE" \
  --image-family="$IMAGE_FAMILY" \
  --image-project="$IMAGE_PROJECT" \
  --tags="api-gateway" \
  --metadata-from-file=startup-script=deploy/gateway-startup.sh \
  --description="Public gateway — nginx reverse proxy"

echo "==> Launching engine VM (private)..."
gcloud compute instances create "$ENGINE_VM" \
  --zone="$ZONE" \
  --machine-type="$MACHINE_TYPE" \
  --subnet="$SUBNET" \
  --no-address \
  --boot-disk-size="$DISK_SIZE" \
  --image-family="$IMAGE_FAMILY" \
  --image-project="$IMAGE_PROJECT" \
  --metadata-from-file=startup-script=deploy/engine-startup.sh \
  --description="iii RPC engine — coordinates all workers"

echo "==> Launching inference VM (private)..."
gcloud compute instances create "$INFERENCE_VM" \
  --zone="$ZONE" \
  --machine-type="$MACHINE_TYPE" \
  --subnet="$SUBNET" \
  --no-address \
  --boot-disk-size="$DISK_SIZE" \
  --image-family="$IMAGE_FAMILY" \
  --image-project="$IMAGE_PROJECT" \
  --metadata-from-file=startup-script=deploy/inference-startup.sh \
  --description="Python worker — Gemma 3 270M inference"

echo "==> Launching caller VM (private)..."
gcloud compute instances create "$CALLER_VM" \
  --zone="$ZONE" \
  --machine-type="$MACHINE_TYPE" \
  --subnet="$SUBNET" \
  --no-address \
  --boot-disk-size="$DISK_SIZE" \
  --image-family="$IMAGE_FAMILY" \
  --image-project="$IMAGE_PROJECT" \
  --metadata-from-file=startup-script=deploy/caller-startup.sh \
  --description="TypeScript worker — HTTP trigger and RPC fan-out"

# ---------- 6. Summary -------------------------------------------------------
echo ""
echo "==> All VMs created. Internal IPs:"
gcloud compute instances list \
  --filter="zone:$ZONE" \
  --format="table(name,networkInterfaces[0].networkIP,networkInterfaces[0].accessConfigs[0].natIP,status)"

GATEWAY_IP=$(gcloud compute instances describe "$GATEWAY_VM" \
  --zone="$ZONE" \
  --format="value(networkInterfaces[0].accessConfigs[0].natIP)")

echo ""
echo "==> Your API is live at:"
echo "    POST http://${GATEWAY_IP}:3111/v1/chat/completions"
echo ""
echo "==> Quick test:"
echo "    curl -X POST http://${GATEWAY_IP}:3111/v1/chat/completions \\"
echo "      -H 'Content-Type: application/json' \\"
echo "      -d '{\"messages\": [{\"role\": \"user\", \"content\": \"Hello!\"}]}'"
