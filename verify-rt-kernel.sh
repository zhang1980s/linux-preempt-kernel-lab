#!/bin/bash
#
# Script to verify RT kernel installation and test real-time capabilities
# This script should be run on the remote host after installing the RT kernel

set -e  # Exit on error

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

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo_error "This script must be run as root or with sudo."
    exit 1
fi

echo "============================================="
echo "   RT Kernel Verification and Testing Tool   "
echo "============================================="
echo

# Verify kernel version
echo_status "Checking kernel version..."
KERNEL_VERSION=$(uname -r)
echo "Current kernel: $KERNEL_VERSION"

# Check if kernel has RT capabilities
# First try to check the kernel version string
if echo $KERNEL_VERSION | grep -q "rt"; then
    echo_status "RT kernel detected by version string: $KERNEL_VERSION"
else
    # If not found in version string, check kernel config
    if [ -f "/boot/config-$(uname -r)" ]; then
        if grep -q "CONFIG_PREEMPT_RT=y" "/boot/config-$(uname -r)"; then
            echo_status "RT kernel detected by config: PREEMPT_RT is enabled"
        else
            echo_error "RT kernel not detected. Current kernel: $KERNEL_VERSION"
            echo_error "PREEMPT_RT not found in kernel config."
            echo_error "Please reboot into the RT kernel before running this script."
            exit 1
        fi
    else
        echo_warning "Cannot verify RT kernel: config file not found."
        echo_warning "Proceeding with tests, but results may not be valid."
    fi
fi

# Check kernel command line for RT-related parameters
echo_status "Checking kernel command line parameters..."
CMDLINE=$(cat /proc/cmdline)
echo "Kernel command line: $CMDLINE"

# Check for RT-specific features
echo_status "Checking for RT-specific features..."
if [ -f "/sys/kernel/realtime" ]; then
    RT_ENABLED=$(cat /sys/kernel/realtime)
    echo_status "RT feature enabled: $RT_ENABLED"
else
    echo_warning "RT feature file not found. This might be normal depending on kernel version."
fi

# Check for preemption model
echo_status "Checking preemption model..."
if [ -f "/sys/kernel/debug/sched_features" ]; then
    echo "Scheduler features:"
    cat /sys/kernel/debug/sched_features
else
    echo_warning "Scheduler features file not found. Debug filesystem might not be mounted."
    echo_status "Mounting debugfs..."
    sudo mount -t debugfs none /sys/kernel/debug 2>/dev/null || true
    
    if [ -f "/sys/kernel/debug/sched_features" ]; then
        echo "Scheduler features:"
        cat /sys/kernel/debug/sched_features
    fi
fi

# Check config
echo_status "Checking kernel config for RT options..."
if [ -f "/boot/config-$(uname -r)" ]; then
    CONFIG_FILE="/boot/config-$(uname -r)"
    
    echo "PREEMPT_RT: $(grep CONFIG_PREEMPT_RT $CONFIG_FILE || echo 'Not found')"
    echo "PREEMPT: $(grep CONFIG_PREEMPT= $CONFIG_FILE || echo 'Not found')"
    echo "HIGH_RES_TIMERS: $(grep CONFIG_HIGH_RES_TIMERS $CONFIG_FILE || echo 'Not found')"
    echo "NO_HZ_FULL: $(grep CONFIG_NO_HZ_FULL $CONFIG_FILE || echo 'Not found')"
    echo "HZ: $(grep CONFIG_HZ= $CONFIG_FILE || echo 'Not found')"
    
    # Check RCU configurations
    echo_status "Checking RCU configurations..."
    echo "RCU_BOOST: $(grep CONFIG_RCU_BOOST $CONFIG_FILE || echo 'Not found')"
    echo "RCU_BOOST_DELAY: $(grep CONFIG_RCU_BOOST_DELAY $CONFIG_FILE || echo 'Not found')"
    echo "RCU_NOCB_CPU: $(grep CONFIG_RCU_NOCB_CPU $CONFIG_FILE || echo 'Not found')"
    echo "RCU_NOCB_CPU_CB_BOOST: $(grep CONFIG_RCU_NOCB_CPU_CB_BOOST $CONFIG_FILE || echo 'Not found')"
    
    # Check AWS-specific configurations
    echo_status "Checking AWS-specific configurations..."
    echo "ENA_ETHERNET: $(grep CONFIG_ENA_ETHERNET $CONFIG_FILE || echo 'Not found')"
    echo "ENA: $(grep CONFIG_ENA $CONFIG_FILE || echo 'Not found')"
    echo "NVME: $(grep CONFIG_BLK_DEV_NVME $CONFIG_FILE || echo 'Not found')"
    echo "KVM_GUEST: $(grep CONFIG_KVM_GUEST $CONFIG_FILE || echo 'Not found')"
    echo "HYPERV_GUEST: $(grep CONFIG_HYPERV_GUEST $CONFIG_FILE || echo 'Not found')"
    
    # Check if critical AWS drivers are loaded
    echo_status "Checking if AWS drivers are loaded..."
    if lsmod | grep -q ena; then
        echo "ENA driver: Loaded"
    else
        echo_warning "ENA driver: Not loaded - this may cause network issues!"
    fi
    
    if lsmod | grep -q nvme; then
        echo "NVMe driver: Loaded"
    else
        echo_warning "NVMe driver: Not loaded - this may cause storage issues!"
    fi
else
    echo_warning "Kernel config file not found."
fi

