#!/usr/bin/env python3
"""
Integration tests for MiniRun CLI

Tests the Python CLI interface to ensure:
1. Container creation works
2. Container listing works
3. Container deletion works
4. Error handling is correct
"""

import sys
import os
import json
import subprocess
import tempfile
import shutil
from pathlib import Path

# Add project root to path
PROJECT_ROOT = Path(__file__).parent.parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

# Colors for output
GREEN = '\033[0;32m'
RED = '\033[0;31m'
YELLOW = '\033[1;33m'
BLUE = '\033[0;34m'
NC = '\033[0m'

# Test statistics
tests_passed = 0
tests_failed = 0
failed_tests = []

def print_success(message):
    """Print success message"""
    global tests_passed
    tests_passed += 1
    print(f"{GREEN}✓ PASS: {message}{NC}")

def print_error(message):
    """Print error message"""
    global tests_failed
    tests_failed += 1
    failed_tests.append(message)
    print(f"{RED}✗ FAIL: {message}{NC}")

def print_info(message):
    """Print info message"""
    print(f"{BLUE}ℹ INFO: {message}{NC}")

def run_command(cmd, check=True):
    """Run a command and return output"""
    try:
        result = subprocess.run(
            cmd,
            shell=True,
            capture_output=True,
            text=True,
            check=check
        )
        return result.returncode, result.stdout, result.stderr
    except subprocess.CalledProcessError as e:
        return e.returncode, e.stdout, e.stderr

def test_cli_exists():
    """Test 1: Verify CLI script exists and is executable"""
    print("\n[Test 1: CLI Exists]")
    
    cli_path = PROJECT_ROOT / "minirun"
    
    if cli_path.exists():
        print_success("minirun CLI file exists")
    else:
        print_error("minirun CLI file not found")
        return False
    
    if os.access(cli_path, os.X_OK):
        print_success("minirun CLI is executable")
    else:
        print_error("minirun CLI is not executable")
        return False
    
    return True

def test_cli_help():
    """Test 2: Verify help command works"""
    print("\n[Test 2: Help Command]")
    
    returncode, stdout, stderr = run_command(f"{PROJECT_ROOT}/minirun --help", check=False)
    
    if returncode == 0:
        print_success("Help command executed successfully")
    else:
        print_error(f"Help command failed with code {returncode}")
        return False
    
    if "usage" in stdout.lower() or "minirun" in stdout.lower():
        print_success("Help output contains usage information")
    else:
        print_error("Help output missing usage information")
        return False
    
    return True

def test_container_create():
    """Test 3: Test container creation"""
    print("\n[Test 3: Container Creation]")
    
    test_name = f"test-create-{os.getpid()}"
    
    # Create container
    returncode, stdout, stderr = run_command(
        f"{PROJECT_ROOT}/minirun create {test_name}",
        check=False
    )
    
    if returncode == 0:
        print_success(f"Container '{test_name}' created successfully")
    else:
        print_error(f"Container creation failed: {stderr}")
        return False
    
    # Verify container config file exists
    config_file = PROJECT_ROOT / "containers" / f"{test_name}.json"
    if config_file.exists():
        print_success("Container config file created")
    else:
        print_error("Container config file not found")
        return False
    
    # Verify config file is valid JSON
    try:
        with open(config_file, 'r') as f:
            config = json.load(f)
        print_success("Container config is valid JSON")
        
        # Check required fields
        if config.get('name') == test_name:
            print_success("Container config has correct name")
        else:
            print_error("Container config has incorrect name")
        
        if 'rootfs' in config and 'command' in config:
            print_success("Container config has required fields")
        else:
            print_error("Container config missing required fields")
    except json.JSONDecodeError:
        print_error("Container config is not valid JSON")
        return False
    
    # Cleanup
    run_command(f"{PROJECT_ROOT}/minirun delete {test_name}", check=False)
    
    return True

def test_container_list():
    """Test 4: Test container listing"""
    print("\n[Test 4: Container Listing]")
    
    # Create test containers
    test_name1 = f"test-list-1-{os.getpid()}"
    test_name2 = f"test-list-2-{os.getpid()}"
    
    run_command(f"{PROJECT_ROOT}/minirun create {test_name1}", check=False)
    run_command(f"{PROJECT_ROOT}/minirun create {test_name2}", check=False)
    
    # List containers
    returncode, stdout, stderr = run_command(
        f"{PROJECT_ROOT}/minirun list",
        check=False
    )
    
    if returncode == 0:
        print_success("List command executed successfully")
    else:
        print_error(f"List command failed: {stderr}")
        return False
    
    if test_name1 in stdout and test_name2 in stdout:
        print_success("List command shows created containers")
    else:
        print_error("List command doesn't show all containers")
    
    # Cleanup
    run_command(f"{PROJECT_ROOT}/minirun delete {test_name1}", check=False)
    run_command(f"{PROJECT_ROOT}/minirun delete {test_name2}", check=False)
    
    return True

