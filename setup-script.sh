#!/bin/bash

# Cloud IDS Lab Setup Script
# This script automates the setup process for the Cloud IDS lab

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Verify prerequisites
print_status "Checking prerequisites..."

if ! command_exists gcloud; then
    print_error "gcloud CLI is not installed. Please install Google Cloud SDK first."
    exit 1
fi

# Set project ID
print_status "Setting up project environment..."
export PROJECT_ID=$(gcloud config get-value project 2>/dev/null | sed '2d')

if [ -z "$PROJECT_ID" ]; then
    print_error "No project ID found. Please set your project with: gcloud config set project YOUR_PROJECT_ID"
    exit 1
fi

print_success "Using project: $PROJECT_ID"

# Enable APIs
print_status "Enabling required APIs..."
print_status "This may take a few minutes..."

gcloud services enable servicenetworking.googleapis.com --project=$PROJECT_ID
print_success "Service Networking API enabled"

gcloud services enable ids.googleapis.com --project=$PROJECT_ID
print_success "Cloud IDS API enabled"

gcloud services enable logging.googleapis.com --project=$PROJECT_ID
print_success "Cloud Logging API enabled"

# Create VPC network
print_status "Creating VPC network..."
gcloud compute networks create cloud-ids --subnet-mode=custom
print_success "VPC network 'cloud-ids' created"

# Add subnet
print_status "Adding subnet..."
gcloud compute networks subnets create cloud-ids-useast1 \
    --range=192.168.10.0/24 \
    --network=cloud-ids \
    --region=us-east1
print_success "Subnet 'cloud-ids-useast1' created"

# Configure private services access
print_status "Configuring private services access..."
gcloud compute addresses create cloud-ids-ips \
    --global \
    --purpose=VPC_PEERING \
    --addresses=10.10.10.0 \
    --prefix-length=24 \
    --description="Cloud IDS Range" \
    --network=cloud-ids
print_success "Private IP range allocated"

# Create private connection
print_status "Creating private connection..."
gcloud services vpc-peerings connect \
    --service=servicenetworking.googleapis.com \
    --ranges=cloud-ids-ips \
    --network=cloud-ids \
    --project=$PROJECT_ID
print_success "Private connection established"

# Create Cloud IDS endpoint
print_status "Creating Cloud IDS endpoint..."
print_warning "This will take approximately 20 minutes to complete"
gcloud ids endpoints create cloud-ids-east1 \
    --network=cloud-ids \
    --zone=us-east1-b \
    --severity=INFORMATIONAL \
    --async
print_success "Cloud IDS endpoint creation initiated"

# Create firewall rules
print_status "Creating firewall rules..."
gcloud compute firewall-rules create allow-http-icmp \
    --direction=INGRESS \
    --priority=1000 \
    --network=cloud-ids \
    --action=ALLOW \
    --rules=tcp:80,icmp \
    --source-ranges=0.0.0.0/0 \
    --target-tags=server
print_success "HTTP/ICMP firewall rule created"

gcloud compute firewall-rules create allow-iap-proxy \
    --direction=INGRESS \
    --priority=1000 \
    --network=cloud-ids \
    --action=ALLOW \
    --rules=tcp:22 \
    --source-ranges=35.235.240.0/20
print_success "IAP proxy firewall rule created"

# Create Cloud Router
print_status "Creating Cloud Router..."
gcloud compute routers create cr-cloud-ids-useast1 \
    --region=us-east1 \
    --network=cloud-ids
print_success "Cloud Router created"

# Configure Cloud NAT
print_status "Configuring Cloud NAT..."
gcloud compute routers nats create nat-cloud-ids-useast1 \
    --router=cr-cloud-ids-useast1 \
    --router-region=us-east1 \
    --auto-allocate-nat-external-ips \
    --nat-all-subnet-ip-ranges
print_success "Cloud NAT configured"

# Create server VM
print_status "Creating server VM..."
gcloud compute instances create server \
    --zone=us-east1-b \
    --machine-type=e2-medium \
    --subnet=cloud-ids-useast1 \
    --no-address \
    --private-network-ip=192.168.10.20 \
    --metadata=startup-script='#!/bin/bash
sudo apt-get update
sudo apt-get -qq -y install nginx' \
    --tags=server \
    --image=debian-11-bullseye-v20240709 \
    --image-project=debian-cloud \
    --boot-disk-size=10GB
print_success "Server VM created"

# Create attacker VM
print_status "Creating attacker VM..."
gcloud compute instances create attacker \
    --zone=us-east1-b \
    --machine-type=e2-medium \
    --subnet=cloud-ids-useast1 \
    --no-address \
    --private-network-ip=192.168.10.10 \
    --image=debian-11-bullseye-v20240709 \
    --image-project=debian-cloud \
    --boot-disk-size=10GB
print_success "Attacker VM created"

print_success "Infrastructure setup completed!"
print_status "Next steps:"
echo "1. Wait for the Cloud IDS endpoint to be ready (~20 minutes)"
echo "2. Run './setup-packet-mirroring.sh' to configure packet mirroring"
echo "3. Run './prepare-server.sh' to prepare the server for testing"
echo "4. Run './simulate-attacks.sh' to simulate attack traffic"
echo ""
print_status "Check IDS endpoint status with:"
echo "gcloud ids endpoints list --project=$PROJECT_ID"
