#!/bin/bash
#
# Script to build a PREEMPT_RT kernel from Amazon Linux 2023 source RPM
# This approach ensures all Amazon-specific drivers (including ENA) are properly included

set -e  # Exit on error

# Function to show usage information
function show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --debug    Enable debug mode with verbose output"
    echo "  --help     Show this help message"
    echo
    echo "This script builds a PREEMPT_RT kernel from Amazon Linux source RPM."
    echo "It ensures all Amazon-specific drivers (including ENA) are properly included."
    echo
    echo "The script will:"
    echo "1. Enable the Amazon Linux source repository"
    echo "2. Download the kernel source RPM"
    echo "3. Modify the spec file and config files to enable PREEMPT_RT"
    echo "4. Build the kernel with RT support"
    echo "5. Create RPM packages in ~/rt-kernel-rpms/"
    echo
    echo "After building, you can install the kernel with:"
    echo "sudo dnf install ~/rt-kernel-rpms/kernel*.rpm"
    echo "sudo grub2-mkconfig -o /boot/grub2/grub.cfg"
    echo
    exit 0
}

# Parse command line arguments
DEBUG=false
for arg in "$@"; do
    case $arg in
        --debug)
        DEBUG=true
        shift
        ;;
        --help)
        show_usage
        ;;
    esac
done

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

# Function to check if command exists and install it if missing
function check_command() {
    if ! command -v $1 &> /dev/null; then
        echo_warning "$1 is not installed. Attempting to install it..."
        case $1 in
            rpm)
                sudo dnf install -y rpm
                ;;
            dnf)
                echo_error "dnf is not installed. This is unexpected as it's the package manager for Amazon Linux 2023."
                echo_error "Please install dnf manually and try again."
                exit 1
                ;;
            rpmbuild)
                sudo dnf install -y rpm-build
                ;;
            *)
                sudo dnf install -y $1 || {
                    echo_error "Failed to install $1. Please install it manually and try again."
                    exit 1
                }
                ;;
        esac
        
        # Check if installation was successful
        if ! command -v $1 &> /dev/null; then
            echo_error "Failed to install $1. Please install it manually and try again."
            exit 1
        else
            echo_status "$1 has been installed successfully."
        fi
    fi
}

# Check for required commands
echo_status "Checking for required commands..."
check_command rpm
check_command dnf
check_command rpmbuild

# Install required packages
echo_status "Installing required build tools..."
sudo dnf install -y rpm-build rpmdevtools yum-utils gcc make ncurses-devel bison flex elfutils-libelf-devel openssl-devel \
    asciidoc audit-libs-devel binutils-devel elfutils-devel gdb glibc-static javapackages-local \
    libcap-devel libzstd-devel newt-devel numactl-devel pciutils-devel pesign python3-devel xmlto

# Check if source repository is already enabled
echo_status "Checking source repository..."
if sudo dnf repolist | grep -q "amazonlinux-source"; then
    echo_status "Source repository is already enabled"
else
    # Check if the repo file exists
    if [ -f "/etc/yum.repos.d/amazonlinux.repo" ]; then
        echo_status "Found amazonlinux.repo file, checking if source repo is defined but disabled..."
        if grep -q "amazonlinux-source" /etc/yum.repos.d/amazonlinux.repo; then
            echo_status "Source repository is defined in amazonlinux.repo, enabling it..."
            sudo sed -i '/\[amazonlinux-source\]/,/^\[/ s/enabled=0/enabled=1/' /etc/yum.repos.d/amazonlinux.repo
            echo_status "Repository enabled, verifying..."
            if sudo dnf repolist | grep -q "amazonlinux-source"; then
                echo_status "Source repository successfully enabled"
            else
                echo_warning "Source repository not showing in repolist after enabling"
                echo_status "Trying alternative method..."
                sudo dnf config-manager --set-enabled amazonlinux-source
            fi
        else
            echo_error "Source repository not defined in amazonlinux.repo"
            echo_error "Please manually add the source repository to /etc/yum.repos.d/amazonlinux.repo"
            exit 1
        fi
    else
        echo_status "Trying to enable source repository using dnf config-manager..."
        sudo dnf config-manager --set-enabled amazonlinux-source || {
            echo_error "Failed to enable source repository"
            echo_error "Please manually enable the source repository and try again"
            echo_error "You can add the following to /etc/yum.repos.d/amazonlinux.repo:"
            echo
            echo "[amazonlinux-source]"
            echo "name=Amazon Linux 2023 repository - Source packages"
            echo "mirrorlist=https://al2023-repos-\$awsregion-de612dc2.s3\$dualstack.\$awsregion.\$awsdomain/core/mirrors/\$releasever/SRPMS/\$mirrorlist"
            echo "enabled=1"
            echo "repo_gpgcheck=0"
            echo "type=rpm"
            echo "gpgcheck=1"
            echo "gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-amazon-linux-2023"
            echo
            exit 1
        }
    fi
