#!/bin/bash

# Server Preparation Script
# Sets up the test files on the server VM

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

print_status "Preparing server for testing..."

# Check if server VM exists
print_status "Checking if server VM exists..."
if ! gcloud compute instances describe server --zone=us-east1-b --project=$PROJECT_ID >/dev/null 2>&1; then
    print_error "Server VM not found. Please run the main setup script first."
    exit 1
fi

print_success "Server VM found"

# Create a temporary script to run on the server
cat > /tmp/server-setup.sh << 'EOF'
#!/bin/bash

echo "Checking nginx status..."
sudo systemctl status nginx --no-pager

echo "Creating test directory and files..."
cd /var/www/html/

# Create EICAR test file
echo "Creating EICAR test file..."
sudo touch eicar.file
echo 'X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*' | sudo tee eicar.file

# Create additional test files
echo "Creating additional test files..."
sudo mkdir -p cgi-bin
sudo touch cgi-bin/test-critical

# Create a simple test page
echo "Creating test HTML page..."
cat << 'HTML' | sudo tee index.html
<!DOCTYPE html>
<html>
<head>
    <title>Cloud IDS Test Server</title>
</head>
<body>
    <h1>Cloud IDS Test Server</h1>
    <p>This server is configured for Cloud IDS testing.</p>
    <p>Server IP: 192.168.10.20</p>
</body>
</html>
HTML

# Set proper permissions
sudo chown -R www-data:www-data /var/www/html/
sudo chmod -R 755 /var/www/html/

echo "Server setup completed successfully!"
echo "Files created:"
ls -la /var/www/html/
EOF

# Copy and execute the setup script on the server
print_status "Connecting to server VM and running setup..."
gcloud compute scp /tmp/server-setup.sh server:/tmp/server-setup.sh --zone=us-east1-b --tunnel-through-iap --project=$PROJECT_ID

print_status "Executing server setup script..."
gcloud compute ssh server --zone=us-east1-b --tunnel-through-iap --project=$PROJECT_ID --command="chmod +x /tmp/server-setup.sh && /tmp/server-setup.sh"

# Clean up
rm -f /tmp/server-setup.sh

print_success "Server preparation completed!"
print_status "The server is now ready for attack simulation."
print_status "Next step: Run './simulate-attacks.sh' to generate test traffic"

# Verify server is responding
print_status "Testing server connectivity..."
gcloud compute ssh attacker --zone=us-east1-b --tunnel-through-iap --project=$PROJECT_ID --command="curl -s -I http://192.168.10.20 | head -1" || print_warning "Could not test server connectivity"

print_success "Server preparation process completed!"
