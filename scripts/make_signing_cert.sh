#!/usr/bin/env bash
#
# Create a self-signed code-signing identity in the login keychain so the app's
# code signature (and therefore its TCC permission grants) stay STABLE across
# rebuilds. Run once. After this, make_app.sh signs with it automatically and
# you only ever grant Input Monitoring / Accessibility one more time.
#
set -euo pipefail

IDENTITY_CN="G13ManagerSelfSigned"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY_CN"; then
    echo "Signing identity '$IDENTITY_CN' already exists — nothing to do."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<'EOF'
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = G13ManagerSelfSigned
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

echo "==> Generating self-signed code-signing certificate (valid 10 years)…"
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cnf" >/dev/null 2>&1

# -legacy: OpenSSL 3.x otherwise produces a PKCS12 MAC/cipher that Apple's
# Security framework can't import ("MAC verification failed").
openssl pkcs12 -export -legacy -macalg sha1 -out "$TMP/identity.p12" \
    -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$IDENTITY_CN" -passout pass:g13 >/dev/null 2>&1

echo "==> Importing into login keychain (granting codesign access without prompts)…"
security import "$TMP/identity.p12" -k "$KEYCHAIN" -P g13 -A -T /usr/bin/codesign

# Best-effort: add codesign to the key's partition list so it never prompts.
# Needs the login password; ignore failure (the -A above usually suffices).
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" "$KEYCHAIN" >/dev/null 2>&1 || true

echo "==> Verifying identity is usable for code signing…"
if security find-identity -p codesigning | grep "$IDENTITY_CN"; then
    echo "Done. '$IDENTITY_CN' is ready. Now run: scripts/make_app.sh release"
else
    echo "ERROR: identity not found after import." >&2
    exit 1
fi