fi

# Set up RPM build environment
echo_status "Setting up RPM build environment..."
rpmdev-setuptree

# Check for available kernel source packages
echo_status "Checking available kernel source packages..."
KERNEL_SRPMS=$(sudo dnf list | grep kernel | grep src)
echo "$KERNEL_SRPMS"

# Try to find kernel6.12 source RPM
if echo "$KERNEL_SRPMS" | grep -q "kernel6.12.src"; then
    KERNEL_PACKAGE="kernel6.12"
    SPEC_FILE="kernel6.12.spec"
    echo_status "Found kernel6.12 source package"
elif echo "$KERNEL_SRPMS" | grep -q "kernel.src"; then
    KERNEL_PACKAGE="kernel"
    SPEC_FILE="kernel.spec"
    echo_warning "kernel6.12 not found, using kernel package instead"
else
    echo_error "No suitable kernel source package found"
    exit 1
fi

# Download the kernel source RPM
echo_status "Downloading ${KERNEL_PACKAGE} source RPM..."
mkdir -p ~/rpmbuild/SRPMS
cd ~/rpmbuild/SRPMS
echo_status "Running: sudo dnf download --source ${KERNEL_PACKAGE}"
sudo dnf download --source ${KERNEL_PACKAGE}
if [ ! -f ${KERNEL_PACKAGE}-*.src.rpm ]; then
    echo_error "Failed to download ${KERNEL_PACKAGE} source RPM"
    exit 1
fi

# Install the source RPM
echo_status "Installing source RPM..."
rpm -ivh ${KERNEL_PACKAGE}-*.src.rpm || {
    echo_error "Failed to install source RPM"
    echo_status "Available source RPMs:"
    ls -la *.src.rpm
    exit 1
}

# Backup original spec file
echo_status "Backing up original spec file..."
cd ~/rpmbuild/SPECS
if [ ! -f ${SPEC_FILE} ]; then
    echo_error "${SPEC_FILE} not found! Checking available spec files..."
    ls -la *.spec
    echo_error "Please check if the correct source RPM was installed"
    exit 1
fi
cp ${SPEC_FILE} ${SPEC_FILE}.orig

# Modify the spec file to enable PREEMPT_RT
echo_status "Modifying spec file to enable PREEMPT_RT..."
echo_status "Checking for preemption settings in spec file..."
grep -E "CONFIG_PREEMPT|CONFIG_HZ" ${SPEC_FILE} || echo_warning "Preemption settings not found in spec file"

# Make the changes
sed -i 's/# CONFIG_PREEMPT_RT is not set/CONFIG_PREEMPT_RT=y/' ${SPEC_FILE}
sed -i 's/CONFIG_PREEMPT_VOLUNTARY=y/# CONFIG_PREEMPT_VOLUNTARY is not set/' ${SPEC_FILE}
sed -i 's/CONFIG_PREEMPT=y/# CONFIG_PREEMPT is not set/' ${SPEC_FILE}
sed -i 's/CONFIG_PREEMPT_NONE=y/# CONFIG_PREEMPT_NONE is not set/' ${SPEC_FILE}
sed -i 's/CONFIG_HZ=100/CONFIG_HZ=1000/' ${SPEC_FILE}

# Verify changes
echo_status "Verifying changes to spec file..."
grep -E "CONFIG_PREEMPT|CONFIG_HZ" ${SPEC_FILE} || echo_warning "Failed to modify preemption settings"

