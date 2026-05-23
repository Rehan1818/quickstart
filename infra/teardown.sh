#!/usr/bin/env bash
# =============================================================================
# Alchemyst AI DevOps Assignment — Teardown
# Author: Rehan
# Removes all GCP resources created by setup.sh
# Usage: bash infra/teardown.sh
# =============================================================================

set -euo pipefail

PROJECT_ID="${GCP_PROJECT_ID:-your-gcp-project-id}"
ZONE="us-east1-b"
REGION="us-east1"
NETWORK="alchemyst-net"
SUBNET="alchemyst-private-subnet"

gcloud config set project "$PROJECT_ID"

echo "==> Deleting VMs..."
gcloud compute instances delete \
  rehan-gateway rehan-engine rehan-inference rehan-caller \
  --zone="$ZONE" --quiet

echo "==> Removing firewall rules..."
gcloud compute firewall-rules delete \
  alchemyst-allow-internal \
  alchemyst-allow-ssh \
  alchemyst-allow-http \
  --quiet

echo "==> Removing subnet..."
gcloud compute networks subnets delete "$SUBNET" \
  --region="$REGION" --quiet

echo "==> Removing VPC..."
gcloud compute networks delete "$NETWORK" --quiet

echo "==> Done. All resources deleted."
