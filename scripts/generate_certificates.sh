#!/bin/bash
# SSL/TLS Certificate Generator for MiniRun (self-signed for development)
set -e  # Exit on any error

echo "╔════════════════════════════════════════════════╗"
echo "║   MiniRun SSL/TLS Certificate Generator       ║"
echo "╚════════════════════════════════════════════════╝"
echo ""

# Default certificate paths (system-wide)
CERT_DIR="/etc/minirun"
CERT_FILE="$CERT_DIR/cert.pem"
KEY_FILE="$CERT_DIR/key.pem"

# Fallback to local directory if /etc/minirun not writable
if [ ! -w "$(dirname $CERT_DIR)" ] 2>/dev/null; then
    echo "⚠️  /etc/minirun is not writable, using local directory"
    CERT_DIR="./certs"
    CERT_FILE="$CERT_DIR/cert.pem"
    KEY_FILE="$CERT_DIR/key.pem"
fi

mkdir -p "$CERT_DIR"
echo "Certificate directory: $CERT_DIR"

# Check for existing certificates and prompt for overwrite
if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ]; then
    echo ""
    echo "⚠️  Certificates already exist:"
    echo "   Certificate: $CERT_FILE"
    echo "   Private Key: $KEY_FILE"
    echo ""
    read -p "Do you want to overwrite them? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted. Existing certificates retained."
        exit 0
    fi
fi

echo ""
echo "Generating self-signed SSL/TLS certificates..."
echo ""

# Generate 4096-bit RSA certificate valid for 365 days
openssl req -x509 \
    -newkey rsa:4096 \
    -keyout "$KEY_FILE" \
    -out "$CERT_FILE" \
    -days 365 \
    -nodes \
    -subj "/C=US/ST=State/L=City/O=MiniRun/OU=Development/CN=localhost" \
    -addext "subjectAltName=DNS:localhost,DNS:*.localhost,IP:127.0.0.1"

# Secure permissions: private key read-only by owner, cert readable by all
chmod 600 "$KEY_FILE"
chmod 644 "$CERT_FILE"

echo ""
echo "✅ Certificates generated successfully!"
echo ""
echo "📁 Certificate Files:"
echo "   Certificate: $CERT_FILE"
echo "   Private Key: $KEY_FILE"
echo ""
echo "🔒 Certificate Details:"
openssl x509 -in "$CERT_FILE" -noout -subject -dates
echo ""

# Show how to use the generated certificates
echo "📋 Usage Instructions:"
echo ""
echo "1. Start the API server:"
if [ "$CERT_DIR" = "./certs" ]; then
    echo "   export TLS_CERT_PATH=$CERT_FILE"
    echo "   export TLS_KEY_PATH=$KEY_FILE"
    echo "   cd orchestrator && go run main.go"
else
    echo "   cd orchestrator && go run main.go"  # Auto-detects /etc/minirun certs
fi
echo ""
echo "2. Test HTTPS endpoint (curl -k skips cert verification for self-signed):"
echo "   curl -k https://localhost:8443/health"
echo ""
echo "3. For production, replace with CA-signed certificates (Let's Encrypt, etc.)"
echo ""

# If systemd service detected, show restart command
if [ "$CERT_DIR" = "/etc/minirun" ] && [ -f "/etc/systemd/system/minirun-api.service" ]; then
    echo "📝 Note: Detected systemd service"
    echo "   Restart to enable HTTPS: sudo systemctl restart minirun-api"
    echo ""
fi

echo "⚠️  Security Warning: Self-signed certificates for development only!"
echo "   Production systems need CA-signed certificates for trusted HTTPS."
echo ""