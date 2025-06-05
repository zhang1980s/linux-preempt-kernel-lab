# Building and Installing a Preemptible RT Kernel on Amazon Linux 2023

This guide provides step-by-step instructions for building and installing a Linux kernel with the PREEMPT_RT patch (Real-Time kernel) on Amazon Linux 2023.

## Table of Contents

- [Introduction](#introduction)
- [Prerequisites](#prerequisites)
- [Build Environment Setup](#build-environment-setup)
- [Kernel Source](#kernel-source)
- [Building the RT Kernel](#building-the-rt-kernel)
- [Installing the RT Kernel](#installing-the-rt-kernel)
- [Testing and Verification](#testing-and-verification)
- [Troubleshooting](#troubleshooting)

## Introduction

The PREEMPT_RT patch (Real-Time patch) modifies the Linux kernel to minimize latency and improve determinism, making it suitable for real-time applications. This is achieved by making most kernel code preemptible, including critical sections, interrupt handlers, and spinlocks.

### Key Benefits of RT Kernel

- Lower and more predictable latency
- Improved system responsiveness under load
- Better determinism for time-sensitive applications
- Priority inheritance for kernel locks

## Prerequisites

### Local Build Environment

- Git
- Build tools (gcc, make, etc.)
- Sufficient disk space (~15GB for build process)
- Internet connection to download source code and patches

### Remote EC2 Instance

- Amazon Linux 2023 x86 instance
- SSH access configured
- Sufficient disk space for kernel installation (~500MB)
- Ability to reboot the instance

## Build Environment Setup

The following steps will be performed on the local build environment.

### 1. Install Required Packages

```bash
sudo dnf update -y
sudo dnf install -y git bc gcc gcc-c++ make ncurses-devel openssl-devel elfutils-libelf-devel bison flex dwarves rpm-build perl
```

## Kernel Source

For this guide, we'll use Linux kernel version 6.12.32, which natively supports the PREEMPT option without requiring a separate RT patch.

### 1. Download Kernel Source

```bash
mkdir -p ~/rt-kernel-build
cd ~/rt-kernel-build
wget https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.12.32.tar.xz
tar xf linux-6.12.32.tar.xz
cd linux-6.12.32
```

## Building the RT Kernel

### 1. Configure Kernel

Start with the Amazon Linux 2023 kernel configuration as a base:

```bash
# Copy the current kernel config as a starting point
sudo cp /boot/config-$(uname -r) .config

# Update the configuration for the new kernel version
make olddefconfig

# Enable RT preemption
scripts/config --enable HIGH_RES_TIMERS
scripts/config --enable PREEMPT
scripts/config --disable PREEMPT_VOLUNTARY
scripts/config --disable PREEMPT_NONE
scripts/config --enable PREEMPT_RT

# Set timer frequency to 1000 Hz for better real-time performance
scripts/config --set-val CONFIG_HZ 1000

# Optional: Make additional configuration changes
make menuconfig
```

### 2. Build the Kernel

```bash
# The script automatically detects the number of cores on your system
# You can also specify the number of cores manually with the --cores parameter
./build-rt-kernel.sh --cores=8  # Use 8 cores for compilation

# Or let the script auto-detect the number of cores
./build-rt-kernel.sh

# The script will:
# - Build the kernel and modules
# - Build binary kernel RPM packages (no git repository required)
```


The build process will create several RPM packages with a "preempt-" prefix in the `~/rt-kernel-build/preempt-rpms` directory.

## Installing the RT Kernel

### 1. Transfer RPM Packages to Remote EC2 Instance

```bash
cd ~/rt-kernel-build
scp -i /path/to/your/ssh/key.pem preempt-rpms/preempt-*.rpm ec2-user@your-remote-host:~/
```

### 2. Install the Kernel on Remote EC2 Instance

SSH into the remote instance and install the kernel packages:

```bash
ssh -i /path/to/your/ssh/key.pem ec2-user@your-remote-host

# On the remote instance:
sudo dnf install -y ~/preempt-*.rpm
```

### 3. Update GRUB Configuration

```bash
# Update GRUB configuration
sudo grub2-mkconfig -o /boot/grub2/grub.cfg

# Set the new kernel as default (adjust the menu entry number if needed)
sudo grubby --set-default /boot/vmlinuz-6.12.32
```

### 4. Reboot the System

```bash
sudo reboot
```

## Testing and Verification

After rebooting, verify that the system is running the RT kernel:

```bash
# Check kernel version
uname -a

# Verify RT capabilities
grep -i "rt" /proc/version

# Check for RT-specific features
cat /sys/kernel/realtime
```

### Running RT Tests

The `rt-tests` package is useful for verifying real-time performance, but it may not be available in the default Amazon Linux 2023 repositories. You can build it from source if needed:

```bash
# Clone and build rt-tests from source
git clone https://git.kernel.org/pub/scm/utils/rt-tests/rt-tests.git
cd rt-tests
make
sudo make install

# Run cyclictest to measure latency
sudo cyclictest -l 1000000 -m -n -p 80 -t 10
```

Interpret the results:
- Look for the "Max Latencies" values
- Lower values indicate better real-time performance
- High maximum latencies may indicate issues with the RT configuration

## Troubleshooting

### Common Issues

1. **Boot Failure**
   - Boot into the previous kernel using GRUB menu
   - Check kernel logs: `journalctl -b -1`

2. **High Latency**
   - Disable CPU power management features
   - Isolate CPUs for real-time tasks
   - Disable unnecessary services

3. **Module Loading Failures**
   - Ensure all necessary modules are built
   - Check module dependencies

### Performance Tuning

For optimal RT performance:

1. Update the GRUB command line with these parameters:
   ```
   isolcpus=1-3 nohz_full=1-3 rcu_nocbs=1-3 intel_pstate=disable nosoftlockup
   ```

2. Set CPU affinity for critical processes:
   ```bash
   taskset -c 1 your_rt_application
   ```

3. Set real-time priority for processes:
   ```bash
   chrt -f 99 your_rt_application
   ```
