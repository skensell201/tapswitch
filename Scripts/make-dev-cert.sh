#!/usr/bin/env bash
# Creates a self-signed code signing identity so rebuilt bundles keep a stable
# designated requirement. Without it every rebuild is ad-hoc signed with a new
# code hash, and macOS forgets the Login Items registration.
#
# macOS will ask for your login password once when the certificate is trusted.
set -euo pipefail

NAME="TapSwitch Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
# `security import` refuses an empty-password PKCS#12 ("MAC verification
# failed"), so the transit file gets a throwaway password. It never leaves the
# temporary directory below.
PASSWORD="tapswitch"

if security find-identity -v -p codesigning | grep -q "$NAME"; then
    echo "Identity '$NAME' already exists."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/openssl.cnf" <<'CNF'
[ req ]
distinguished_name = dn
x509_extensions = v3
prompt = no

[ dn ]
CN = TapSwitch Dev

[ v3 ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/openssl.cnf"

# OpenSSL 3 writes PKCS#12 with AES/PBKDF2 by default and `security import`
# rejects it; -legacy writes the RC2/3DES form the keychain accepts. LibreSSL
# (/usr/bin/openssl) has no such flag and already writes the legacy form.
LEGACY=""
if openssl pkcs12 -help 2>&1 | grep -q -- '-legacy'; then
    LEGACY="-legacy"
fi

openssl pkcs12 -export ${LEGACY:+$LEGACY} -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$NAME" -out "$TMP/identity.p12" -passout "pass:$PASSWORD"

security import "$TMP/identity.p12" -k "$KEYCHAIN" -T /usr/bin/codesign -P "$PASSWORD"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"

# The `-T /usr/bin/codesign` ACL entry above is not enough on modern macOS: the
# imported key's partition list stays empty, and `codesign` throws up a GUI
# "wants to sign using key in your keychain" prompt on every invocation. Setting
# the partition list requires unlocking the keychain with its own password.
echo "Enter your login keychain password to let codesign use this key without prompting each build:"
read -rs LOGIN_PASSWORD
echo
if security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$LOGIN_PASSWORD" "$KEYCHAIN" >/dev/null; then
    echo "Partition list set — codesign will not prompt on future builds."
else
    echo "warning: could not set the key's partition list; codesign may prompt on each build." >&2
    echo "warning: fix it in Keychain Access by setting the key to \"Allow all applications to access this item\"." >&2
fi
unset LOGIN_PASSWORD

echo "Created identity '$NAME':"
security find-identity -v -p codesigning
