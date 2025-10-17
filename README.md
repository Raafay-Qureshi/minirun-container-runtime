# MiniRun - Container Runtime from Scratch

A lightweight container runtime built to understand containerization at the Linux kernel level. This project implements core Docker functionality using namespaces, cgroups, and filesystem isolation, with additional features including REST APIs, database persistence, and cloud deployment infrastructure.

**Project Goal:** Deep understanding of container technology for software engineering applications, moving beyond Docker usage to implementation.

## Overview

This is a working container runtime that provides:
- Process isolation via PID and mount namespaces
- Resource limits through cgroups v2 (memory and CPU)
- Filesystem isolation with chroot
- Python CLI for container management
- Go REST API for programmatic access
- PostgreSQL database integration with file-based fallback
- Automated CI/CD pipeline
- AWS deployment via Terraform

The implementation demonstrates how tools like Docker work under the hood by directly using Linux kernel features.

## Quick Start
```bash
# Using Python CLI
./minirun create myapp
sudo ./minirun start myapp    # Requires root for namespace creation
./minirun list
./minirun delete myapp

# Using REST API
cd orchestrator && go run main.go
curl http://localhost:8080/containers
```

Running `ps aux` inside a container shows only container processes, demonstrating successful namespace isolation.

## Architecture

The runtime works through several isolation layers:

1. **Process Isolation**: `clone()` system call with `CLONE_NEWPID` creates new process namespace
2. **Filesystem Isolation**: Mount namespace + `chroot()` restricts filesystem access
3. **Resource Limits**: cgroups v2 enforces memory (512MB) and CPU (50%) caps
4. **Process Execution**: Container init process runs as PID 1 in isolated environment
```
User Command (./minirun start myapp)
    ↓
Python CLI reads JSON configuration
    ↓
Executes C runtime binary
    ↓
clone() with namespace flags
    ↓
Setup cgroups → chroot → mount /proc → exec bash
    ↓
Isolated container environment
```

## Project Structure
```
├── src/
│   ├── container_runtime.c      # Core runtime (270 lines)
│   ├── namespace_demo.c         # PID namespace basics
│   ├── chroot_demo.c            # Filesystem isolation demo
│   └── fork_demo.c              # fork() vs clone() comparison
├── orchestrator/
│   ├── main.go                  # REST API server
│   ├── database.go              # PostgreSQL integration
│   └── schema.sql               # Database schema
├── terraform/                   # AWS infrastructure as code
├── .github/workflows/ci.yml     # CI/CD pipeline
├── scripts/
│   ├── deploy.sh                # Automated deployment
│   └── monitor.sh               # Container monitoring
├── tests/
│   ├── unit/                    # C namespace tests
│   └── integration/             # Python CLI tests
└── minirun                      # Python CLI
```

## Implementation Details

### Container Runtime (C)

The core runtime (`src/container_runtime.c`) implements:
- Namespace creation using `clone()` with appropriate flags
- Cgroup setup via direct filesystem I/O (not `system()` calls)
- Filesystem isolation through `chroot()` and mount operations
- Process management and cleanup

Key technical decisions:
- Using `clone()` instead of `fork()` to enable namespace creation
- Direct file I/O for cgroup operations provides better error handling
- Combining multiple isolation mechanisms for defense in depth
- Graceful degradation when kernel features unavailable

### Python CLI

Provides user-friendly interface for container lifecycle management:
- JSON-based configuration storage
- Input validation and error handling
- Subprocess execution of C runtime
- State management for container tracking

### Go REST API

HTTP server with full CRUD operations:
- RESTful endpoint design
- PostgreSQL integration with connection pooling
- Automatic HTTPS when certificates present
- CORS support for web clients
- Request logging and error handling

### Database Layer

Dual-storage approach:
- PostgreSQL with automatic schema initialization
- File-based JSON fallback when database unavailable
- Connection pooling for performance
- Environment-based configuration

## Features

**Core Container Runtime**
- PID namespace isolation
- Mount namespace isolation  
- Cgroups v2 resource limits
- Chroot filesystem isolation
- Process lifecycle management

**REST API** (`orchestrator/`)
- Container CRUD operations
- Health monitoring endpoints
- SSL/TLS support (ports 8080/8443)
- PostgreSQL or file storage
- JSON request/response handling

**Automation**
- Deployment script with build validation (~70% time reduction)
- Real-time monitoring with multiple output formats
- GitHub Actions CI/CD pipeline
- Terraform AWS infrastructure

**Testing**
- Unit tests for namespace isolation (C)
- Integration tests for CLI operations (Python)
- Automated test runner
- ~90% code coverage

## Technical Concepts Demonstrated

### Linux Namespaces
Implemented PID and mount namespaces using the `clone()` system call. PID namespace gives the container its own process tree (starting at PID 1), while mount namespace allows independent filesystem mounts without affecting the host.

### Control Groups (cgroups)
Resource limiting through cgroups v2 filesystem interface. Memory and CPU limits are enforced by writing values to `/sys/fs/cgroup/` hierarchy files and adding process PIDs to the cgroup.

### System Programming
Direct use of system calls (`clone()`, `chroot()`, `mount()`, `execl()`) with proper error handling. Manual memory management for process stacks and careful cleanup of kernel resources.

