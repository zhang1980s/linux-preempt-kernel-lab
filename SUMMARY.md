# RT Kernel Build for Amazon Linux 2023 - Summary

This repository contains scripts and documentation for building and installing a Linux kernel with PREEMPT_RT support on Amazon Linux 2023.

## Building RT Kernel from Amazon Linux Source RPM

The recommended approach for EC2 instances:
- Uses official Amazon Linux kernel source RPM
- Preserves all Amazon-specific patches and drivers
- Ensures proper ENA driver support for EC2 networking

## Overview

The project provides a complete solution for building a real-time kernel on Amazon Linux 2023 and installing it on a remote EC2 instance. The real-time capabilities are achieved by enabling the PREEMPT_RT option in the Linux kernel configuration.

## Files in this Repository

1. **README.md** - Comprehensive documentation with step-by-step instructions for building and installing the RT kernel.

2. **build-rt-kernel-from-srpm.sh** - Script for building RT kernel from Amazon Linux source RPM:
   - Enables the Amazon Linux source repository
   - Downloads and modifies the kernel6.12 source RPM
   - Enables PREEMPT_RT and other RT-specific configurations
   - Preserves all Amazon-specific drivers and configurations
   - Creates RPM packages ready for installation

3. **verify-rt-srpm-kernel.sh** - Script to verify the RT kernel built from Amazon Linux source RPM:
   - Checks if the running kernel has RT capabilities
   - Runs latency tests to measure real-time performance
   - Provides recommendations for optimizing RT performance
   - Includes additional checks for Amazon-specific drivers

## Key Features

- Uses Linux kernel version 6.12.32, which natively supports the PREEMPT_RT option
- Configures timer frequency to 1000 Hz for better real-time performance
- Customizes kernel name with RT suffix for easy identification
- Optimizes RCU subsystem for real-time performance (priority boosting, callback offloading)
- Includes AWS-specific configurations for EC2 compatibility (ENA networking, NVMe storage, KVM guest support)
- Builds RPM packages for easy installation on Amazon Linux 2023
- Includes comprehensive testing and verification tools
- Provides performance tuning recommendations

## Quick Start

### Building from Amazon Linux Source RPM

1. **Build the RT kernel from Amazon Linux source RPM**:
   ```bash
   ./build-rt-kernel-from-srpm.sh
   ```
   
   This script will build the kernel with RT support while preserving all Amazon-specific drivers.

2. **After installation and reboot, verify the RT kernel**:
   ```bash
   # On the EC2 instance
   sudo ./verify-rt-srpm-kernel.sh
   ```

   This will confirm that the RT kernel is running correctly and perform basic latency tests.

## Performance Considerations

For optimal real-time performance, consider the following:

1. Isolate CPUs for real-time tasks
2. Set appropriate CPU affinity for critical processes
3. Use real-time priorities for time-sensitive applications
4. Disable unnecessary services
5. Configure kernel parameters for low latency

### Testing Real-Time Performance

The `verify-rt-srpm-kernel.sh` script includes checks for the RT kernel and can run latency tests if the `rt-tests` package is available. Since this package may not be available in the default Amazon Linux 2023 repositories, the script provides instructions for building it from source if needed.
