# Building and Installing a Preemptible RT Kernel on Amazon Linux 2023

This guide provides step-by-step instructions for building and installing a Linux kernel with the PREEMPT_RT patch (Real-Time kernel) on Amazon Linux 2023.

## Table of Contents

- [Introduction](#introduction)
- [Prerequisites](#prerequisites)
- [Build Environment Setup](#build-environment-setup)
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

## Building the RT Kernel

### Using the Amazon Linux Source RPM (Recommended for EC2)

This approach is recommended for EC2 instances as it ensures all Amazon-specific drivers and configurations are properly included.

#### 1. Run the Build Script

```bash
./build-rt-kernel-from-srpm.sh
```

This script will:
1. Enable the Amazon Linux source repository
2. Download the kernel6.12 source RPM
3. Modify the spec file and config files to enable PREEMPT_RT
4. Build the kernel with RT support
5. Create RPM packages in `~/rt-kernel-rpms/`

The advantage of this approach is that it uses Amazon's official kernel source that already has all their patches and configurations, including proper support for the ENA driver and other EC2-specific features.

## Installing the RT Kernel

The build script automatically handles the installation process:

1. Transfers the RPM packages to the remote host
2. Installs the packages on the remote host
3. Updates the GRUB configuration
4. Sets the new kernel as default
5. Prompts to reboot the remote host

If you need to manually install the kernel, you can use these commands:

```bash
# Transfer packages
cd ~/rt-kernel-build
scp -i /path/to/your/ssh/key.pem kernel-rpms/kernel-*.rpm ec2-user@your-remote-host:~/

# Install packages on the remote host
ssh -i /path/to/your/ssh/key.pem ec2-user@your-remote-host
sudo dnf install -y ~/kernel-*.rpm
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

### Automated Verification

We provide a verification script to check if the RT kernel is properly installed and configured:

```bash
# For kernels built from Amazon Linux source RPM
sudo ./verify-rt-srpm-kernel.sh
```

This script will:
1. Check if the running kernel has RT capabilities
2. Verify that critical RT configurations are enabled
3. Check for AWS-specific drivers (ENA, NVMe)
4. Run latency tests if rt-tests package is installed
5. Provide a summary of the kernel configuration

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
