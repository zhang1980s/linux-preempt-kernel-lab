# RT Kernel Build for Amazon Linux 2023 - Summary

This repository contains scripts and documentation for building and installing a Linux kernel with PREEMPT_RT support on Amazon Linux 2023.

## Overview

The project provides a complete solution for building a real-time kernel on Amazon Linux 2023 and installing it on a remote EC2 instance. The real-time capabilities are achieved by enabling the PREEMPT_RT option in the Linux kernel configuration.

## Files in this Repository

1. **README.md** - Comprehensive documentation with step-by-step instructions for building and installing the RT kernel.

2. **build-rt-kernel.sh** - Automated script that handles the entire kernel build process:
   - Downloads the Linux kernel source (version 6.12.32)
   - Configures the kernel with PREEMPT_RT support
   - Builds the kernel and creates binary RPM packages (no git repository required)
   - Automatically transfers and installs the packages on a remote EC2 instance

3. **verify-rt-kernel.sh** - Script to verify the RT kernel installation and test real-time capabilities:
   - Checks if the running kernel has RT capabilities
   - Runs latency tests to measure real-time performance
   - Provides recommendations for optimizing RT performance

## Key Features

- Uses Linux kernel version 6.12.32, which natively supports the PREEMPT_RT option
- Configures timer frequency to 1000 Hz for better real-time performance
- Includes AWS-specific configurations for EC2 compatibility (ENA networking, NVMe storage, KVM guest support)
- Automatically detects and utilizes available CPU cores on both local and remote systems for optimal compilation performance
- Builds RPM packages for easy installation on Amazon Linux 2023
- Includes comprehensive testing and verification tools
- Provides performance tuning recommendations

## Quick Start

1. **Build the RT kernel**:
   ```bash
   ./build-rt-kernel.sh
   ```
   
   This script will build the kernel, create RPM packages, and automatically transfer and install them on your remote EC2 instance.

2. **After installation and reboot, verify the RT kernel**:
   ```bash
   # On the remote EC2 instance
   sudo ./verify-rt-kernel.sh
   ```

   This will confirm that the RT kernel is running correctly and perform basic latency tests.

## Remote EC2 Instance

The scripts are configured to work with a remote EC2 instance. You can modify the following variables in `build-rt-kernel.sh` to match your environment:

```bash
REMOTE_HOST="your-remote-host"
SSH_KEY="/path/to/your/ssh/key.pem"
REMOTE_USER="ec2-user"
```

## Performance Considerations

For optimal real-time performance, consider the following:

1. Isolate CPUs for real-time tasks
2. Set appropriate CPU affinity for critical processes
3. Use real-time priorities for time-sensitive applications
4. Disable unnecessary services
5. Configure kernel parameters for low latency

### Testing Real-Time Performance

The `verify-rt-kernel.sh` script includes checks for the RT kernel and can run latency tests if the `rt-tests` package is available. Since this package may not be available in the default Amazon Linux 2023 repositories, the script provides instructions for building it from source if needed.

Refer to the README.md and verify-rt-kernel.sh for more detailed performance tuning recommendations.
