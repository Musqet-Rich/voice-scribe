#!/bin/bash
# Create a local self-signed code-signing identity so macOS keeps Voice Scribe's
# Accessibility permission across rebuilds. One-off per machine. Asks for your password.
set -e
NAME="Voice Scribe Local Signing"
if security find-identity -v -p codesigning | grep -q "$NAME"; then
    echo "'$NAME' already exists and is trusted."
    exit 0
fi

DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT
cat > "$DIR/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF

openssl req -x509 -newkey rsa:2048 -nodes -keyout "$DIR/key.pem" -out "$DIR/cert.pem" \
    -days 3650 -config "$DIR/cert.cnf" 2>/dev/null
PASS=$(openssl rand -hex 12)
openssl pkcs12 -export -legacy -inkey "$DIR/key.pem" -in "$DIR/cert.pem" -name "$NAME" \
    -out "$DIR/id.p12" -passout "pass:$PASS" 2>/dev/null \
  || openssl pkcs12 -export -inkey "$DIR/key.pem" -in "$DIR/cert.pem" -name "$NAME" \
    -out "$DIR/id.p12" -passout "pass:$PASS"

security import "$DIR/id.p12" -k ~/Library/Keychains/login.keychain-db -P "$PASS" -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign -k ~/Library/Keychains/login.keychain-db "$DIR/cert.pem"
echo "Done. The first ./run.sh may ask to allow codesign to use the key: choose Always Allow."