# Check for rt-tests package
echo_status "Checking for rt-tests package..."
if ! check_command cyclictest 2>/dev/null; then
    echo_warning "rt-tests package not installed. Skipping latency tests."
    echo_warning "To install rt-tests, you may need to build it from source:"
    echo_warning "git clone https://git.kernel.org/pub/scm/utils/rt-tests/rt-tests.git"
    echo_warning "cd rt-tests && make && sudo make install"
    SKIP_LATENCY_TESTS=1
else
    echo_status "rt-tests package is installed."
    SKIP_LATENCY_TESTS=0
fi

# Run basic latency test if rt-tests is available
if [ $SKIP_LATENCY_TESTS -eq 0 ]; then
    echo_status "Running basic latency test (duration: 10 seconds)..."
    echo "This test measures the latency of the system under various conditions."
    echo "Lower values indicate better real-time performance."
    echo

    sudo cyclictest -l 100000 -m -n -p 80 -t 4 -D 10
else
    echo_status "Skipping latency tests due to missing rt-tests package."
fi

# Run extended latency test if rt-tests is available
if [ $SKIP_LATENCY_TESTS -eq 0 ]; then
    echo
    echo_status "Running extended latency test with system load (duration: 30 seconds)..."
    echo "This test measures latency while the system is under load."
    
    # Check if stress-ng is available
    if command -v stress-ng &> /dev/null; then
        echo "Starting background load..."
        # Create background load
        sudo stress-ng --cpu 2 --io 1 --vm 1 --vm-bytes 128M --timeout 35s &
        STRESS_PID=$!

        # Wait for stress to start
        sleep 5

        # Run cyclictest with background load
        sudo cyclictest -l 1000000 -m -n -p 80 -t 4 -D 30

        # Make sure stress has finished
        wait $STRESS_PID 2>/dev/null || true
    else
        echo_warning "stress-ng not installed. Running cyclictest without background load."
        sudo cyclictest -l 1000000 -m -n -p 80 -t 4 -D 30
    fi
fi

echo
echo_status "Testing complete!"
echo
echo "============================================="
echo "   RT Kernel Verification Summary   "
echo "============================================="
echo
echo "Kernel version: $KERNEL_VERSION"
# Check if kernel has RT capabilities
if echo $KERNEL_VERSION | grep -q "rt"; then
    echo "RT kernel (by version string): YES"
elif [ -f "/boot/config-$(uname -r)" ] && grep -q "CONFIG_PREEMPT_RT=y" "/boot/config-$(uname -r)"; then
    echo "RT kernel (by config): YES"
else
    echo "RT kernel: NO"
fi

# Check timer frequency
if [ -f "/boot/config-$(uname -r)" ]; then
    HZ_VALUE=$(grep "CONFIG_HZ=" "/boot/config-$(uname -r)" | cut -d'=' -f2)
    echo "Timer frequency: $HZ_VALUE Hz"
    if [ "$HZ_VALUE" == "1000" ]; then
        echo "Timer frequency set to 1000 Hz: YES"
    else
        echo "Timer frequency set to 1000 Hz: NO (current: $HZ_VALUE Hz)"
    fi
    
    # Check AWS-specific configurations in summary
    echo
    echo "AWS EC2 Compatibility:"
    if grep -q "CONFIG_ENA_ETHERNET=y" "/boot/config-$(uname -r)"; then
        echo "ENA Ethernet support: YES"
    else
        echo "ENA Ethernet support: NO (may cause network issues)"
    fi
    
    if grep -q "CONFIG_BLK_DEV_NVME=y" "/boot/config-$(uname -r)"; then
        echo "NVMe storage support: YES"
    else
        echo "NVMe storage support: NO (may cause storage issues)"
    fi
    
    if grep -q "CONFIG_KVM_GUEST=y" "/boot/config-$(uname -r)"; then
        echo "KVM guest support: YES"
    else
        echo "KVM guest support: NO (may cause virtualization issues)"
    fi
    
    if lsmod | grep -q ena; then
        echo "ENA driver loaded: YES"
    else
        echo "ENA driver loaded: NO (network may not function properly)"
    fi
    
    # Check RCU configurations in summary
    echo
    echo "RCU Configuration for Real-time Performance:"
    if grep -q "CONFIG_RCU_BOOST=y" "/boot/config-$(uname -r)"; then
        echo "RCU priority boosting: YES"
    else
        echo "RCU priority boosting: NO (may cause priority inversion issues)"
    fi
    
    if grep -q "CONFIG_RCU_NOCB_CPU=y" "/boot/config-$(uname -r)"; then
        echo "RCU callback offloading: YES"
    else
        echo "RCU callback offloading: NO (may cause latency spikes)"
    fi
fi

echo
echo "For optimal RT performance, consider these tuning options:"
echo "1. Update GRUB with these parameters:"
echo "   isolcpus=1-3 nohz_full=1-3 rcu_nocbs=1-3 intel_pstate=disable nosoftlockup"
echo
echo "2. Set CPU affinity for critical processes:"
echo "   taskset -c 1 your_rt_application"
echo
echo "3. Set real-time priority for processes:"
echo "   chrt -f 99 your_rt_application"
echo
echo "4. Disable unnecessary services:"
echo "   systemctl disable NetworkManager"
echo "   systemctl disable firewalld"
echo "   systemctl disable tuned"
echo
echo "5. Consider using a real-time process shield:"
echo "   https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux_for_real_time/8/html/tuning_guide/proc-shield_tuning-guide"
echo
echo "============================================="