# Add RT suffix to kernel release
echo_status "Adding RT suffix to kernel release..."
sed -i 's/^\%define dist_tag.*$/\%define dist_tag \%{?dist\}.rt/' ${SPEC_FILE}

# Modify config files directly if needed
echo_status "Checking for config files in SOURCES directory..."
cd ~/rpmbuild/SOURCES
CONFIG_FILES=$(find . -name "config-*" -type f)
if [ -n "$CONFIG_FILES" ]; then
    echo_status "Found config files, modifying them to enable PREEMPT_RT..."
    for config_file in $CONFIG_FILES; do
        echo_status "Modifying $config_file..."
        # Enable PREEMPT_RT
        sed -i 's/# CONFIG_PREEMPT_RT is not set/CONFIG_PREEMPT_RT=y/' "$config_file"
        # Disable other preemption models
        sed -i 's/CONFIG_PREEMPT_VOLUNTARY=y/# CONFIG_PREEMPT_VOLUNTARY is not set/' "$config_file"
        sed -i 's/CONFIG_PREEMPT=y/# CONFIG_PREEMPT is not set/' "$config_file"
        sed -i 's/CONFIG_PREEMPT_NONE=y/# CONFIG_PREEMPT_NONE is not set/' "$config_file"
        # Set timer frequency to 1000 Hz
        sed -i 's/CONFIG_HZ=100/CONFIG_HZ=1000/' "$config_file"
        sed -i 's/CONFIG_HZ_100=y/# CONFIG_HZ_100 is not set/' "$config_file"
        sed -i 's/# CONFIG_HZ_1000 is not set/CONFIG_HZ_1000=y/' "$config_file"
        # Configure RCU for RT
        sed -i 's/# CONFIG_RCU_BOOST is not set/CONFIG_RCU_BOOST=y/' "$config_file"
        sed -i 's/# CONFIG_RCU_NOCB_CPU is not set/CONFIG_RCU_NOCB_CPU=y/' "$config_file"
    done
else
    echo_warning "No config files found in SOURCES directory. Config changes will rely on spec file modifications."
fi

# Check for build dependencies
echo_status "Checking for build dependencies..."
cd ~/rpmbuild/SPECS
BUILD_DEPS=$(grep -i "buildrequires:" ${SPEC_FILE} | sed 's/BuildRequires: *//i' | tr -d ',' | sort | uniq)
if [ "$DEBUG" = true ]; then
    echo_status "Build dependencies found in spec file:"
    echo "$BUILD_DEPS"
fi

echo_status "Installing build dependencies..."
sudo dnf builddep -y ${SPEC_FILE}

# Build the kernel
echo_status "Building the kernel (this may take a while)..."

# Use verbose output if debug mode is enabled
if [ "$DEBUG" = true ]; then
    echo_status "Debug mode enabled, using verbose output..."
    rpmbuild -ba --verbose ${SPEC_FILE}
else
    rpmbuild -ba ${SPEC_FILE}
fi

# Check if build was successful
if [ $? -eq 0 ]; then
    echo_status "Kernel build completed successfully!"
    echo_status "RPM packages are available in ~/rpmbuild/RPMS/x86_64/"
    
    # List the built RPMs
    echo_status "Built kernel packages:"
    ls -la ~/rpmbuild/RPMS/x86_64/${KERNEL_PACKAGE}-*.rpm
    
    # Create a directory to store the RT kernel RPMs
    mkdir -p ~/rt-kernel-rpms
    cp ~/rpmbuild/RPMS/x86_64/${KERNEL_PACKAGE}-*.rpm ~/rt-kernel-rpms/
    
    echo
    echo_status "To install the RT kernel, run:"
    echo_status "sudo dnf install ~/rt-kernel-rpms/${KERNEL_PACKAGE}-*.rpm"
    echo_status "sudo grub2-mkconfig -o /boot/grub2/grub.cfg"
    echo
    echo_status "After installation, reboot your system to use the new kernel."
    echo_status "To verify the RT kernel is running after reboot:"
    echo_status "uname -r  # Should show the kernel version with .rt suffix"
    echo_status "cat /sys/kernel/realtime  # Should return 1 if RT is enabled"
else
    echo_error "Kernel build failed!"
    echo_error "Check the build logs for errors."
    exit 1
fi
