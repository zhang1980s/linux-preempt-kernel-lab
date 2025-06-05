#!/bin/bash
#
# Script to copy build-rt-kernel.sh to remote test server and execute it
# This script uses the SSH command provided by the user

set -e  # Exit on error

# Configuration variables - adjust as needed
REMOTE_HOST="rt-kernel.zzhe.xyz"
SSH_KEY="/home/admin/myspace/keys/keypair-sandbox0-sin-mymac.pem"
REMOTE_USER="ec2-user"

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to display status messages
function echo_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

# Function to display warning messages
function echo_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to display error messages
function echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if SSH key exists
if [ ! -f "$SSH_KEY" ]; then
    echo_error "SSH key not found: $SSH_KEY"
    exit 1
fi

# Check if build-rt-kernel.sh exists
if [ ! -f "build-rt-kernel.sh" ]; then
    echo_error "build-rt-kernel.sh not found in current directory"
    exit 1
fi

echo "============================================="
echo "   Copy and Execute RT Kernel Build Script   "
echo "============================================="
echo

# Step 1: Copy build-rt-kernel.sh to remote server
echo_status "Step 1: Copying build-rt-kernel.sh to remote server..."
scp -i $SSH_KEY build-rt-kernel.sh $REMOTE_USER@$REMOTE_HOST:~/build-rt-kernel.sh

# Step 2: Make the script executable on remote server
echo_status "Step 2: Making the script executable on remote server..."
ssh -i $SSH_KEY $REMOTE_USER@$REMOTE_HOST "chmod +x ~/build-rt-kernel.sh"

# Step 3: Execute the script on remote server
echo_status "Step 3: Executing build-rt-kernel.sh on remote server..."
echo_status "This will start the kernel build process on the remote server."
echo_status "The process may take a long time depending on the server's resources."
echo
echo "Do you want to execute the script on the remote server? (y/n)"
read -p "Enter your choice: " choice

if [ "$choice" == "y" ] || [ "$choice" == "Y" ]; then
    # Get CPU count from remote system
    echo_status "Detecting CPU count on remote system..."
    REMOTE_CORES=$(ssh -i $SSH_KEY $REMOTE_USER@$REMOTE_HOST "nproc")
    echo_status "Remote system has $REMOTE_CORES CPU cores"
    
    echo_status "Executing build-rt-kernel.sh on remote server..."
    ssh -i $SSH_KEY -t $REMOTE_USER@$REMOTE_HOST "cd ~ && ./build-rt-kernel.sh --cores=$REMOTE_CORES"
    echo_status "Script execution completed on remote server."
else
    echo_status "Script execution skipped."
    echo_status "You can manually execute the script on the remote server using:"
    echo "ssh -i $SSH_KEY -t $REMOTE_USER@$REMOTE_HOST \"cd ~ && ./build-rt-kernel.sh\""
fi

echo
echo_status "Script completed successfully!"
