#!/bin/bash
# Creates a self-signed "Nastro Dev" code-signing certificate in the login keychain,
# so Screen Recording permission survives rebuilds. Idempotent.
set -euo pipefail

NAME="Nastro Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning 2>/dev/null | grep -q "$NAME"; then
    echo "Certificate '$NAME' already present, nothing to do."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS="nastro-dev-$$"

cat > "$TMP/openssl.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/openssl.cnf"
# -legacy keeps the PKCS#12 readable by macOS `security` with OpenSSL 3.
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/nastro.p12" -passout "pass:$PASS" 2>/dev/null \
  || openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/nastro.p12" -passout "pass:$PASS"

security import "$TMP/nastro.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign
echo "Imported '$NAME' into the login keychain."
echo "If codesign cannot use it, open Keychain Access, trust the certificate for Code Signing."
