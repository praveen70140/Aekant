#!/bin/bash
# push-to-ppa.sh - Prepares and uploads source package to Launchpad

set -e

VERSION=$1
LP_USER=$2
PPA_NAME=$3
GPG_KEY_ID=$4
GPG_PASSPHRASE=$5

if [ -z "$VERSION" ] || [ -z "$LP_USER" ] || [ -z "$PPA_NAME" ]; then
    echo "Usage: $0 <version> <lp_user> <ppa_name> [gpg_key_id] [gpg_passphrase]"
    exit 1
fi

# Distributions to target
DISTS=("jammy" "noble" "focal")

# Create dput config
cat <<EOF > ~/.dput.cf
[aekant-ppa]
fqdn = ppa.launchpad.net
method = ftp
incoming = ~${LP_USER}/ubuntu/${PPA_NAME}/
login = anonymous
allow_unsigned_uploads = 0
EOF

DATE=$(date -R)

for DIST in "${DISTS[@]}"; do
    echo "Preparing upload for $DIST..."
    
    # Version for PPA must be unique per distribution
    PPA_VERSION="${VERSION}-0ppa1~ubuntu${DIST}"
    
    # Clean up any previous builds
    rm -rf build-source
    mkdir -p build-source
    
    # Copy source files (excluding current build artifacts)
    cp -r . build-source/
    cd build-source
    
    # Move debian folder to root of source
    cp -r apt/debian .
    
    # Update changelog
    sed -i "s/#VERSION#/$PPA_VERSION/g" debian/changelog
    sed -i "s/#DIST#/$DIST/g" debian/changelog
    sed -i "s/#DATE#/$DATE/g" debian/changelog
    
    # Create source package
    # -us -uc means unsigned for now, we will sign with debsign
    # -S means source package only
    # -d means skip build dependencies check (useful in CI)
    dpkg-buildpackage -S -d -us -uc
    
    cd ..
    
    # Sign the changes and dsc files
    CHANGES_FILE="aekant-browser_${PPA_VERSION}_source.changes"
    if [ -n "$GPG_KEY_ID" ]; then
        echo "Signing $CHANGES_FILE..."
        
        # Configure debsign to use gpg with passphrase
        if [ -n "$GPG_PASSPHRASE" ]; then
            export DEBSIGN_PROGRAM="gpg --batch --passphrase $GPG_PASSPHRASE --pinentry-mode loopback"
        fi
        
        debsign -k "$GPG_KEY_ID" "$CHANGES_FILE"
        
        # Upload to Launchpad
        echo "Uploading to Launchpad..."
        dput aekant-ppa "$CHANGES_FILE"
    else
        echo "GPG_KEY_ID not provided, skipping signing and upload."
    fi
done

echo "Done."
