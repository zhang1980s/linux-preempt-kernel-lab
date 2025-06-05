#!/bin/bash
#
# Automated script to build a Linux kernel with PREEMPT_RT support for Amazon Linux 2023
# This script automates the steps described in the README.md file

set -e  # Exit on error

# Configuration variables - adjust as needed
KERNEL_VERSION="6.12.32"
BUILD_DIR="$HOME/rt-kernel-build"

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

# Set custom kernel name with -rt-custom suffix
echo_status "Setting custom kernel name with -rt-custom suffix..."
./scripts/config --set-str LOCALVERSION "-rt-custom"

# Set timer frequency to 1000 Hz
echo_status "Setting timer frequency to 1000 Hz..."
./scripts/config --set-val CONFIG_HZ 1000

# Configure RCU subsystem for real-time performance
echo_status "Configuring RCU subsystem for real-time performance..."
./scripts/config --disable RCU_EXPERT
./scripts/config --enable RCU_BOOST
./scripts/config --set-val RCU_BOOST_DELAY 500
./scripts/config --enable RCU_NOCB_CPU
./scripts/config --disable RCU_NOCB_CPU_DEFAULT_ALL
./scripts/config --enable RCU_NOCB_CPU_CB_BOOST
./scripts/config --disable RCU_LAZY

# Enable AWS-specific configurations
echo_status "Enabling AWS-specific configurations..."
# Elastic Network Adapter (ENA) support - essential for EC2 networking
./scripts/config --module AMAZON_ENA_ETHERNET

# NVMe support for AWS storage
./scripts/config --enable NVME_CORE
./scripts/config --enable BLK_DEV_NVME

# KVM support (for KVM-based EC2 instances)
./scripts/config --enable KVM_GUEST
./scripts/config --enable HYPERV_GUEST

# AWS NitroV2 support
./scripts/config --enable PCI_HYPERV_INTERFACE

# ACPI and other hardware support
./scripts/config --enable ACPI
./scripts/config --enable ACPI_EC_DEBUGFS
./scripts/config --enable ACPI_BGRT

# Cloud-init related
./scripts/config --enable RANDOM_TRUST_CPU

# Disable Xen support as it's not needed
./scripts/config --disable XEN
./scripts/config --disable XEN_PV
./scripts/config --disable XEN_HVM
./scripts/config --disable XEN_PVHVM

# Verify critical AWS configurations
echo_status "Verifying AWS-specific configurations..."
if ! grep -q "CONFIG_AMAZON_ENA_ETHERNET=m" .config && ! grep -q "CONFIG_AMAZON_ENA_ETHERNET=y" .config; then
    echo_warning "Amazon ENA Ethernet support is not enabled! This may cause network issues on EC2."
fi
if ! grep -q "CONFIG_BLK_DEV_NVME=y" .config; then
    echo_warning "NVMe support is not enabled! This may cause storage issues on EC2."
fi

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
RPM_DIR="rpmbuild/RPMS/x86_64"
if [ -d "$RPM_DIR" ] && ls $RPM_DIR/kernel-*.rpm 1> /dev/null 2>&1; then
    echo_status "RPM packages created successfully:"
    ls -la $RPM_DIR/kernel-*.rpm
    
    # Copy RPM packages to parent directory
    echo_status "Copying RPM packages to parent directory..."
    cd ..
    mkdir -p kernel-rpms
    cp linux-$KERNEL_VERSION/$RPM_DIR/kernel-*.rpm kernel-rpms/
    echo_status "Copied RPM packages:"
    ls -la kernel-rpms/
else
    echo_error "Failed to create RPM packages!"
    cd ..
    exit 1
fi

echo
echo_status "Build process completed successfully!"
echo_status "RPM packages are available in: $BUILD_DIR/kernel-rpms/"
echo
echo_status "To install the kernel locally, run:"
echo_status "sudo dnf install -y $BUILD_DIR/kernel-rpms/kernel-*.rpm"
echo_status "sudo grub2-mkconfig -o /boot/grub2/grub.cfg"
echo_status "sudo grubby --set-default /boot/vmlinuz-${KERNEL_VERSION}-rt-custom"
echo
echo_status "After installation, reboot your system to use the new kernel."
echo
echo_status "Script completed successfully!"
