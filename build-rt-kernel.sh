#!/bin/bash
#
# Automated script to build a Linux kernel with PREEMPT_RT support for Amazon Linux 2023
# This script automates the steps described in the README.md file

set -e  # Exit on error

# Configuration variables - adjust as needed
KERNEL_VERSION="6.12.32"
BUILD_DIR="$HOME/rt-kernel-build"
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

# Function to check if command exists
function check_command() {
    if ! command -v $1 &> /dev/null; then
        echo_error "$1 is not installed. Please install it and try again."
        exit 1
    fi
}

# Install required packages first to ensure all commands are available
echo_status "Installing required packages..."
sudo dnf update -y
sudo dnf install -y git bc gcc gcc-c++ make ncurses-devel openssl-devel \
    elfutils-libelf-devel bison flex dwarves rpm-build wget tar patch perl

# Check for required commands
echo_status "Checking for required commands..."
check_command wget
check_command tar
check_command patch
check_command make
check_command gcc

# Additional packages that might be needed
echo_status "Installing additional packages..."
# Install stress-ng if available
sudo dnf install -y stress-ng || echo_warning "stress-ng package not available, skipping..."

# Create build directory
echo_status "Creating build directory at $BUILD_DIR..."
mkdir -p $BUILD_DIR
cd $BUILD_DIR

# Download kernel source
echo_status "Downloading Linux kernel $KERNEL_VERSION..."
if [ ! -f "linux-$KERNEL_VERSION.tar.xz" ]; then
    wget https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$KERNEL_VERSION.tar.xz
else
    echo_warning "Kernel source already downloaded, skipping..."
fi

# Extract kernel source
echo_status "Extracting kernel source..."
if [ ! -d "linux-$KERNEL_VERSION" ]; then
    tar xf linux-$KERNEL_VERSION.tar.xz
else
    echo_warning "Kernel source already extracted, skipping..."
fi

# Change to kernel source directory
cd linux-$KERNEL_VERSION

# No need to download and apply RT patch for kernel 6.12.32 as it natively supports PREEMPT_RT

# Configure kernel
echo_status "Configuring kernel..."
if [ -f "/boot/config-$(uname -r)" ]; then
    sudo cp /boot/config-$(uname -r) .config
    echo_status "Using current kernel config as base..."
else
    echo_warning "Current kernel config not found, using default config..."
    make defconfig
fi

# Update config for new kernel version
echo_status "Updating config for new kernel version..."
make olddefconfig

# Enable RT preemption
echo_status "Enabling RT preemption options..."
./scripts/config --enable HIGH_RES_TIMERS
./scripts/config --enable PREEMPT
./scripts/config --disable PREEMPT_VOLUNTARY
./scripts/config --disable PREEMPT_NONE
./scripts/config --enable PREEMPT_RT

# Set timer frequency to 1000 Hz
echo_status "Setting timer frequency to 1000 Hz..."
./scripts/config --set-val CONFIG_HZ 1000

# Parse command line arguments
MENUCONFIG=false
CORES_ARG=""

for arg in "$@"; do
    case $arg in
        --menuconfig)
        MENUCONFIG=true
        shift
        ;;
        --cores=*)
        CORES_ARG="${arg#*=}"
        shift
        ;;
    esac
done

# Optional: Run menuconfig if requested
if [ "$MENUCONFIG" = true ]; then
    echo_status "Running menuconfig for manual configuration..."
    make menuconfig
fi

# Build kernel
echo_status "Building kernel and modules..."
# Set number of cores for compilation
if [ -n "$CORES_ARG" ]; then
    CORES=$CORES_ARG
    echo_status "Using specified $CORES cores for compilation..."
else
    CORES=$(nproc)
    echo_status "Using detected $CORES cores for compilation..."
fi
make -j$CORES

# Build binary RPM packages (doesn't require git repository)
echo_status "Building binary RPM packages..."
make -j$CORES binrpm-pkg

# Check if RPM packages were created
cd ..
if ls kernel-*.rpm 1> /dev/null 2>&1; then
    echo_status "RPM packages created successfully:"
    ls -la kernel-*.rpm
else
    echo_error "Failed to create RPM packages!"
    exit 1
fi

# Ask if user wants to transfer and install packages
echo
echo_status "Build process completed successfully!"
echo
echo "The following options are available:"
echo "1. Transfer RPM packages to remote host and install"
echo "2. Exit without transferring packages"
echo

read -p "Enter your choice (1 or 2): " choice

if [ "$choice" == "1" ]; then
    # Transfer RPM packages to remote host
    echo_status "Transferring RPM packages to $REMOTE_HOST..."
    scp -i $SSH_KEY kernel-*.rpm $REMOTE_USER@$REMOTE_HOST:~/
    
    # Install packages on remote host
    echo_status "Installing kernel on remote host..."
    ssh -i $SSH_KEY $REMOTE_USER@$REMOTE_HOST "sudo dnf install -y ~/kernel*.rpm"
    
    # Update GRUB configuration
    echo_status "Updating GRUB configuration on remote host..."
    ssh -i $SSH_KEY $REMOTE_USER@$REMOTE_HOST "sudo grub2-mkconfig -o /boot/grub2/grub.cfg"
    
    # Set new kernel as default
    echo_status "Setting new kernel as default on remote host..."
    ssh -i $SSH_KEY $REMOTE_USER@$REMOTE_HOST "sudo grubby --set-default /boot/vmlinuz-$KERNEL_VERSION"
    
    echo
    echo_status "Kernel installation completed successfully!"
    echo_status "You can now reboot the remote host to use the new kernel."
    echo_status "To reboot, run: ssh -i $SSH_KEY $REMOTE_USER@$REMOTE_HOST 'sudo reboot'"
    echo
    
    # Ask if user wants to reboot remote host
    read -p "Do you want to reboot the remote host now? (y/n): " reboot_choice
    if [ "$reboot_choice" == "y" ] || [ "$reboot_choice" == "Y" ]; then
        echo_status "Rebooting remote host..."
        ssh -i $SSH_KEY $REMOTE_USER@$REMOTE_HOST 'sudo reboot'
        echo_status "Remote host is rebooting. Wait a few minutes before reconnecting."
    else
        echo_status "Skipping reboot. Remember to reboot the remote host to use the new kernel."
    fi
else
    echo_status "Exiting without transferring packages."
    echo_status "You can manually transfer and install the packages later using the commands in the README.md file."
fi

echo
echo_status "Script completed successfully!"
