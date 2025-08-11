#!/bin/bash

# Cloud IDS Packet Mirroring Setup Script
# Run this after the IDS endpoint is in READY state

set -e

# Colors for output 

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Set project ID
export PROJECT_ID=$(gcloud config get-value project 2>/dev/null | sed '2d')

if [ -z "$PROJECT_ID" ]; then
    print_error "No project ID found. Please set your project with: gcloud config set project YOUR_PROJECT_ID"
    exit 1
fi

print_status "Setting up packet mirroring for project: $PROJECT_ID"

# Check if IDS endpoint is ready
print_status "Checking Cloud IDS endpoint status..."
ENDPOINT_STATE=$(gcloud ids endpoints list --project=$PROJECT_ID --format="value(state)" --filter="name:cloud-ids-east1" 2>/dev/null || echo "NOT_FOUND")

if [ "$ENDPOINT_STATE" != "READY" ]; then
    if [ "$ENDPOINT_STATE" == "NOT_FOUND" ]; then
        print_error "Cloud IDS endpoint 'cloud-ids-east1' not found. Please run the main setup script first."
        exit 1
    else
        print_error "Cloud IDS endpoint is in state: $ENDPOINT_STATE"
        print_warning "Please wait for the endpoint to be in READY state before running this script."
        print_status "You can check the status with:"
        echo "gcloud ids endpoints list --project=$PROJECT_ID"
        exit 1
    fi
fi

print_success "Cloud IDS endpoint is ready"

# Get the forwarding rule
print_status "Getting IDS endpoint forwarding rule..."
export FORWARDING_RULE=$(gcloud ids endpoints describe cloud-ids-east1 --zone=us-east1-b --format="value(endpointForwardingRule)")

if [ -z "$FORWARDING_RULE" ]; then
    print_error "Failed to get forwarding rule from IDS endpoint"
    exit 1
fi

print_success "Forwarding rule obtained: $FORWARDING_RULE"

# Create packet mirroring policy
print_status "Creating packet mirroring policy..."
gcloud compute packet-mirrorings create cloud-ids-packet-mirroring \
    --region=us-east1 \
    --collector-ilb=$FORWARDING_RULE \
    --network=cloud-ids \
    --mirrored-subnets=cloud-ids-useast1

print_success "Packet mirroring policy created"

# Verify packet mirroring policy
print_status "Verifying packet mirroring policy..."
gcloud compute packet-mirrorings list --filter="name:cloud-ids-packet-mirroring"

print_success "Packet mirroring setup completed!"
print_status "The Cloud IDS is now ready to monitor traffic on the cloud-ids-useast1 subnet."
print_status "Next steps:"
echo "1. Run './prepare-server.sh' to set up the test environment"
echo "2. Run './simulate-attacks.sh' to generate test traffic"
echo "3. View results in Cloud Console > Network Security > Cloud IDS"