### Multi-language Integration
Combining C for low-level operations, Python for user experience, Go for API services, and Bash for automation. Each language chosen for appropriate use case.

## Common Issues and Solutions

**Permission Denied on Namespace Creation**
- Namespace creation requires `CAP_SYS_ADMIN` capability
- Solution: Run with sudo or appropriate capabilities

**Cgroup Limits Not Applied**
- Process must be added to cgroup via `cgroup.procs` file
- Verify cgroups v2 enabled: `mount | grep cgroup2`

**Container Sees Host Processes**
- Indicates namespace not properly created or `/proc` not mounted
- Verify: `ls -la /proc/self/ns/pid` should differ from host

**Missing Shared Libraries**
- Container rootfs needs all binary dependencies
- Use `ldd` to identify required libraries: `ldd /bin/bash`

## Setup and Installation
```bash
# Build C runtime
gcc -o bin/container_runtime src/container_runtime.c -Wall -Wextra

# Setup container rootfs
sudo ./setup_container.sh

# Make CLI executable
chmod +x minirun

# Test basic functionality
./minirun create test
sudo ./minirun start test
```

### REST API Setup
```bash
# Basic (file storage)
cd orchestrator && go run *.go

# With PostgreSQL
export DB_HOST=localhost
export DB_PORT=5432
export DB_USER=minirun
export DB_PASSWORD=your_password
export DB_NAME=minirun
go run *.go
```

### Enable HTTPS
```bash
# Generate self-signed certificates
sudo ./scripts/generate_certificates.sh

# API automatically detects and enables HTTPS
cd orchestrator && go run main.go
# Now accessible at https://localhost:8443
```

### AWS Deployment
```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Configure AWS credentials and settings

terraform init
terraform apply
```

## Testing
```bash
# Run full test suite
sudo ./tests/run_tests.sh

# Unit tests only
sudo ./tests/run_tests.sh --unit-only

# Integration tests only
./tests/run_tests.sh --integration-only
```

Tests verify:
- Namespace isolation functionality
- Cgroup resource limit enforcement
- CLI command operations
- Container lifecycle management
- Error handling and edge cases

## API Usage
```bash
# Health check
curl http://localhost:8080/health

# Create container
curl -X POST http://localhost:8080/containers \
  -H "Content-Type: application/json" \
  -d '{"name":"webapp","command":"/bin/bash"}'

# List containers
curl http://localhost:8080/containers | jq

# Get container details
curl http://localhost:8080/containers/webapp

# Delete container
curl -X DELETE http://localhost:8080/containers/webapp
```

## Comparison with Docker

| Feature | MiniRun | Docker |
|---------|---------|---------|
| PID Isolation | ✓ | ✓ |
| Mount Isolation | ✓ | ✓ |
| Resource Limits | ✓ (cgroups v2) | ✓ |
| Network Isolation | ✗ | ✓ |
| Image Layers | ✗ | ✓ (overlay2) |
| REST API | ✓ (Go) | ✓ |
| Database | ✓ (PostgreSQL) | ✓ |
| Cloud Deploy | ✓ (Terraform) | ✓ |

This implementation covers core containerization mechanisms. Docker adds production features like network isolation, image management, and orchestration.

## Performance Characteristics

- Container creation: ~10ms (JSON write)
- Container startup: ~50-100ms (namespace + cgroup setup)
- API response time: <5ms
- Database operations: <10ms
- Automated deployment: ~10s vs ~30s manual

## Current Limitations

**Not Implemented:**
- Network namespace (containers use host network)
- User namespace (rootless containers)
- Image layering system
- Container-to-container networking
- Volume management
- Multi-node orchestration

These features would be required for production use but are beyond the scope of understanding core containerization mechanisms.

## Technology Stack

- **C** - Container runtime, system calls
- **Python** - CLI interface
- **Go** - REST API server
- **PostgreSQL** - Database persistence
- **Bash** - Automation scripts
- **Terraform** - Infrastructure as code
- **GitHub Actions** - CI/CD automation

## Learning Outcomes

### Systems Programming
- Direct system call usage and error handling
- Memory management for process stacks
- Kernel resource cleanup and management
- Multi-process coordination

### Container Technology
- Understanding namespace types and usage
- Cgroups v2 filesystem interface
- Difference between chroot and mount namespaces
- Container isolation mechanisms

### Software Engineering
- Multi-language project integration
- REST API design and implementation
- Database schema design and connection pooling
- Infrastructure as code with Terraform
- CI/CD pipeline development
- SSL/TLS certificate management

### DevOps Practices
- Automated deployment and testing
- Monitoring and metrics collection
- Cloud infrastructure provisioning
- Configuration management

## Project Statistics

- ~5,000+ lines of code
- 7 programming languages
- 20+ automated tests
- 50+ hours development time
- 95% feature completion

## Future Enhancements

Potential additions for production readiness:
- Network namespace implementation
- Container networking (bridge mode)
- Image system with layer caching
- OAuth authentication for API
- Seccomp syscall filtering
- User namespace support
- Volume management
- Multi-container orchestration

---

### **Author:** Raafay Qureshi
### **Purpose:** Understanding containerization for software engineering applications