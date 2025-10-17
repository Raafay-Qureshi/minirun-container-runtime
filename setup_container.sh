#!/bin/bash

# Create directory structure
mkdir -p myroot/{bin,lib,lib64,lib/x86_64-linux-gnu,usr/bin,proc,tmp}

echo "Copying binaries..."
# Copy binaries
sudo cp /bin/bash myroot/bin/
sudo cp /bin/ls myroot/bin/
sudo cp /bin/ps myroot/bin/
sudo cp /bin/cat myroot/bin/
sudo cp /bin/pwd myroot/bin/
sudo cp /bin/echo myroot/bin/

echo "Copying libraries for bash..."
for lib in $(ldd /bin/bash | grep -o '/lib[^ ]*'); do
    sudo cp --parents "$lib" myroot/ 2>/dev/null
done

echo "Copying libraries for ls..."
for lib in $(ldd /bin/ls | grep -o '/lib[^ ]*'); do
    sudo cp --parents "$lib" myroot/ 2>/dev/null
done

echo "Copying libraries for ps..."
for lib in $(ldd /bin/ps | grep -o '/lib[^ ]*'); do
    sudo cp --parents "$lib" myroot/ 2>/dev/null
done

echo "Done! Your container filesystem is ready."
ls -la myroot/