def test_container_info():
    """Test 5: Test container info"""
    print("\n[Test 5: Container Info]")
    
    test_name = f"test-info-{os.getpid()}"
    
    # Create container
    run_command(f"{PROJECT_ROOT}/minirun create {test_name}", check=False)
    
    # Get info
    returncode, stdout, stderr = run_command(
        f"{PROJECT_ROOT}/minirun info {test_name}",
        check=False
    )
    
    if returncode == 0:
        print_success("Info command executed successfully")
    else:
        print_error(f"Info command failed: {stderr}")
        run_command(f"{PROJECT_ROOT}/minirun delete {test_name}", check=False)
        return False
    
    if test_name in stdout:
        print_success("Info output contains container name")
    else:
        print_error("Info output missing container name")
    
    # Cleanup
    run_command(f"{PROJECT_ROOT}/minirun delete {test_name}", check=False)
    
    return True

def test_container_delete():
    """Test 6: Test container deletion"""
    print("\n[Test 6: Container Deletion]")
    
    test_name = f"test-delete-{os.getpid()}"
    
    # Create container
    run_command(f"{PROJECT_ROOT}/minirun create {test_name}", check=False)
    
    # Verify it exists
    config_file = PROJECT_ROOT / "containers" / f"{test_name}.json"
    if not config_file.exists():
        print_error("Container was not created properly")
        return False
    
    # Delete container
    returncode, stdout, stderr = run_command(
        f"{PROJECT_ROOT}/minirun delete {test_name}",
        check=False
    )
    
    if returncode == 0:
        print_success("Delete command executed successfully")
    else:
        print_error(f"Delete command failed: {stderr}")
        return False
    
    # Verify it's gone
    if not config_file.exists():
        print_success("Container config file removed")
    else:
        print_error("Container config file still exists")
        return False
    
    return True

def test_error_handling():
    """Test 7: Test error handling for invalid operations"""
    print("\n[Test 7: Error Handling]")
    
    # Try to start non-existent container
    returncode, stdout, stderr = run_command(
        f"{PROJECT_ROOT}/minirun start nonexistent-{os.getpid()}",
        check=False
    )
    
    if returncode != 0:
        print_success("Non-existent container start properly fails")
    else:
        print_error("Non-existent container start should fail")
    
    # Try to delete non-existent container
    returncode, stdout, stderr = run_command(
        f"{PROJECT_ROOT}/minirun delete nonexistent-{os.getpid()}",
        check=False
    )
    
    if returncode != 0:
        print_success("Non-existent container delete properly fails")
    else:
        print_error("Non-existent container delete should fail")
    
    # Try to create duplicate container
    test_name = f"test-duplicate-{os.getpid()}"
    run_command(f"{PROJECT_ROOT}/minirun create {test_name}", check=False)
    
    returncode, stdout, stderr = run_command(
        f"{PROJECT_ROOT}/minirun create {test_name}",
        check=False
    )
    
    if returncode != 0:
        print_success("Duplicate container creation properly fails")
    else:
        print_error("Duplicate container creation should fail")
    
    # Cleanup
    run_command(f"{PROJECT_ROOT}/minirun delete {test_name}", check=False)
    
    return True

def main():
    """Run all integration tests"""
    print("╔════════════════════════════════════════════════╗")
    print("║   MiniRun CLI Integration Tests               ║")
    print("╚════════════════════════════════════════════════╝")
    
    # Run tests
    test_cli_exists()
    test_cli_help()
    test_container_create()
    test_container_list()
    test_container_info()
    test_container_delete()
    test_error_handling()
    
    # Summary
    print("\n════════════════════════════════════════════════")
    print("Test Results:")
    print(f"  Passed: {tests_passed}")
    print(f"  Failed: {tests_failed}")
    print("════════════════════════════════════════════════")
    
    if tests_failed > 0:
        print("\n❌ Some tests failed:")
        for test in failed_tests:
            print(f"  - {test}")
        return 1
    else:
        print("\n✅ All integration tests passed!")
        return 0

if __name__ == "__main__":
    sys.exit(main())